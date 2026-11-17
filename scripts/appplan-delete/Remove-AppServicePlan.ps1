# ==============================================================================
# Module      : Remove-AppServicePlan.ps1
# Description : App Service Plan discovery, shared app protection, and deletion
# ==============================================================================

function Get-AppServicePlanAudit {
    param (
        [string]$ResourceGroupName,
        [string]$PlanName,
        [string[]]$SelectedAppNames = @()
    )

    Write-Log "Auditing App Service Plan: '$PlanName'..." "INFO"
    $planJson = az appservice plan show --resource-group $ResourceGroupName --name $PlanName -o json 2>$null
    $exists = [bool]$planJson
    $planId = $null
    $allAppsOnPlan = @()
    $unselectedApps = @()

    if ($exists) {
        $plan = $planJson | ConvertFrom-Json
        $planId = $plan.id

        # Query all webapps in the resource group
        $allAppsJson = az webapp list --resource-group $ResourceGroupName -o json 2>$null
        if ($allAppsJson) {
            $allApps = @($allAppsJson | ConvertFrom-Json)
            $matchingApps = $allApps | Where-Object {
                ($_.serverFarmId -and $_.serverFarmId -eq $plan.id) -or
                ($_.appServicePlanId -and $_.appServicePlanId -eq $plan.id)
            }
            if ($matchingApps -and $matchingApps.Count -gt 0) {
                $allAppsOnPlan = @($matchingApps.name)
            }

            # Identify apps on this plan that are NOT marked for deletion
            $unselected = $allAppsOnPlan | Where-Object { $_ -notin $SelectedAppNames }
            if ($unselected -and $unselected.Count -gt 0) {
                $unselectedApps = @($unselected)
            }
        }

        if ($unselectedApps.Count -gt 0) {
            $otherList = $unselectedApps -join ", "
            Write-Log "SHARED PLAN NOTICE: Plan '$PlanName' also hosts other app(s) NOT marked for deletion: [$otherList]." "WARN"
        } else {
            Write-Log "Plan '$PlanName': Clean (Only selected app(s) are hosted on this plan)." "SUCCESS"
        }
    } else {
        Write-Log "App Service Plan '$PlanName': Not found in '$ResourceGroupName'." "WARN"
    }

    return [PSCustomObject]@{
        Name           = $PlanName
        Exists         = $exists
        Id             = $planId
        AllAppsOnPlan  = $allAppsOnPlan
        UnselectedApps = $unselectedApps
        CanSafelyDelete= ($exists -and ($unselectedApps.Count -eq 0))
    }
}

function Invoke-AppServicePlanDecommission {
    param (
        [string]$ResourceGroupName,
        [PSCustomObject]$PlanAudit,
        [switch]$IsDryRun
    )

    $planName = $PlanAudit.Name

    if (-not $PlanAudit.Exists) {
        Write-Log "App Service Plan '$planName' does not exist. Skipping." "WARN"
        return $false
    }

    if (-not $PlanAudit.CanSafelyDelete) {
        $otherList = ($PlanAudit.UnselectedApps) -join ", "
        Write-Log "CANNOT DELETE PLAN '$planName': Still hosts active apps not selected for deletion: [$otherList]." "ERROR"
        return $false
    }

    if ($IsDryRun) {
        Write-Log "[DRY-RUN] Would delete App Service Plan: '$planName'." "INFO"
    } else {
        Write-Log "Deleting App Service Plan: '$planName'..." "INFO"
        az appservice plan delete --resource-group $ResourceGroupName --name $planName --yes | Out-Null
        Write-Log "Successfully deleted App Service Plan: '$planName'." "SUCCESS"
    }

    return $true
}

function Test-ResourceDecommissionVerification {
    param (
        [string]$ResourceGroupName,
        [string[]]$AppNames = @(),
        [string[]]$PlanNames = @()
    )

    Write-Log "Verifying resource removal with Azure ARM..." "INFO"
    $stillPresent = @()

    foreach ($app in $AppNames) {
        $check = az webapp show --resource-group $ResourceGroupName --name $app -o json 2>$null
        if ($check) { $stillPresent += "App Service: $app" }
    }

    foreach ($plan in $PlanNames) {
        $check = az appservice plan show --resource-group $ResourceGroupName --name $plan -o json 2>$null
        if ($check) { $stillPresent += "App Service Plan: $plan" }
    }

    if ($stillPresent.Count -gt 0) {
        $items = $stillPresent -join ", "
        Write-Log "Verification Notice: Propagating in ARM ($items)." "WARN"
    } else {
        Write-Log "All targeted resources have been verified as completely removed." "SUCCESS"
    }
}
