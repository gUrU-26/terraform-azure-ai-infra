# ==============================================================================
# Module      : Azure-Utils.ps1
# Description : Common Azure CLI session verification, logging, and lock audits
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

function Test-AzureCliSession {
    param (
        [string]$SubscriptionId
    )

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI ('az') was not found in PATH. Install from https://aka.ms/installazurecliwindows."
    }

    $accountJson = az account show -o json 2>$null
    if (-not $accountJson) {
        throw "No active Azure CLI session found. Please run 'az login' first."
    }
    $context = $accountJson | ConvertFrom-Json

    if ($SubscriptionId -and ($context.id -ne $SubscriptionId)) {
        Write-Log "Switching active subscription to: $SubscriptionId" "INFO"
        az account set --subscription $SubscriptionId | Out-Null
        $context = (az account show -o json) | ConvertFrom-Json
    }

    return $context
}

function Test-TargetResourceLocks {
    param (
        [string]$ResourceGroupName,
        [string[]]$AppServiceNames = @(),
        [string[]]$PlanNames = @()
    )

    Write-Log "Auditing Azure Resource Locks in '$ResourceGroupName'..." "INFO"
    $locksJson = az lock list --resource-group $ResourceGroupName -o json 2>$null
    if ($locksJson) {
        $locks = @($locksJson | ConvertFrom-Json)
        
        # Only locks on the Resource Group itself, or on the specific selected apps/plans will block deletion
        $blockingLocks = $locks | Where-Object { 
            $lockLevel = $_.level
            $lockId = $_.id
            if ($lockLevel -notin @("CanNotDelete", "ReadOnly")) { return $false }

            # 1. Lock directly on the RG itself
            if ($lockId -match "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Authorization/locks/") {
                return $true
            }

            # 2. Lock on any selected App Service
            foreach ($app in $AppServiceNames) {
                if ($app -and ($lockId -match "(?i)/sites/$app/")) { return $true }
            }

            # 3. Lock on any selected App Service Plan
            foreach ($plan in $PlanNames) {
                if ($plan -and ($lockId -match "(?i)/serverFarms/$plan/")) { return $true }
            }

            return $false
        }

        if ($blockingLocks -and $blockingLocks.Count -gt 0) {
            foreach ($lock in $blockingLocks) {
                Write-Log "BLOCKING LOCK FOUND: '$($lock.name)' (Level: $($lock.level)) on '$($lock.id)'" "ERROR"
            }
            throw "Decommissioning halted: Resource lock(s) detected on target resources. To remove via terminal, run: az lock delete --ids '$($blockingLocks[0].id)'"
        }

        # Notice: log any unrelated locks (e.g. backup locks on storage accounts)
        $unrelatedLocks = $locks | Where-Object { $_.level -in @("CanNotDelete", "ReadOnly") -and $_ -notin $blockingLocks }
        if ($unrelatedLocks -and $unrelatedLocks.Count -gt 0) {
            foreach ($ul in $unrelatedLocks) {
                Write-Log "Notice: Found lock '$($ul.name)' on unrelated resource '$($ul.id)'. (Safely ignored)" "INFO"
            }
        }
    }

    Write-Log "Lock Audit: Passed (No blocking locks found on selected resources)." "SUCCESS"
    return $true
}
