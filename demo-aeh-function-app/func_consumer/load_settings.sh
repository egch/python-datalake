#!/bin/bash
# Populates local.settings.json from the root .env file for local development.
set -euo pipefail
source "$(dirname "$0")/../az-cli/.env"

cat > "$(dirname "$0")/local.settings.json" <<EOF
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING}",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "EVENT_HUB_CONNECTION_STRING": "${EVENT_HUB_CONNECTION_STRING}",
    "EVENT_HUB_NAME": "${AZURE_EVENTHUB_NAME}",
    "EVENT_HUB_CONSUMER_GROUP": "\$Default"
  }
}
EOF

echo "local.settings.json updated."
