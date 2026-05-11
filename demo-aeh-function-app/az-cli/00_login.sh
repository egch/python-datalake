#!/bin/bash
# Login to Azure and set the subscription
set -euo pipefail
export MSYS_NO_PATHCONV=1  # prevent Git Bash from mangling /subscriptions/... Azure resource IDs into Windows paths
source "$(dirname "$0")/.env"

az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show
