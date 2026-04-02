#!/bin/bash
# Build, push and deploy the Azure Container Apps Job consumer
set -euo pipefail
source "$(dirname "$0")/../../.env"

SCRIPT_DIR="$(dirname "$0")"

# ── 1. Build & push image ────────────────────────────────────────────────────
echo "Building Docker image: egch/job-consumer:latest"
docker build -t egch/job-consumer:latest "$SCRIPT_DIR/../../job_aeh"

echo "Pushing to Docker Hub"
docker push egch/job-consumer:latest

# ── 2. Create checkpoint container (if not exists) ───────────────────────────
echo "Creating checkpoint container (if not exists)"
az storage container create \
  --name eventhub-checkpoints \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --auth-mode login \
  --output table

# ── 3. Deploy Container Apps Job ─────────────────────────────────────────────
echo "Deploying Container Apps Job: $ACJ_JOB_NAME"

YAML_FILE="/tmp/acj_consumer_deploy.yaml"
rm -f "$YAML_FILE"

EH_ESCAPED=$(printf '%s' "$EVENT_HUB_CONNECTION_STRING" | sed 's/[&/\]/\\&/g')
CS_ESCAPED=$(printf '%s' "$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" | sed 's/[&/\]/\\&/g')

sed \
  -e "s|EVENTHUB_CONNECTION_PLACEHOLDER|${EH_ESCAPED}|g" \
  -e "s|CHECKPOINT_STORAGE_PLACEHOLDER|${CS_ESCAPED}|g" \
  -e "s|ACJ_EVENTHUB_NAME_PLACEHOLDER|${ACJ_EVENTHUB_NAME}|g" \
  "$SCRIPT_DIR/acj_consumer.yaml" > "$YAML_FILE"

az containerapp job create \
  --name "$ACJ_JOB_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --environment "$AZURE_CONTAINER_APP_ENV" \
  --yaml "$YAML_FILE" \
  --output table

rm -f "$YAML_FILE"

echo "Done."
