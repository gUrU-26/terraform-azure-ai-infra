# ==============================================================================
# Module      : Remove-AppService.ps1
# Description : Dynamic discovery, slot inspection, and App Service deletion
# ==============================================================================

function Get-AllAppServicesInResourceGroup {
    param (
        [string]$ResourceGroupName
    )

    Write-Log "Discovering App Services in Resource Group '$ResourceGroupName'..." "INFO"
    $appsJson = az webapp list --resource-group $ResourceGroupName -o json 2>$null
    
    if (-not $appsJson -or $appsJson.Trim() -eq "" -or $appsJson.Trim() -eq "[]") {
        return @()
    }

    $raw = $appsJson | ConvertFrom-Json
    if (-not $raw) {
        return @()
    }

    # Filter out null elements and ensure each item has a valid name
    $validApps = @($raw | Where-Object { $_ -ne $null -and $_.name })
    if ($validApps.Count -eq 0) {
        return @()
    }

    $results = @()
    foreach ($app in $validApps) {
        $planName = ""
        if ($app.serverFarmId) {
            $planName = ($app.serverFarmId -split '/')[-1]
        } elseif ($app.appServicePlanId) {
            $planName = ($app.appServicePlanId -split '/')[-1]
        }

        $results += [PSCustomObject]@{
            Name     = $app.name
            State    = if ($app.state) { $app.state } else { "Unknown" }
            Location = if ($app.location) { $app.location } else { "Unknown" }
            PlanName = $planName
            PlanId   = if ($app.serverFarmId) { $app.serverFarmId } else { $app.appServicePlanId }
        }
    }

    return $results
}

function Get-AppServiceAudit {
    param (
        [string]$ResourceGroupName,
        [string]$AppName
    )

    Write-Log "Auditing App Service: '$AppName'..." "INFO"
    $appJson = az webapp show --resource-group $ResourceGroupName --name $AppName -o json 2>$null
    $exists = [bool]$appJson
    $slots = @()
    $planName = ""
    $planId = ""

    if ($exists) {
        $app = $appJson | ConvertFrom-Json
        if ($app.serverFarmId) {
            $planId = $app.serverFarmId
            $planName = ($app.serverFarmId -split '/')[-1]
        } elseif ($app.appServicePlanId) {
            $planId = $app.appServicePlanId
            $planName = ($app.appServicePlanId -split '/')[-1]
        }

        $slotsJson = az webapp deployment slot list --resource-group $ResourceGroupName --name $AppName -o json 2>$null
        if ($slotsJson -and $slotsJson.Trim() -ne "" -and $slotsJson.Trim() -ne "[]") {
            $slotsRaw = $slotsJson | ConvertFrom-Json
            if ($slotsRaw) {
                $slotsObj = @($slotsRaw | Where-Object { $_ -ne $null -and $_.name })
                if ($slotsObj.Count -gt 0) {
                    $slots = @($slotsObj.name)
                }
            }
        }
        $slotText = if ($slots.Count -gt 0) { $slots -join ', ' } else { "None" }
        Write-Log "App Service '$AppName': Found (Plan: '$planName', Slots: $slotText)" "SUCCESS"
    } else {
        Write-Log "App Service '$AppName': Not found in '$ResourceGroupName'." "WARN"
    }

    return [PSCustomObject]@{
        Name     = $AppName
        Exists   = $exists
        PlanName = $planName
        PlanId   = $planId
        Slots    = $slots
    }
}

function Invoke-AppServiceDecommission {
    param (
        [string]$ResourceGroupName,
        [PSCustomObject]$AppAudit,
        [switch]$IsDryRun
    )

    $appName = $AppAudit.Name

    if (-not $AppAudit.Exists) {
        Write-Log "App Service '$appName' does not exist. Skipping." "WARN"
        return $false
    }

    # Step A: Delete deployment slots first (ARM constraint)
    if ($AppAudit.Slots -and $AppAudit.Slots.Count -gt 0) {
        foreach ($slot in $AppAudit.Slots) {
            if ($IsDryRun) {
                Write-Log "[DRY-RUN] Would delete deployment slot: '$slot' on '$appName'." "INFO"
            } else {
                Write-Log "Deleting deployment slot: '$slot' on '$appName'..." "INFO"
                az webapp deployment slot delete --resource-group $ResourceGroupName --name $appName --slot $slot | Out-Null
                Write-Log "Successfully deleted deployment slot: '$slot'." "SUCCESS"
            }
        }
    }

    # Step B: Delete the Web App
    if ($IsDryRun) {
        Write-Log "[DRY-RUN] Would delete App Service: '$appName'." "INFO"
    } else {
        Write-Log "Deleting App Service: '$appName'..." "INFO"
        az webapp delete --resource-group $ResourceGroupName --name $appName --keep-empty-plan true | Out-Null
        Write-Log "Successfully deleted App Service: '$appName'." "SUCCESS"
    }

    return $true
}
