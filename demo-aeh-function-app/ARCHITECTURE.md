# Architecture Deep Dive — Azure Function App + Private Event Hub

This document explains **why** every component in this architecture exists. The scenario is a common corporate requirement: consume Azure Event Hub from an Azure Function App, with the Event Hub locked down to private network access only, and all authentication done through managed identity (no SAS keys, no connection strings).

---

## The Goal

```
User uploads a file
    → Azure Storage (blob container)
        → Event Grid (blob event)
            → Azure Event Hub
                → Azure Function App (process the event)
```

Simple in theory. Complex in practice because of two constraints:
1. The Event Hub **must not be reachable from the public internet**
2. The Function App **must not use SAS keys** to authenticate

---

## Full Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│  Azure (global backbone)                                             │
│                                                                      │
│  Storage Account (saehfa)                                            │
│  └── container-eh-fa                                                 │
│           │ BlobCreated / BlobUpdated / BlobDeleted                  │
│           ▼                                                          │
│  Event Grid System Topic (evgt-storage-eh-fa)                        │
│  └── system-assigned managed identity                                │
│       └── role: Azure Event Hubs Data Sender (on evhns-eh-fa)        │
│           │ trusted Microsoft services bypass (no public IP needed)  │
│           ▼                                                          │
│  Event Hub Namespace (evhns-eh-fa)          PublicNetworkAccess:     │
│  └── evh-eh-fa (2 partitions)               Disabled                │
│                                ▲                                     │
│                                │ private tunnel                      │
│  ┌─────────────────────────────┼──────────────────────────────────┐  │
│  │  VNet: vnet-eh-fa (10.0.0.0/16)          │                    │  │
│  │                                          │                    │  │
│  │  snet-eh-fa-pe (10.0.2.0/24)             │                    │  │
│  │  └── Private Endpoint NIC (10.0.2.4) ───┘                    │  │
│  │       ↑ DNS: evhns-eh-fa.servicebus.windows.net → 10.0.2.4   │  │
│  │                                                               │  │
│  │  snet-eh-fa (10.0.1.0/24)                                     │  │
│  │  └── Azure Function App (func-eh-fa)                          │  │
│  │       └── UAMI: uami-eh-fa                                    │  │
│  │            └── role: Azure Event Hubs Data Receiver           │  │
│  │                                                               │  │
│  │  Private DNS Zone: privatelink.servicebus.windows.net         │  │
│  │  └── linked to vnet-eh-fa                                     │  │
│  │  └── A record: evhns-eh-fa → 10.0.2.4                        │  │
│  └───────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Why Each Component Exists

### 1. Virtual Network (VNet) — `vnet-eh-fa`

The VNet is the private network boundary. Resources inside a VNet can communicate with each other using private IPs, isolated from the internet. It is the foundation everything else builds on.

Without a VNet there is no private network to put the Function App or the private endpoint into.

---

### 2. Two Subnets

**Why are there two separate subnets?**

| Subnet | CIDR | Purpose |
|---|---|---|
| `snet-eh-fa` | 10.0.1.0/24 | Function App outbound traffic (VNet integration) |
| `snet-eh-fa-pe` | 10.0.2.0/24 | Private Endpoint NIC |

They must be **separate** because:

- The Function App subnet must be **delegated** to `Microsoft.Web/serverFarms` — this is a hard Azure requirement for VNet integration. A delegated subnet cannot have private endpoints in it.
- The Private Endpoint NIC needs a subnet that has `privateLinkServiceNetworkPolicies` disabled (Azure does this automatically when you deploy a private endpoint), which conflicts with subnet delegation.
- Keeping them separate also makes it easier to apply different NSG rules to each in the future.

---

### 3. VNet Integration on the Function App (outbound)

The Function App is integrated with `snet-eh-fa` via **VNet integration** (not to be confused with a private endpoint, which handles inbound access to a service).

**Key insight:** Event Hub does not push events to the Function App. The Function App opens a **persistent outbound AMQP connection** to Event Hub and continuously polls:

```
Function App ──(outbound AMQP 5671/5672)──▶ Event Hub
    "any new messages?"
    ◀── "yes, here are 3" → function invoked
    "any new messages?"
    ◀── "no" → wait...
```

This means the integration is on the **outbound** side (Function App → Event Hub), not the inbound side. VNet integration routes the Function App's outbound traffic through the VNet so it can reach the private endpoint.

`WEBSITE_VNET_ROUTE_ALL=1` is also required — by default VNet integration only routes RFC1918 (private) addresses through the VNet. This setting forces **all** outbound traffic (including DNS queries to `*.servicebus.windows.net`) through the VNet, which is necessary for private DNS resolution to work.

---

### 4. Private Endpoint — `pe-evhns-eh-fa`

The Event Hub namespace has public network access disabled (`PublicNetworkAccess: Disabled`). Its public endpoint (`evhns-eh-fa.servicebus.windows.net`) is closed. No traffic from the public internet can reach it, including from the Function App, which runs on Microsoft's infrastructure but outside our VNet.

A **private endpoint** solves this by:
1. Creating a **Network Interface Card (NIC)** with a private IP (e.g. `10.0.2.4`) inside our VNet
2. Wiring that NIC directly to the Event Hub namespace through Microsoft's internal backbone

Now there is a door to Event Hub **inside** our VNet. The Function App can reach Event Hub by connecting to `10.0.2.4` — without that traffic ever touching the public internet or the public endpoint.

```
Before private endpoint:
  Function App → evhns-eh-fa.servicebus.windows.net → public IP → BLOCKED

After private endpoint:
  Function App → 10.0.2.4 (PE NIC in our VNet) → private tunnel → Event Hub ✓
```

**The Function App does not need to know any of this.** It still connects to `evhns-eh-fa.servicebus.windows.net` as if nothing changed. The private DNS zone handles the redirect transparently.

---

### 5. Private DNS Zone — `privatelink.servicebus.windows.net`

The private endpoint creates a private IP, but the Function App still looks up `evhns-eh-fa.servicebus.windows.net` by name. Without a DNS override, that name resolves to the **public IP** of the Event Hub namespace — which is blocked.

The private DNS zone overrides DNS resolution **within the VNet**:

```
DNS query from inside vnet-eh-fa:
  evhns-eh-fa.servicebus.windows.net
    → CNAME → evhns-eh-fa.privatelink.servicebus.windows.net
    → A record (from private DNS zone) → 10.0.2.4  ✓

DNS query from outside the VNet:
  evhns-eh-fa.servicebus.windows.net
    → CNAME → evhns-eh-fa.privatelink.servicebus.windows.net
    → A record (from public DNS) → 52.x.x.x (public IP) → BLOCKED
```

The zone is **linked to the VNet** — it only affects DNS queries originating from within `vnet-eh-fa`. Queries from outside resolve to the public IP as normal.

The **DNS zone group** (created in script 06, step 5) automatically registers an A record in the zone pointing to the private endpoint's IP. This removes the need to manually look up and enter the IP.

---

### 6. Event Grid System Topic with Managed Identity

**Why not a simple Event Grid subscription with a webhook?**

Event Hub's endpoint is also blocked to Event Grid. Event Grid is a Microsoft-managed service running on Microsoft's backbone — it is **not** inside our VNet and cannot use our private endpoint.

Azure provides a special exception: **trusted Microsoft services bypass**. When enabled on an Event Hub namespace, it allows specific Azure services (including Event Grid) to reach the namespace even when public network access is disabled.

**The catch:** the trusted services bypass only works when Event Grid authenticates with a **managed identity + RBAC**. A SAS-key-based delivery (the default) is rejected even with the bypass enabled.

This is why script 04 creates a **system topic** with a **system-assigned managed identity**, assigns it the `Azure Event Hubs Data Sender` role on the namespace, and configures `deliveryWithResourceIdentity`. The delivery path is:

```
Event Grid system topic
  └── system-assigned managed identity
       └── presents identity token to Event Hub
            └── Event Hub checks: does this identity have Data Sender role? → yes ✓
                 └── accepts delivery (via trusted bypass, no public IP needed)
```

---

### 7. User-Assigned Managed Identity (UAMI) — `uami-eh-fa`

The Function App needs to authenticate to Event Hub to **read** messages. SAS keys are disabled (`DisableLocalAuth: true`) so it must use a managed identity.

**The UAMI requires two completely separate operations — both are mandatory:**

| Operation | Azure CLI command | What it does |
|---|---|---|
| Role assignment on Event Hub namespace | `az role assignment create --scope <namespace-id> --role "Azure Event Hubs Data Receiver"` | Grants the UAMI **permission** to read from Event Hub |
| Attach UAMI to the Function App | `az functionapp identity assign --identities <uami-resource-id>` | Gives the Function App **access to use** that identity |

Think of the UAMI as a **badge**:
- The **role assignment** loads permissions onto the badge (the badge grants access to Event Hub)
- **Attaching it to the Function App** gives the badge to the Function App so it can present it when authenticating

One without the other does not work:
- UAMI attached to Function App but **no role on Event Hub** → Function App can present the identity but Event Hub rejects it (unauthorized)
- UAMI has role on Event Hub but **not attached to Function App** → Function App cannot present the identity at all (it does not hold it)

The app setting `EVENT_HUB_CONNECTION__clientId` then tells the Functions runtime **which badge to use**, since a Function App can have multiple UAMIs attached.

**Why UAMI instead of System-Assigned Managed Identity (SAMI)?**

| | SAMI | UAMI |
|---|---|---|
| Lifecycle | Tied to the Function App | Independent Azure resource |
| `principalId` on redeploy | Changes (new identity) | Stays the same |
| RBAC role assignments | Must be redone after redeploy | Survive Function App deletion |
| Can be pre-provisioned | No | Yes |
| Can be shared across resources | No | Yes |

In a corporate environment (and in this demo), the Function App may be deleted and recreated. With a SAMI, every recreation breaks the RBAC role assignments and requires re-running the identity configuration. With a UAMI, the identity and its permissions survive the Function App lifecycle.

The UAMI is identified to the Azure Functions runtime via the app setting `EVENT_HUB_CONNECTION__clientId`. This is required because a Function App can have **multiple UAMIs attached** — without the `clientId`, the runtime would not know which identity to use for Event Hub authentication.

---

### 8. Elastic Premium App Service Plan (EP1)

The Consumption plan (the cheapest option) cannot be used here.

The Event Hub trigger requires the Function App host to maintain a **persistent outbound AMQP connection** to Event Hub, alive 24/7. The Consumption plan scales to zero between invocations and cannot keep persistent outbound VNet connections alive. Elastic Premium (EP1 minimum) is required for:
- VNet integration support
- Persistent outbound connections (no cold-start severing of the AMQP connection)
- The trigger to work reliably at low message volumes

---

### 9. Two Managed Identities on the Same Namespace

It can be confusing to see two identities on the same Event Hub namespace, doing opposite things:

| Identity | Type | Role | Direction |
|---|---|---|---|
| `evgt-storage-eh-fa` (Event Grid system topic) | System-assigned | `Azure Event Hubs Data Sender` | **Writes** events to Event Hub |
| `uami-eh-fa` (Function App) | User-assigned | `Azure Event Hubs Data Receiver` | **Reads** events from Event Hub |

Event Grid publishes, the Function App consumes. Both authenticate to the same Event Hub namespace with managed identity, just with different roles.

---

## Data Flow — Step by Step

```
1. User uploads a blob to container-eh-fa in storage account saehfa

2. Storage emits a BlobCreated event to Event Grid

3. Event Grid system topic (evgt-storage-eh-fa) receives the event
   - Its system-assigned managed identity authenticates to Event Hub
   - Event Hub checks the identity has Azure Event Hubs Data Sender role → ✓
   - Event Hub accepts the message via trusted services bypass (public network disabled)

4. Event Hub stores the message in partition 0 or 1 of evh-eh-fa

5. Function App (inside VNet, snet-eh-fa) polls Event Hub:
   - DNS query: evhns-eh-fa.servicebus.windows.net
   - Private DNS zone intercepts: returns 10.0.2.4 (private endpoint NIC)
   - AMQP connection to 10.0.2.4 → private endpoint → Event Hub
   - UAMI uami-eh-fa presents identity token
   - Event Hub checks: Azure Event Hubs Data Receiver role → ✓
   - Event Hub delivers the message

6. Azure Functions host invokes process_blob_event()
   - Logs event type, subject, blob URL
   - Commits checkpoint to AzureWebJobsStorage blob container
```

---

## Q&A

**Q: Why does the Function App need a subnet if it is already in Azure?**

Being "in Azure" does not mean being in a private network. By default, Azure Functions run in Microsoft's multitenant infrastructure with a public IP address. VNet integration gives the Function App a presence inside your private VNet so it can reach resources (like a private endpoint) that are not accessible from the public internet.

---

**Q: Why can't I just whitelist the Function App's IP on the Event Hub firewall?**

Azure Functions on a Consumption or Elastic Premium plan do not have a stable outbound IP. The IP can change at any time. Even if you pinned it today, it could break tomorrow. VNet integration with a private endpoint is the stable, supportable solution.

---

**Q: Why two subnets? Can I put everything in one?**

No. Azure enforces that a subnet with VNet integration (delegated to `Microsoft.Web/serverFarms`) cannot also host a private endpoint NIC, because the delegation disables the network policies that private endpoints require. They must be in separate subnets.

---

**Q: Why does DNS matter here? Can't the Function App just use the private IP directly?**

Technically yes, but it would require hardcoding the private endpoint IP into your connection string. If the private endpoint is recreated (e.g. after a disaster recovery event), the IP could change and your connection would break. Using the hostname and letting DNS resolve it keeps the configuration portable and resilient. The Azure Functions SDK also expects a fully qualified namespace name, not a raw IP.

---

**Q: Why is `WEBSITE_VNET_ROUTE_ALL=1` needed?**

By default, VNet integration only routes traffic destined for **private address ranges** (RFC1918: 10.x, 172.16-31.x, 192.168.x) through the VNet. DNS queries for `*.servicebus.windows.net` go to Azure's public DNS resolvers, which return the public IP. By setting `WEBSITE_VNET_ROUTE_ALL=1`, all outbound traffic — including DNS queries — is routed through the VNet, so the private DNS zone intercepts the lookup and returns the private IP.

---

**Q: Why does Event Grid need a system topic with managed identity? Why not a direct subscription?**

A direct Event Grid subscription delivers to an endpoint using either a webhook (HTTP POST) or a SAS key for Event Hub. Both require the destination to have public network access enabled or be reachable from Event Grid's public IPs. Since the Event Hub has public access disabled, neither works.

The **trusted Microsoft services bypass** is the only mechanism that lets Event Grid reach a private Event Hub — but it only applies when Event Grid authenticates with a **managed identity + RBAC**. A system topic is required to create a system-assigned managed identity for Event Grid.

---

**Q: Why a system-assigned identity for Event Grid and a user-assigned identity for the Function App?**

Event Grid system topics only support **system-assigned** managed identities — you cannot attach a UAMI to an Event Grid system topic. So there is no choice for Event Grid.

For the Function App, a UAMI is preferred because its `principalId` does not change when the Function App is deleted and recreated, avoiding broken RBAC assignments.

---

**Q: What happens if I delete and recreate the Function App?**

With UAMI: the UAMI still exists, its `principalId` is unchanged, and its role assignment on the Event Hub namespace is still valid. Run script 05 again and everything works immediately.

With SAMI (old approach): the new Function App gets a new system-assigned identity with a new `principalId`. The old role assignment is now orphaned (points to a deleted identity). You must re-run script 07 to create a new role assignment for the new identity.

---

**Q: Can I skip the private endpoint and just leave public network access enabled?**

Yes. Scripts 01–05 work with public network access enabled (the default). Script 06 is the one that locks it down. If you only want to test the Function App + Event Hub integration without the private networking layer, you can stop after script 05.

---

**Q: Why does the portal say "data operations will not work" when public access is disabled?**

The Azure Portal's Event Hub data explorer connects to the data plane over the **public endpoint**. When public access is disabled, the portal cannot send or receive messages. This does not affect the Function App (which goes through the private endpoint) or Event Grid (which uses the trusted bypass). Use `az webapp log tail` to observe function invocations, or check **Metrics → Incoming Messages** in the portal (which uses the management plane, still accessible).

---

**Q: The UAMI is already configured — do I need to do anything else to wire it to the Function App?**

Yes — two things, both required:

1. **Role assignment on the Event Hub namespace** — grants the UAMI permission to read messages (`Azure Event Hubs Data Receiver` role). This is set on the Event Hub side.
2. **Attach the UAMI to the Function App** (`az functionapp identity assign`) — gives the Function App access to use that identity. This is set on the Function App side.

These are independent operations and easy to miss one of. If the role is assigned but the UAMI is not attached, the Function App cannot present the identity. If the UAMI is attached but has no role, Event Hub will reject the authentication.

---

**Q: What role does `EVENT_HUB_CONNECTION__clientId` play?**

When multiple UAMIs are attached to a Function App, the Azure Functions SDK does not know which one to use for a given connection. The `__clientId` suffix on the connection setting tells the SDK: "use the managed identity with this specific client ID for this connection." Without it, the runtime falls back to `DefaultAzureCredential`, which may pick the wrong identity or fail entirely.

---

**Q: Why Elastic Premium EP1 and not a cheaper plan?**

The Event Hub trigger requires a persistent outbound AMQP connection to poll for messages. The Consumption plan scales to zero and cannot maintain persistent VNet connections. EP1 is the minimum plan that supports both VNet integration and persistent connections. The trade-off is cost: EP1 runs 24/7 regardless of activity.

---

**Q: What is the `azure-webjobs-eventhub` blob container for?**

The Azure Functions runtime stores **checkpoints** in blob storage to track which Event Hub messages have already been processed. Each partition (0 and 1 in this demo) has a checkpoint blob. If the Function App restarts, it resumes from the last checkpoint rather than reprocessing all messages from the beginning. This is why `AzureWebJobsStorage` must be set correctly — without it, the trigger cannot start.
