# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager,

    # The answers, whole - by whichever road they were asked: the window's
    # form and the console's conversation (src\windows\cli\Build.ps1) render
    # the same object, and this file never asks which. A name that exists is
    # refused on either road, never built over.
    [object]$Form
)

$ErrorActionPreference = "Stop"

# The repository root, three levels above this script - src\windows\
# WslCommands\ - : it holds the Dockerfile, and that is the context the build
# below must run in, not this folder. The local build is the only caller that
# feels this; the CI builds from the checkout's own root.
$RepoRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
Set-Location -Path $RepoRoot

# The preflight, as a piece of its own: docker must answer before anything is
# made. It exits rather than throws - there is nothing to catch above it.
function Assert-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "[ABORT] Docker is not installed, or not on the PATH." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Install Docker Desktop (see Prerequisites in the README), then run this script again." -ForegroundColor (Get-MessageColour hint)
        exit 1
    }

    if (-not (Test-NativeCommand { docker info })) {
        Write-Host ""
        Write-Host "[ABORT] Docker is not responding." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Start Docker Desktop, then run this script again." -ForegroundColor (Get-MessageColour hint)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }
}
Assert-DockerReady

# The Manager's configured root folder: the checks below read it.
$Root = $Manager.InstancesRoot

# The answers, hydrated once - same names either way: everything below reads
# plain values and never asks which door the run came by.
$Name = $Form.Name
$User = $Form.User
$Packs = $Form.Packs
$Dockerfile = $Form.Dockerfile
$Image = $Form.Image
$FirstBoot = $Form.FirstBoot
$KeepImage = $Form.SaveImage
$RegisterDocker = $Form.RegisterDocker

# The recipe files, checked here too: an answer is not trusted blind,
# whichever door it came by - the console checked its typed path before its
# questions, this catches what came by the window.
$ToCheck = @()
if ($FirstBoot) { $ToCheck += @{ What = "first_boot"; Path = $FirstBoot } }
if ($Image) { $ToCheck += @{ What = "Docker image"; Path = $Image } }
elseif ($Dockerfile) { $ToCheck += @{ What = "Dockerfile"; Path = $Dockerfile } }
foreach ($Named in $ToCheck) {
    if (-not (Test-Path -Path $Named.Path -PathType Leaf)) {
        Write-Host ""
        Write-Host "[ABORT] The $($Named.What) is not a file: $($Named.Path)" -ForegroundColor (Get-MessageColour error)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }
}
$Dockerfile = if ($Dockerfile) { [System.IO.Path]::GetFullPath($Dockerfile) } else { "" }
$Image = if ($Image) { [System.IO.Path]::GetFullPath($Image) } else { "" }
$FirstBoot = if ($FirstBoot) { [System.IO.Path]::GetFullPath($FirstBoot) } else { "" }

# The name and its folder: the same rules either way. A name Windows already
# carries is refused, never built over.
$DistroName = $Name
if (-not $Manager.IsNameUsable($Name)) {
    Write-Host ""
    Write-Host "[ABORT] '$Name' is not usable as an instance name (letters, digits, '.', '_' and '-' only)." -ForegroundColor (Get-MessageColour error)
    exit 1
}
if ((Get-DistroNames) -contains $Name) {
    Write-Host ""
    Write-Host "[ABORT] '$Name' is already registered." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Remove it first:  .\wsl.ps1 unregister" -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}
$InstallPath = [System.IO.Path]::GetFullPath((Join-Path $Root $DistroName))
if ($Manager.IsPathOccupied($InstallPath)) {
    Write-Host ""
    Write-Host "[ABORT] The folder below already exists and is not empty:" -ForegroundColor (Get-MessageColour error)
    Write-Host "        $InstallPath" -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Move or delete it, then run this again." -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# The packs chosen - names in, from either door: the shared resolver turns
# them into the list to apply, requirements included, in order. Empty names
# simply leave nothing to install.
$PackSelection = $null
$PackCatalog = $Manager.Catalog
if ($PackCatalog.AvailablePacks.Count -gt 0) {
    $Wanted = @($Packs -split ',' | Where-Object { $_ })
    $Resolved = Resolve-PackSelection -Catalog $PackCatalog -Installed @() -Kept $Wanted
    if ($Resolved.ToAdd.Count -gt 0) {
        $PackSelection = [PSCustomObject]@{ ToAdd = $Resolved.ToAdd; ToRemove = @() }
    }
}

# The account: the same rule either way, and only when an onboarding runs -
# the onboarding is what makes it.
$UserName = ""
if ($FirstBoot) {
    if ("$User" -cnotmatch '^[a-z][a-z0-9_-]*$') {
        Write-Host ""
        Write-Host "[ABORT] '$User' is not a usable user name." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Lowercase letters, digits, '_' and '-' only, starting with a letter." -ForegroundColor (Get-MessageColour hint)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }
    $UserName = $User
}

try {
    $Recipe = [WslRecipe]::new().
    WithImage($Image).
    WithDockerfile($Dockerfile, $RepoRoot).
    WithFirstBoot($FirstBoot).
    WithLook([WslTheme]::Default($DistroName)).
    WithPacks([WslPack[]]@($PackSelection ? $PackSelection.ToAdd : @())).
    WithKeepImage($KeepImage).
    WithRegisterDocker($RegisterDocker)

    Write-Host "==> 1. Building '$DistroName' from its recipe..." -ForegroundColor (Get-MessageColour info)
    $Instance = $Manager.CreateNew($DistroName, $Recipe, $UserName)

    Clear-Host
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
    Write-Host "         WSL Stack Instance Successfully Deployed!          " -ForegroundColor (Get-MessageColour success)
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
    Write-Host ""
    # The instance describes itself; one call shows the lot.
    Write-Host "$Instance"
    # What the look could not do, as the birth wrote it down.
    foreach ($Note in $Instance.Recipe.Messages) {
        Write-Host "  * Note               : $Note" -ForegroundColor (Get-MessageColour warning)
    }
    # What the scripts themselves said, read back from the file the run kept
    # them in - shown on every run, not only the failed ones: the install
    # runs under the instance's own method, and there the screen loses the
    # scripts' channel; the file did not.
    $ErrorLog = Join-Path $InstallPath "pack-errors.log"
    if ((Test-Path $ErrorLog) -and (Get-Item $ErrorLog).Length -gt 0) {
        Write-Host "  * Scripts            : what the pack scripts reported:" -ForegroundColor (Get-MessageColour warning)
        foreach ($Line in @(Get-Content -LiteralPath $ErrorLog)) {
            Write-Host "$(' ' * 24)  $Line" -ForegroundColor (Get-MessageColour error)
        }
    }
}
catch {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour error)
    Write-Host " [ERROR] DURING DEPLOYMENT" -ForegroundColor (Get-MessageColour error)
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour error)
    Write-Host $_.Exception.Message -ForegroundColor (Get-MessageColour error)
    Write-Host ""

    # The packs install as the birth's last step. A failure before the
    # import leaves nothing behind - the user knows their packs went with it.
    # A failure after it leaves a half-born instance, and THAT is the fact
    # worth saying: what is missing, and how to finish it.
    if ($null -eq $Instance -and $PackSelection -and (Test-TemplateInstance -Folder $InstallPath)) {
        $WantedPacks = ($PackSelection.ToAdd | ForEach-Object { $_.Name }) -join ", "
        Write-Host "The packs chosen earlier ($WantedPacks) were not installed: the build stopped before them." -ForegroundColor (Get-MessageColour warning)
        Write-Host "Once it is usable, .\wsl.ps1 manage_packs installs them in it." -ForegroundColor (Get-MessageColour muted)
    }

    exit 1
}

# A success says so too: the failure paths exit 1, and a script that simply
# ends leaves the last native's code for the caller - the window's runner
# read it and waited on a build that had succeeded.
exit 0
