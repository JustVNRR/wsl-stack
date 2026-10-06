# The build's own window, for real: VISIBLE, like the packs run - the build is
# long, loud, and still has questions only it can ask (the account the image
# already carries, the Docker image, Docker Desktop, the first shell). It is
# called in PowerShell with its arguments NAMED - wsl.ps1's road hands extra
# arguments over positionally, which is how they used to land nowhere - and
# the window waits for Enter at the end: an abort must not vanish with the
# process.

param([string]$Name, [string]$User, [string]$Packs, [string]$Module, [string]$BuildScript)

try {
    Import-Module $Module -Force
    $mgr = New-InstanceManager
    & $BuildScript -Name $Name -User $User -Packs $Packs -Manager $mgr
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
