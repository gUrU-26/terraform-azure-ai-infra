<#
.SYNOPSIS
    Interactive & Dynamic Azure App Services and App Service Plan Decommissioning Wizard.

.DESCRIPTION
    Fully interactive and configurable tool for decommissioning Azure App Services:
      1. Prompts for Resource Group (sanitizes input and auto-discovers available resources).
      2. Dynamically lists all App Services in that Resource Group.
         (If auto-discovery returns 0, allows direct manual entry of app names).
      3. Prompts user to select which App Services to delete (by index, name, or 'all').
      4. Auto-discovers associated App Service Plan(s) and audits workloads hosted on them.
      5. Asks user whether to also delete the associated App Service Plan(s).
      6. Offers interactive actions:
           [1] Dry Run (Perform all pre-flight audits and show Bill of Materials, zero deletions)
           [2] Permanent Delete (Audits -> Explicit confirmation -> Deletion)
           [3] Exit

.PARAMETER ResourceGroupName
    Optional: Specify a Resource Group directly to skip the initial prompt.

.PARAMETER SubscriptionId
    Optional: Target Azure Subscription ID.

.EXAMPLE
    # Launch interactive wizard:
    .\decommission.ps1

.EXAMPLE
    # Launch with pre-selected Resource Group:
    .\decommission.ps1 -ResourceGroupName "rg-bw-ai-sttdev"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# Import Modular Sub-scripts
# ==============================================================================
$commonModulePath = Join-Path $PSScriptRoot "common\Azure-Utils.ps1"
$appModulePath    = Join-Path $PSScriptRoot "app-delete\Remove-AppService.ps1"
$planModulePath   = Join-Path $PSScriptRoot "appplan-delete\Remove-AppServicePlan.ps1"

if (-not (Test-Path $commonModulePath)) { throw "Module not found: $commonModulePath" }
if (-not (Test-Path $appModulePath))    { throw "Module not found: $appModulePath" }
if (-not (Test-Path $planModulePath))   { throw "Module not found: $planModulePath" }

. $commonModulePath
. $appModulePath
. $planModulePath

# ==============================================================================
# Main Interactive Wizard
# ==============================================================================
try {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " AZURE APP SERVICES DECOMMISSIONING WIZARD" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    # 1. Verify Azure CLI Session
    $context = Test-AzureCliSession -SubscriptionId $SubscriptionId
    Write-Log "Active Subscription: $($context.name) ($($context.id))" "SUCCESS"

    # 2. Get Resource Group interactively (sanitize any control characters or extra whitespace)
    $targetRg = $ResourceGroupName
    if (-not $targetRg) {
        Write-Host ""
        $inputRg = Read-Host "Enter Azure Resource Group name [Press Enter for 'rg-bw-ai-sttdev']"
        # Sanitize non-printable control characters (like Ctrl+V / \x16) and whitespace
        $cleanRg = ($inputRg -replace '[\x00-\x1F\x7F]', '').Trim()
        $targetRg = if ($cleanRg) { $cleanRg } else { "rg-bw-ai-sttdev" }
    } else {
        $targetRg = ($targetRg -replace '[\x00-\x1F\x7F]', '').Trim()
    }

    Write-Log "Target Resource Group: '$targetRg'" "INFO"

    # 3. Discover App Services in the Resource Group
    $availableApps = Get-AllAppServicesInResourceGroup -ResourceGroupName $targetRg
    $selectedAppNames = @()

    if ($availableApps -and $availableApps.Count -gt 0) {
        # Display discovered App Services with numbered indices
        Write-Host ""
        Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Discovered App Services in '$targetRg':" -ForegroundColor Yellow
        Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
        for ($i = 0; $i -lt $availableApps.Count; $i++) {
            $app = $availableApps[$i]
            $num = $i + 1
            Write-Host "  [$num] $($app.Name)" -ForegroundColor Cyan -NoNewline
            Write-Host " (Plan: $($app.PlanName) | State: $($app.State) | Region: $($app.Location))" -ForegroundColor Gray
        }
        Write-Host "----------------------------------------------------------" -ForegroundColor Yellow

        # 4. User selection of App Services
        Write-Host ""
        $appSelectionInput = Read-Host "Which App Service(s) do you want to delete? (e.g. '1, 2' or 'all')"
        $cleanSelection = ($appSelectionInput -replace '[\x00-\x1F\x7F]', '').Trim()

        if (-not $cleanSelection) {
            Write-Log "No selection made. Exiting." "WARN"
            exit 0
        }

        if ($cleanSelection.ToLower() -eq "all") {
            $selectedAppNames = @($availableApps.Name)
        } else {
            $tokens = $cleanSelection -split ',' | ForEach-Object { $_.Trim() }
            foreach ($token in $tokens) {
                if ($token -match '^\d+$') {
                    $pos = [int]$token - 1
                    if ($pos -ge 0 -and $pos -lt $availableApps.Count) {
                        $selectedAppNames += $availableApps[$pos].Name
                    } else {
                        Write-Log "Invalid index '$token' ignored." "WARN"
                    }
                } else {
                    # User typed the app name directly
                    if ($token) { $selectedAppNames += $token }
                }
            }
        }
    } else {
        # Fallback if az webapp list returned empty: Allow manual entry
        Write-Host ""
        Write-Log "Auto-discovery returned 0 App Services in '$targetRg'." "WARN"
        $manualInput = Read-Host "Enter App Service name(s) to delete (comma-separated, e.g. 'app-bwai-qaapi, app-bwai-devapi')"
        $cleanManual = ($manualInput -replace '[\x00-\x1F\x7F]', '').Trim()
        if (-not $cleanManual) {
            Write-Log "No App Services entered. Exiting." "WARN"
            exit 0
        }
        $selectedAppNames = @($cleanManual -split ',' | ForEach-Object { ($_.Trim() -replace '[\x00-\x1F\x7F]', '') } | Where-Object { $_ })
    }

    if ($selectedAppNames.Count -eq 0) {
        Write-Log "No valid App Services selected. Exiting." "WARN"
        exit 0
    }

    $selectedAppNames = @($selectedAppNames | Select-Object -Unique)
    Write-Log "Selected for deletion: $($selectedAppNames -join ', ')" "INFO"

    # 5. Audit Each Selected App & Discover Hosting App Service Plan(s)
    $appAudits = @()
    $associatedPlanNames = @()

    foreach ($appName in $selectedAppNames) {
        $audit = Get-AppServiceAudit -ResourceGroupName $targetRg -AppName $appName
        $appAudits += $audit
        if ($audit.Exists -and $audit.PlanName) {
            $associatedPlanNames += $audit.PlanName
        }
    }

    $associatedPlanNames = @($associatedPlanNames | Select-Object -Unique)
    $plansToDelete = @()

    if ($associatedPlanNames.Count -gt 0) {
        Write-Host ""
        Write-Host "----------------------------------------------------------" -ForegroundColor Magenta
        Write-Host " Associated App Service Plan(s) Analysis:" -ForegroundColor Magenta
        Write-Host "----------------------------------------------------------" -ForegroundColor Magenta

        foreach ($planName in $associatedPlanNames) {
            $planAudit = Get-AppServicePlanAudit -ResourceGroupName $targetRg -PlanName $planName -SelectedAppNames $selectedAppNames
            
            Write-Host "  Plan Name      : $planName" -ForegroundColor Cyan
            Write-Host "  Apps on Plan   : $($planAudit.AllAppsOnPlan -join ', ')"
            
            if ($planAudit.CanSafelyDelete) {
                Write-Host "  Status         : All apps on this plan are selected for deletion." -ForegroundColor Green
                $deletePlanPrompt = Read-Host "  Do you also want to delete App Service Plan '$planName'? (y/n) [default: y]"
                $cleanPlanAnswer = ($deletePlanPrompt -replace '[\x00-\x1F\x7F]', '').Trim().ToLower()
                $answer = if ($cleanPlanAnswer) { $cleanPlanAnswer } else { "y" }
                if ($answer -in @("y", "yes")) {
                    $plansToDelete += $planAudit
                    Write-Log "Plan '$planName' marked for deletion." "INFO"
                } else {
                    Write-Log "Plan '$planName' will be kept." "INFO"
                }
            } else {
                $otherApps = $planAudit.UnselectedApps -join ", "
                Write-Host "  Status         : CANNOT DELETE (Still hosts active apps: [$otherApps])." -ForegroundColor Yellow
                Write-Log "Plan '$planName' will NOT be deleted to prevent outage for remaining apps." "WARN"
            }
            Write-Host "----------------------------------------------------------" -ForegroundColor Magenta
        }
    }

    # 6. Action Menu Selection
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " ACTION SELECTION" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   [1] Dry Run (Perform all pre-flight audits and show BOM, zero deletions)" -ForegroundColor Yellow
    Write-Host "   [2] Decommission / Permanent Delete (Audit -> Confirm -> Destroy)" -ForegroundColor Red
    Write-Host "   [3] Exit" -ForegroundColor Gray
    Write-Host "----------------------------------------------------------"
    $actionChoice = Read-Host " Enter choice (1, 2, or 3)"
    $cleanAction = ($actionChoice -replace '[\x00-\x1F\x7F]', '').Trim()

    switch ($cleanAction) {
        "1" { $mode = "DryRun" }
        "2" { $mode = "Delete" }
        default {
            Write-Log "Exiting decommissioning wizard." "INFO"
            exit 0
        }
    }

    # 7. Execute Pre-Flight Lock Audit for Selected Resources
    Write-Log "==========================================================" "STEP"
    Write-Log " PHASE 1: PRE-FLIGHT AUDITS & DEPENDENCY CHECKS" "STEP"
    Write-Log "==========================================================" "STEP"

    $planNamesList = @($plansToDelete.Name)
    Test-TargetResourceLocks -ResourceGroupName $targetRg -AppServiceNames $selectedAppNames -PlanNames $planNamesList | Out-Null

    # 8. Display Formatted Bill of Materials (BOM)
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " BILL OF MATERIALS MARKED FOR DECOMMISSIONING" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  Subscription    : $($context.name)"
    Write-Host "  Resource Group  : $targetRg"
    Write-Host "  Target Apps     : $($selectedAppNames.Count) App Service(s)"
    foreach ($audit in $appAudits) {
        $statusStr = if ($audit.Exists) { "[EXISTS]" } else { "[NOT FOUND]" }
        Write-Host "    - $($audit.Name) $statusStr" -ForegroundColor Cyan
        if ($audit.Slots -and $audit.Slots.Count -gt 0) {
            Write-Host "      |-- Deployment Slots: $($audit.Slots -join ', ')" -ForegroundColor Yellow
        }
    }
    Write-Host "  Target Plans    : $(if ($plansToDelete.Count -gt 0) { ($plansToDelete.Name) -join ', ' } else { 'None (Plans will be preserved)' })"
    Write-Host "  Resource Locks  : Clean (No blocking locks on selected resources)"
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""

    # Mode 1: Dry Run Output
    if ($mode -eq "DryRun") {
        Write-Log "==========================================================" "SUCCESS"
        Write-Log " MODE: DRY-RUN COMPLETED SUCCESSFULLY" "SUCCESS"
        Write-Log " All pre-flight audits and dependency checks passed." "SUCCESS"
        Write-Log " Zero resources were modified or deleted." "SUCCESS"
        Write-Log " To execute permanent deletion, re-run and select Option [2]." "INFO"
        Write-Log "==========================================================" "SUCCESS"
        exit 0
    }

    # Mode 2: Permanent Deletion Confirmation Gate
    if ($mode -eq "Delete") {
        Write-Host "WARNING: THIS ACTION IS PERMANENT AND CANNOT BE UNDONE!" -ForegroundColor Red
        Write-Host "The selected App Services and confirmed App Service Plan(s) will be destroyed." -ForegroundColor Yellow
        $userConfirm = Read-Host "Are you sure you want to proceed? (Type 'yes' to proceed, or press Enter to cancel)"
        $cleanConfirm = ($userConfirm -replace '[\x00-\x1F\x7F]', '').Trim().ToLower()
        
        if ($cleanConfirm -ne "yes") {
            Write-Log "Decommissioning CANCELLED by user. Zero resources were modified or deleted." "WARN"
            exit 0
        }

        Write-Log "==========================================================" "STEP"
        Write-Log " PHASE 2: EXECUTING PERMANENT DELETION" "STEP"
        Write-Log "==========================================================" "STEP"

        # Step A: Delete App Services and their slots
        foreach ($audit in $appAudits) {
            Invoke-AppServiceDecommission -ResourceGroupName $targetRg -AppAudit $audit -IsDryRun:$false | Out-Null
        }

        # Step B: Delete App Service Plan(s)
        foreach ($planAudit in $plansToDelete) {
            Invoke-AppServicePlanDecommission -ResourceGroupName $targetRg -PlanAudit $planAudit -IsDryRun:$false | Out-Null
        }

        # Step C: Post-Deletion ARM Verification
        Test-ResourceDecommissionVerification -ResourceGroupName $targetRg -AppNames $selectedAppNames -PlanNames $planNamesList

        Write-Log "==========================================================" "SUCCESS"
        Write-Log " Decommissioning workflow completed successfully." "SUCCESS"
        Write-Log "==========================================================" "SUCCESS"
        exit 0
    }

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    exit 1
}
