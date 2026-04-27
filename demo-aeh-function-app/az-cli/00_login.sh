#!/bin/bash
# Login to Azure and set the subscription
set -euo pipefail
source "$(dirname "$0")/.env"

az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show
