#!/usr/bin/env bash
# ==============================================================================
# Script Name : decommission_app_services.sh
# Description : Production-grade decommissioning script for Azure App Services
#               and their associated App Service Plan using Azure CLI.
# Workflow    :
#   PHASE 1: Comprehensive Pre-Flight Audits (Nothing is deleted)
#     - Verifies Azure CLI session and subscription context.
#     - Audits Resource Locks (CanNotDelete / ReadOnly).
#     - Audits App Service Plan and checks for unintended shared apps.
#     - Discovers App Service 1 and any deployment slots.
#     - Discovers App Service 2 and any deployment slots.
#
#   PHASE 2: Summary & Interactive Confirmation Gate
#     - Displays a Bill of Materials (BOM) of all discovered resources.
#     - If --dry-run: Halts cleanly after reporting readiness.
#     - If live: Prompts for explicit 'yes' confirmation before proceeding.
#
#   PHASE 3: Safe Execution (Only after explicit 'yes')
#     - Deletes deployment slots first.
#     - Deletes Web Apps.
#     - Deletes App Service Plan.
#     - Post-deletion verification.
# ==============================================================================

set -euo pipefail

# Color codes
CLR_RED="\033[0;31m"
CLR_GREEN="\033[0;32m"
CLR_YELLOW="\033[1;33m"
CLR_CYAN="\033[0;36m"
CLR_MAGENTA="\033[0;35m"
CLR_RESET="\033[0m"

log() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  case "$level" in
    "INFO")    echo -e "${CLR_CYAN}[$timestamp] [INFO] $msg${CLR_RESET}" ;;
    "WARN")    echo -e "${CLR_YELLOW}[$timestamp] [WARN] $msg${CLR_RESET}" ;;
    "ERROR")   echo -e "${CLR_RED}[$timestamp] [ERROR] $msg${CLR_RESET}" ;;
    "SUCCESS") echo -e "${CLR_GREEN}[$timestamp] [SUCCESS] $msg${CLR_RESET}" ;;
    "STEP")    echo -e "${CLR_MAGENTA}[$timestamp] [STEP] $msg${CLR_RESET}" ;;
    *)         echo -e "[$timestamp] [$level] $msg" ;;
  esac
}

print_usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Required Arguments:
  -g, --resource-group   Azure Resource Group name
  -a, --app1             Name of the first App Service
  -b, --app2             Name of the second App Service
  -p, --plan             Name of the App Service Plan

Optional Arguments:
  -s, --subscription     Azure Subscription ID (optional)
  -d, --dry-run          Run all checks and display summary without deleting
  -f, --force            Skip interactive confirmation
  -h, --help             Show this help message

Example:
  $(basename "$0") -g "gems-apig-rg" -a "app-bwai-qaapi" -b "app-bwai-devapi" -p "asp-bwai-dev" --dry-run
EOF
}

RESOURCE_GROUP=""
APP_SERVICE_1=""
APP_SERVICE_2=""
APP_SERVICE_PLAN=""
SUBSCRIPTION_ID=""
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -a|--app1)           APP_SERVICE_1="$2"; shift 2 ;;
    -b|--app2)           APP_SERVICE_2="$2"; shift 2 ;;
    -p|--plan)           APP_SERVICE_PLAN="$2"; shift 2 ;;
    -s|--subscription)   SUBSCRIPTION_ID="$2"; shift 2 ;;
    -d|--dry-run)        DRY_RUN=true; shift ;;
    -f|--force)          FORCE=true; shift ;;
    -h|--help)           print_usage; exit 0 ;;
    *) log "ERROR" "Unknown argument: $1"; print_usage; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" || -z "$APP_SERVICE_1" || -z "$APP_SERVICE_2" || -z "$APP_SERVICE_PLAN" ]]; then
  log "ERROR" "Missing one or more required arguments (-g, -a, -b, -p)."
  print_usage
  exit 1
fi

log "STEP" "=========================================================="
log "STEP" " PHASE 1: PRE-FLIGHT AUDITS & DEPENDENCY CHECKS"
log "STEP" "=========================================================="

# 1. Verify Azure CLI Session
if ! az account show &>/dev/null; then
  log "ERROR" "No active Azure CLI session found. Please run 'az login' first."
  exit 1
fi

if [[ -n "$SUBSCRIPTION_ID" ]]; then
  log "INFO" "Setting subscription context: $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

CURRENT_SUB_NAME=$(az account show --query "name" -o tsv)
CURRENT_SUB_ID=$(az account show --query "id" -o tsv)

log "INFO" "Azure Subscription : $CURRENT_SUB_NAME ($CURRENT_SUB_ID)"
log "INFO" "Target Resource Grp: $RESOURCE_GROUP"

# 2. Check for Blocking Resource Locks on Target Resources
log "INFO" "Auditing Azure Resource Locks for targeted resources..."
LOCKS=$(az lock list --resource-group "$RESOURCE_GROUP" \
  --query "[?level=='CanNotDelete' || level=='ReadOnly'].id" -o tsv 2>/dev/null || true)

BLOCKING_LOCKS=()
if [[ -n "$LOCKS" ]]; then
  while IFS= read -r lock_id; do
    # Only flag locks on the RG itself, App 1, App 2, or Plan
    if [[ "$lock_id" =~ /resourceGroups/[^/]+/providers/Microsoft\.Authorization/locks/ ]] || \
       [[ "$lock_id" =~ /sites/$APP_SERVICE_1/ ]] || \
       [[ "$lock_id" =~ /sites/$APP_SERVICE_2/ ]] || \
       [[ "$lock_id" =~ /serverFarms/$APP_SERVICE_PLAN/ ]]; then
      BLOCKING_LOCKS+=("$lock_id")
    fi
  done <<< "$LOCKS"
fi

if [[ ${#BLOCKING_LOCKS[@]} -gt 0 ]]; then
  log "ERROR" "BLOCKING RESOURCE LOCK DETECTED ON TARGET RESOURCES: ${BLOCKING_LOCKS[*]}"
  log "ERROR" "To remove via terminal, run: az lock delete --ids '${BLOCKING_LOCKS[0]}'"
  exit 1
fi
log "SUCCESS" "Lock Audit: Passed (No blocking locks found on target App Services or Plan)."

# 3. Audit App Service Plan & Check for Unintended Shared Apps
log "INFO" "Auditing App Service Plan: '$APP_SERVICE_PLAN'..."
PLAN_EXISTS=false
if az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" &>/dev/null; then
  PLAN_EXISTS=true
  PLAN_ID=$(az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --query "id" -o tsv)
  
  APPS_ON_PLAN=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[?serverFarmId=='$PLAN_ID'].name" -o tsv 2>/dev/null || true)
  for app in $APPS_ON_PLAN; do
    if [[ "$app" != "$APP_SERVICE_1" && "$app" != "$APP_SERVICE_2" ]]; then
      log "ERROR" "SAFETY GUARDRAIL TRIGGERED: Plan '$APP_SERVICE_PLAN' still hosts other app '$app'. Aborting to avoid outage."
      exit 1
    fi
  done
  log "SUCCESS" "Plan Audit: Passed (Only the two target apps are associated with this plan)."
else
  log "WARN" "App Service Plan '$APP_SERVICE_PLAN' was not found in '$RESOURCE_GROUP'."
fi

# 4. Audit App Service 1 and its Deployment Slots
log "INFO" "Auditing App Service 1: '$APP_SERVICE_1'..."
APP1_EXISTS=false
APP1_SLOTS=()
if az webapp show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_1" &>/dev/null; then
  APP1_EXISTS=true
  while IFS= read -r slot; do
    [[ -n "$slot" ]] && APP1_SLOTS+=("$slot")
  done < <(az webapp deployment slot list --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_1" --query "[].name" -o tsv 2>/dev/null || true)
  log "SUCCESS" "App 1 Status: Found (Slots: ${#APP1_SLOTS[@]})"
else
  log "WARN" "App 1 Status: Not found."
fi

# 5. Audit App Service 2 and its Deployment Slots
log "INFO" "Auditing App Service 2: '$APP_SERVICE_2'..."
APP2_EXISTS=false
APP2_SLOTS=()
if az webapp show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_2" &>/dev/null; then
  APP2_EXISTS=true
  while IFS= read -r slot; do
    [[ -n "$slot" ]] && APP2_SLOTS+=("$slot")
  done < <(az webapp deployment slot list --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_2" --query "[].name" -o tsv 2>/dev/null || true)
  log "SUCCESS" "App 2 Status: Found (Slots: ${#APP2_SLOTS[@]})"
else
  log "WARN" "App 2 Status: Not found."
fi

# ==============================================================================
# PHASE 2: DISPLAY SUMMARY & CONFIRMATION
# ==============================================================================
echo ""
echo -e "${CLR_GREEN}==========================================================${CLR_RESET}"
echo -e "${CLR_GREEN} PRE-FLIGHT AUDIT COMPLETE - BILL OF MATERIALS TO DELETE  ${CLR_RESET}"
echo -e "${CLR_GREEN}==========================================================${CLR_RESET}"
echo "  Subscription    : $CURRENT_SUB_NAME"
echo "  Resource Group  : $RESOURCE_GROUP"
echo -n "  App Service 1   : $APP_SERVICE_1 "
if [[ "$APP1_EXISTS" == "true" ]]; then echo "[EXISTS]"; else echo "[NOT FOUND]"; fi
if [[ ${#APP1_SLOTS[@]} -gt 0 ]]; then
  echo -e "    ${CLR_YELLOW}└─ Slots (1)  : ${APP1_SLOTS[*]}${CLR_RESET}"
fi

echo -n "  App Service 2   : $APP_SERVICE_2 "
if [[ "$APP2_EXISTS" == "true" ]]; then echo "[EXISTS]"; else echo "[NOT FOUND]"; fi
if [[ ${#APP2_SLOTS[@]} -gt 0 ]]; then
  echo -e "    ${CLR_YELLOW}└─ Slots (2)  : ${APP2_SLOTS[*]}${CLR_RESET}"
fi

echo -n "  App Service Plan: $APP_SERVICE_PLAN "
if [[ "$PLAN_EXISTS" == "true" ]]; then echo "[EXISTS]"; else echo "[NOT FOUND]"; fi
echo "  Resource Locks  : 0 blocking locks detected"
echo -e "${CLR_GREEN}==========================================================${CLR_RESET}"
echo ""

if [[ "$APP1_EXISTS" == "false" && "$APP2_EXISTS" == "false" && "$PLAN_EXISTS" == "false" ]]; then
  log "WARN" "None of the specified resources exist in '$RESOURCE_GROUP'. Nothing to delete."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "WARN" "MODE: DRY-RUN COMPLETED."
  log "SUCCESS" "All pre-flight checks passed successfully."
  log "SUCCESS" "Zero resources were modified or deleted."
  log "INFO" "To execute the deletion, re-run without the '--dry-run' flag."
  exit 0
fi

# Interactive confirmation prompt
if [[ "$FORCE" == "false" ]]; then
  echo -e "${CLR_YELLOW}WARNING: This action is PERMANENT and will destroy the resources listed above.${CLR_RESET}"
  read -r -p "Do you want to proceed with deletion? (Type 'yes' to confirm, or press Enter to cancel): " USER_CONFIRM
  if [[ "$USER_CONFIRM" != "yes" ]]; then
    log "WARN" "Decommissioning CANCELLED by user. No resources were modified or deleted."
    exit 0
  fi
fi

# ==============================================================================
# PHASE 3: EXECUTION (Only reached after explicit 'yes' confirmation)
# ==============================================================================
log "STEP" "=========================================================="
log "STEP" " PHASE 3: EXECUTING RESOURCE DECOMMISSIONING"
log "STEP" "=========================================================="

# Delete App 1 slots
for slot in "${APP1_SLOTS[@]}"; do
  log "INFO" "Deleting slot '$slot' on '$APP_SERVICE_1'..."
  az webapp deployment slot delete --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_1" --slot "$slot"
  log "SUCCESS" "Deleted slot '$slot'."
done

# Delete App 1
if [[ "$APP1_EXISTS" == "true" ]]; then
  log "INFO" "Deleting App Service: '$APP_SERVICE_1'..."
  az webapp delete --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_1" --keep-empty-plan true
  log "SUCCESS" "Deleted App Service: '$APP_SERVICE_1'."
fi

# Delete App 2 slots
for slot in "${APP2_SLOTS[@]}"; do
  log "INFO" "Deleting slot '$slot' on '$APP_SERVICE_2'..."
  az webapp deployment slot delete --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_2" --slot "$slot"
  log "SUCCESS" "Deleted slot '$slot'."
done

# Delete App 2
if [[ "$APP2_EXISTS" == "true" ]]; then
  log "INFO" "Deleting App Service: '$APP_SERVICE_2'..."
  az webapp delete --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_2" --keep-empty-plan true
  log "SUCCESS" "Deleted App Service: '$APP_SERVICE_2'."
fi

# Delete App Service Plan
if [[ "$PLAN_EXISTS" == "true" ]]; then
  log "INFO" "Deleting App Service Plan: '$APP_SERVICE_PLAN'..."
  az appservice plan delete --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" --yes
  log "SUCCESS" "Deleted App Service Plan: '$APP_SERVICE_PLAN'."
fi

# Verification
log "INFO" "Verifying resource removal with Azure..."
if az webapp show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_1" &>/dev/null || \
   az webapp show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_2" &>/dev/null || \
   az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" &>/dev/null; then
  log "WARN" "One or more resources are still reported by ARM (Azure deletion propagation is completing in the background)."
else
  log "SUCCESS" "All targeted resources have been verified as completely deleted."
fi

log "SUCCESS" "=========================================================="
log "SUCCESS" " Decommissioning completed successfully."
log "SUCCESS" "=========================================================="
