# The build's own window, for real: VISIBLE, like the packs run - the build is
# long, loud, and still has questions only it can ask (the account the image
# already carries, the Docker image, Docker Desktop, the first shell). The
# window's road hands its arguments over positionally, in the order the param
# line below declares - gui.ps1's ArgumentList and that line must agree, and
# gui-test.ps1 pins both - and the window closes with the build: it waits for
# Enter only when the build ABORTED, so the error is read instead of vanishing
# with the process.

# SaveImage and RegisterDocker ride as strings like JobRunner's archive flag:
# a [bool] parameter refuses every token pwsh -File hands it (measured - even
# "1" and "$true" die at the binding), so the window sends True/False and the
# conversion happens here.
param([string]$Name, [string]$User, [string]$Packs, [string]$Dockerfile, [string]$FirstBoot, [string]$Image, [string]$SaveImage, [string]$RegisterDocker, [string]$Module, [string]$BuildScript)

$failed = $false
# Zeroed first, the entry's own rule: a run that simply ends returns zero -
# what an earlier native left in $LASTEXITCODE must not read as this run's.
$LASTEXITCODE = 0
try {
    Import-Module $Module -Force
    $mgr = New-InstanceManager
    # The window's answers, one object - the build's mode IS its presence,
    # and the console never sees these as parameters any more.
    $Form = [PSCustomObject]@{
        Name           = $Name
        User           = $User
        Packs          = $Packs
        Dockerfile     = $Dockerfile
        FirstBoot      = $FirstBoot
        Image          = $Image
        SaveImage      = [bool]::Parse($SaveImage)
        RegisterDocker = [bool]::Parse($RegisterDocker)
    }
    Write-Host ""
    Write-Host "==> Creating a new instance" -ForegroundColor (Get-MessageColour info)
    & $BuildScript -Form $Form -Manager $mgr
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
    $failed = $true
}

# The script's own refusals end in exit 1, not in a throw - the window must
# stay for those too, or the message is gone before it is read. A build that
# went through gets its other ending: the summary's moment, then the shell.
if ($failed -or $LASTEXITCODE -ne 0) {
    Write-Host ""
    $null = Read-Host "Press Enter to close this window"
} else {
    $null = Read-Host "Press Enter to open the shell"
    try {
        $mgr.Refresh()
        $inst = @($mgr.Instances | Where-Object { $_.Name -eq $Name })[0]
        if ($inst) { $inst.OpenShell() }
    } catch {
        Write-Host "The shell window could not be opened: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour warning)
    }
}
