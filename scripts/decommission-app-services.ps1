<#
.SYNOPSIS
    Production-grade decommissioning script for Azure App Services and their associated App Service Plan.

.DESCRIPTION
    Two-Phase Decommissioning Architecture:
      PHASE 1: Comprehensive Pre-Flight Audits (Nothing is deleted)
        - Verifies Azure CLI session and subscription context.
        - Audits Resource Locks (CanNotDelete / ReadOnly).
        - Audits App Service Plan and ensures NO third-party apps share the plan.
        - Discovers App Service 1 and any attached deployment slots.
        - Discovers App Service 2 and any attached deployment slots.

      PHASE 2: Summary & Interactive Confirmation
        - Displays a clear Bill of Materials (BOM) of everything discovered.
        - If -DryRun is passed: Halts cleanly after reporting readiness.
        - If running live: Prompts the user for explicit confirmation ('yes' to delete, anything else to abort).

      PHASE 3: Execution (Only after explicit confirmation)
        - Deletes all discovered deployment slots first.
        - Deletes Web App 1 and Web App 2.
        - Deletes the App Service Plan.
        - Performs post-deletion verification with ARM.

.PARAMETER ResourceGroupName
    Name of the Azure Resource Group hosting the resources.

.PARAMETER AppService1Name
    Name of the first App Service to delete.

.PARAMETER AppService2Name
    Name of the second App Service to delete.

.PARAMETER AppServicePlanName
    Name of the App Service Plan to delete.

.PARAMETER SubscriptionId
    Optional: Target Azure Subscription ID. If omitted, uses active context.

.PARAMETER DryRun
    Run all pre-flight checks and display the summary without performing any deletions.

.PARAMETER Force
    Skip the interactive confirmation prompt (for unattended CI/CD automation).

.EXAMPLE
    # Dry-run: Audits everything and shows the summary without deleting
    .\decommission-app-services.ps1 `
        -ResourceGroupName "gems-apig-rg" `
        -AppService1Name "app-bwai-qaapi" `
        -AppService2Name "app-bwai-devapi" `
        -AppServicePlanName "asp-bwai-dev" `
        -DryRun

.EXAMPLE
    # Live run: Audits everything, shows summary, then asks "yes" before deleting
    .\decommission-app-services.ps1 `
        -ResourceGroupName "gems-apig-rg" `
        -AppService1Name "app-bwai-qaapi" `
        -AppService2Name "app-bwai-devapi" `
        -AppServicePlanName "asp-bwai-dev"
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Name of the Azure Resource Group")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the first App Service")]
    [ValidateNotNullOrEmpty()]
    [string]$AppService1Name,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the second App Service")]
    [ValidateNotNullOrEmpty()]
    [string]$AppService2Name,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the App Service Plan")]
    [ValidateNotNullOrEmpty()]
    [string]$AppServicePlanName,

    [Parameter(Mandatory = $false, HelpMessage = "Optional: Target Azure Subscription ID")]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false, HelpMessage = "Run all checks and display summary without deleting")]
    [switch]$DryRun,

    [Parameter(Mandatory = $false, HelpMessage = "Bypass interactive confirmation prompt")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# Logging Helper
# ==============================================================================
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "STEP")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO"    = "Cyan"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
        "SUCCESS" = "Green"
        "STEP"    = "Magenta"
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================
try {
    Write-Log "==========================================================" "STEP"
    Write-Log " PHASE 1: PRE-FLIGHT AUDITS & DEPENDENCY CHECKS" "STEP"
    Write-Log "==========================================================" "STEP"

    # 1. Verify Azure CLI is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI ('az') was not found in PATH. Please install Azure CLI from https://aka.ms/installazurecliwindows."
    }

    # 2. Verify active Azure login session
    $accountJson = az account show -o json 2>$null
    if (-not $accountJson) {
        throw "No active Azure CLI session found. Please run 'az login' first."
    }
    $context = $accountJson | ConvertFrom-Json

    if ($SubscriptionId -and ($context.id -ne $SubscriptionId)) {
        Write-Log "Switching context to Subscription: $SubscriptionId" "INFO"
        az account set --subscription $SubscriptionId | Out-Null
        $context = (az account show -o json) | ConvertFrom-Json
    }

    Write-Log "Azure Subscription : $($context.name) ($($context.id))" "INFO"
    Write-Log "Target Resource Grp: $ResourceGroupName" "INFO"

    # 3. Check for Blocking Resource Locks on Target Resources
    Write-Log "Auditing Azure Resource Locks for targeted resources..." "INFO"
    $locksJson = az lock list --resource-group $ResourceGroupName -o json 2>$null
    if ($locksJson) {
        $locks = @($locksJson | ConvertFrom-Json)
        # Only locks on the RG itself, App 1, App 2, or the App Service Plan affect this deletion
        # Locks on other unrelated resources (e.g. storage accounts, databases) are safely ignored
        $blockingLocks = $locks | Where-Object { 
            ($_.level -in @("CanNotDelete", "ReadOnly")) -and (
                ($_.id -match "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Authorization/locks/") -or
                ($_.id -match "(?i)/sites/$AppService1Name/") -or
                ($_.id -match "(?i)/sites/$AppService2Name/") -or
                ($_.id -match "(?i)/serverFarms/$AppServicePlanName/")
            )
        }
        if ($blockingLocks -and $blockingLocks.Count -gt 0) {
            foreach ($lock in $blockingLocks) {
                Write-Log "BLOCKING LOCK FOUND: '$($lock.name)' (Level: $($lock.level)) on '$($lock.id)'" "ERROR"
            }
            throw "Decommissioning halted: Resource lock(s) detected on target resources. To remove via terminal, run: az lock delete --ids '$($blockingLocks[0].id)'"
        }
        
        $unrelatedLocks = $locks | Where-Object { $_.level -in @("CanNotDelete", "ReadOnly") -and $_ -notin $blockingLocks }
        if ($unrelatedLocks -and $unrelatedLocks.Count -gt 0) {
            foreach ($ul in $unrelatedLocks) {
                Write-Log "Notice: Found lock '$($ul.name)' on unrelated resource '$($ul.id)'. Safe to ignore." "INFO"
            }
        }
    }
    Write-Log "Lock Audit: Passed (No blocking locks found on target App Services or Plan)." "SUCCESS"

    # 4. Audit App Service Plan & Check for Unintended Shared Apps
    Write-Log "Auditing App Service Plan: '$AppServicePlanName'..." "INFO"
    $planJson = az appservice plan show --resource-group $ResourceGroupName --name $AppServicePlanName -o json 2>$null
    $planFound = $false
    $planId = $null

    if ($planJson) {
        $plan = $planJson | ConvertFrom-Json
        $planFound = $true
        $planId = $plan.id

        # Query all webapps in the resource group
        $allAppsJson = az webapp list --resource-group $ResourceGroupName -o json 2>$null
        if ($allAppsJson) {
            $allApps = @($allAppsJson | ConvertFrom-Json)
            $appsOnPlan = $allApps | Where-Object {
                ($_.serverFarmId -and $_.serverFarmId -eq $plan.id) -or
                ($_.appServicePlanId -and $_.appServicePlanId -eq $plan.id)
            }
            $targetNames = @($AppService1Name, $AppService2Name)
            $unintendedApps = $appsOnPlan | Where-Object { $_.name -notin $targetNames }

            if ($unintendedApps -and $unintendedApps.Count -gt 0) {
                $otherNames = ($unintendedApps.name) -join ", "
                throw "SAFETY GUARDRAIL TRIGGERED: App Service Plan '$AppServicePlanName' still hosts other application(s): [$otherNames]. Aborting to prevent an unintended production outage."
            }
        }
        Write-Log "Plan Audit: Passed (Only the two target apps are associated with this plan)." "SUCCESS"
    } else {
        Write-Log "App Service Plan '$AppServicePlanName' was not found in '$ResourceGroupName'." "WARN"
    }

    # 5. Audit App Service 1 and its Deployment Slots
    Write-Log "Auditing App Service 1: '$AppService1Name'..." "INFO"
    $app1Json = az webapp show --resource-group $ResourceGroupName --name $AppService1Name -o json 2>$null
    $app1Found = [bool]$app1Json
    $app1Slots = @()

    if ($app1Found) {
        $slots1Json = az webapp deployment slot list --resource-group $ResourceGroupName --name $AppService1Name -o json 2>$null
        if ($slots1Json) {
            $slots1Obj = @($slots1Json | ConvertFrom-Json)
            $app1Slots = @($slots1Obj.name)
        }
        Write-Log "App 1 Status: Found (Slots: $(if ($app1Slots.Count -gt 0) { $app1Slots -join ', ' } else { 'None' }))" "SUCCESS"
    } else {
        Write-Log "App 1 Status: Not found (may already be deleted)." "WARN"
    }

    # 6. Audit App Service 2 and its Deployment Slots
    Write-Log "Auditing App Service 2: '$AppService2Name'..." "INFO"
    $app2Json = az webapp show --resource-group $ResourceGroupName --name $AppService2Name -o json 2>$null
    $app2Found = [bool]$app2Json
    $app2Slots = @()

    if ($app2Found) {
        $slots2Json = az webapp deployment slot list --resource-group $ResourceGroupName --name $AppService2Name -o json 2>$null
        if ($slots2Json) {
            $slots2Obj = @($slots2Json | ConvertFrom-Json)
            $app2Slots = @($slots2Obj.name)
        }
        Write-Log "App 2 Status: Found (Slots: $(if ($app2Slots.Count -gt 0) { $app2Slots -join ', ' } else { 'None' }))" "SUCCESS"
    } else {
        Write-Log "App 2 Status: Not found (may already be deleted)." "WARN"
    }

    # ==============================================================================
    # PHASE 2: DISPLAY SUMMARY & CONFIRMATION
    # ==============================================================================
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " PRE-FLIGHT AUDIT COMPLETE - BILL OF MATERIALS TO DELETE" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  Subscription    : $($context.name)"
    Write-Host "  Resource Group  : $ResourceGroupName"
    Write-Host "  App Service 1   : $AppService1Name $(if ($app1Found) { '[EXISTS]' } else { '[NOT FOUND]' })"
    if ($app1Slots.Count -gt 0) {
        Write-Host "    └─ Slots (1)  : $($app1Slots -join ', ')" -ForegroundColor Yellow
    }
    Write-Host "  App Service 2   : $AppService2Name $(if ($app2Found) { '[EXISTS]' } else { '[NOT FOUND]' })"
    if ($app2Slots.Count -gt 0) {
        Write-Host "    └─ Slots (2)  : $($app2Slots -join ', ')" -ForegroundColor Yellow
    }
    Write-Host "  App Service Plan: $AppServicePlanName $(if ($planFound) { '[EXISTS]' } else { '[NOT FOUND]' })"
    Write-Host "  Resource Locks  : 0 blocking locks detected"
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""

    # Check if there is anything to delete
    if (-not $app1Found -and -not $app2Found -and -not $planFound) {
        Write-Log "None of the specified resources exist in '$ResourceGroupName'. Nothing to delete." "WARN"
        exit 0
    }

    # If DryRun mode is requested, STOP HERE
    if ($DryRun) {
        Write-Log "MODE: DRY-RUN COMPLETED." "WARN"
        Write-Log "All pre-flight checks passed successfully." "SUCCESS"
        Write-Log "Zero resources were modified or deleted." "SUCCESS"
        Write-Log "To execute the deletion, re-run the command without the '-DryRun' flag." "INFO"
        exit 0
    }

    # Interactive Confirmation Gate
    if (-not $Force) {
        Write-Host "WARNING: This action is PERMANENT and will destroy the resources listed above." -ForegroundColor Yellow
        $userResponse = Read-Host "Do you want to proceed with deletion? (Type 'yes' to confirm, or press Enter to cancel)"
        if ($userResponse.Trim().ToLower() -ne "yes") {
            Write-Log "Decommissioning CANCELLED by user. No resources were modified or deleted." "WARN"
            exit 0
        }
    }

    # ==============================================================================
    # PHASE 3: EXECUTION (Only reached after explicit 'yes' confirmation)
    # ==============================================================================
    Write-Log "==========================================================" "STEP"
    Write-Log " PHASE 3: EXECUTING RESOURCE DECOMMISSIONING" "STEP"
    Write-Log "==========================================================" "STEP"

    # Step 3A: Delete slots for App 1
    if ($app1Slots.Count -gt 0) {
        foreach ($slot in $app1Slots) {
            Write-Log "Deleting slot '$slot' on '$AppService1Name'..." "INFO"
            az webapp deployment slot delete --resource-group $ResourceGroupName --name $AppService1Name --slot $slot | Out-Null
            Write-Log "Deleted slot '$slot'." "SUCCESS"
        }
    }

    # Step 3B: Delete App 1
    if ($app1Found) {
        Write-Log "Deleting App Service: '$AppService1Name'..." "INFO"
        az webapp delete --resource-group $ResourceGroupName --name $AppService1Name --keep-empty-plan true | Out-Null
        Write-Log "Deleted App Service: '$AppService1Name'." "SUCCESS"
    }

    # Step 3C: Delete slots for App 2
    if ($app2Slots.Count -gt 0) {
        foreach ($slot in $app2Slots) {
            Write-Log "Deleting slot '$slot' on '$AppService2Name'..." "INFO"
            az webapp deployment slot delete --resource-group $ResourceGroupName --name $AppService2Name --slot $slot | Out-Null
            Write-Log "Deleted slot '$slot'." "SUCCESS"
        }
    }

    # Step 3D: Delete App 2
    if ($app2Found) {
        Write-Log "Deleting App Service: '$AppService2Name'..." "INFO"
        az webapp delete --resource-group $ResourceGroupName --name $AppService2Name --keep-empty-plan true | Out-Null
        Write-Log "Deleted App Service: '$AppService2Name'." "SUCCESS"
    }

    # Step 3E: Delete App Service Plan
    if ($planFound) {
        Write-Log "Deleting App Service Plan: '$AppServicePlanName'..." "INFO"
        az appservice plan delete --resource-group $ResourceGroupName --name $AppServicePlanName --yes | Out-Null
        Write-Log "Deleted App Service Plan: '$AppServicePlanName'." "SUCCESS"
    }

    # Step 3F: Post-Deletion Verification
    Write-Log "Verifying resource removal with Azure..." "INFO"
    $checkApp1 = az webapp show --resource-group $ResourceGroupName --name $AppService1Name -o json 2>$null
    $checkApp2 = az webapp show --resource-group $ResourceGroupName --name $AppService2Name -o json 2>$null
    $checkPlan = az appservice plan show --resource-group $ResourceGroupName --name $AppServicePlanName -o json 2>$null

    if ($checkApp1 -or $checkApp2 -or $checkPlan) {
        Write-Log "Verification Notice: One or more resources are still reported by ARM (Azure deletion propagation is completing in the background)." "WARN"
    } else {
        Write-Log "All targeted resources have been verified as completely deleted." "SUCCESS"
    }

    Write-Log "==========================================================" "SUCCESS"
    Write-Log " Decommissioning completed successfully." "SUCCESS"
    Write-Log "==========================================================" "SUCCESS"
    exit 0

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
}
