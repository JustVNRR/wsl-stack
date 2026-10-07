# The build's own window, for real: VISIBLE, like the packs run - the build is
# long, loud, and still has questions only it can ask (the account the image
# already carries, the Docker image, Docker Desktop, the first shell). The
# window's road hands its arguments over positionally, in the order the param
# line below declares - gui.ps1's ArgumentList and that line must agree, and
# gui-test.ps1 pins both - and the window closes with the build: it waits for
# Enter only when the build ABORTED, so the error is read instead of vanishing
# with the process.

param([string]$Name, [string]$User, [string]$Packs, [string]$Dockerfile, [string]$FirstBoot, [string]$Image, [string]$Module, [string]$BuildScript)

$failed = $false
try {
    Import-Module $Module -Force
    $mgr = New-InstanceManager
    & $BuildScript -Name $Name -User $User -Packs $Packs -Dockerfile $Dockerfile -FirstBoot $FirstBoot -Image $Image -Manager $mgr
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
    $failed = $true
}

if ($failed) {
    Write-Host ""
    $null = Read-Host "Press Enter to close this window"
}
