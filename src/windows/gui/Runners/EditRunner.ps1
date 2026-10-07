# The pack run's own window, for real: VISIBLE, this one - the installs can
# take minutes, and what they are doing is the point. It prints the same lines
# the console's manage_packs prints, because it is the same engine doing the
# work; the window then waits for Enter, so a failure can be read before it
# closes. Nothing watches it: the window IS the progress.

param([string]$Name, [string]$Add, [string]$Remove, [string]$Module)

try {
    Import-Module $Module -Force
    $mgr = New-InstanceManager

    $inst = @($mgr.OursHere()) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $inst) { throw "'$Name' is not in our list any more." }

    # The distro must be up to carry packs - the console's own first move.
    Invoke-External { wsl.exe -d $Name --exec /bin/true } "Could not start '$Name'."

    $catalog = Get-PackCatalog
    $toAdd = @()
    foreach ($n in @($Add -split ',' | Where-Object { $_ })) {
        $pack = $catalog.GetPack($n)
        if ($null -ne $pack) { $toAdd += $pack }
    }
    $toRemove = @($Remove -split ',' | Where-Object { $_ })

    Write-Host ""
    Write-Host "==> Packs of '$Name'" -ForegroundColor (Get-MessageColour info)
    $report = $mgr.ManagePacks($inst, $toAdd, $toRemove, "")

    if ($null -eq $report.Failure) {
        Write-Host ""
        $now = @($report.Now)
        Write-Host "==> '$Name' now carries: $(if ($now.Count -gt 0) { $now -join ', ' } else { 'no pack' })" -ForegroundColor (Get-MessageColour success)
    }
} catch {
    # No colour helper here: this very catch exists for the case where the
    # module did not load - and the helper lives in the module.
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
