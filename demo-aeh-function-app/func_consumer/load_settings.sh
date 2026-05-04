#!/bin/bash
# Populates local.settings.json from the root .env file for local development.
# Requires az login — DefaultAzureCredential picks up the logged-in identity
# which must have the Azure Event Hubs Data Receiver role on the namespace.
set -euo pipefail
source "$(dirname "$0")/../az-cli/.env"

cat > "$(dirname "$0")/local.settings.json" <<EOF
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING}",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "EVENT_HUB_CONNECTION__fullyQualifiedNamespace": "${AZURE_EVENTHUB_NAMESPACE}.servicebus.windows.net",
    "EVENT_HUB_NAME": "${AZURE_EVENTHUB_NAME}",
    "EVENT_HUB_CONSUMER_GROUP": "\$Default"
  }
}
EOF

echo "local.settings.json updated."
