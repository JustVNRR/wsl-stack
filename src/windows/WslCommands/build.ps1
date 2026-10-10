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

    # The window's answers, when the window is the one running: the form's
    # result, whole - name, account, packs, recipe, onboarding, both tick
    # boxes. Its presence IS the mode (see $Gui below); absent, the console
    # asks as it always did. A name that exists is refused on either road,
    # never built over.
    [object]$Form,

    # The recipe from the command line: -Dockerfile and -Image are the two
    # roads and exclude each other; absent both - and no form - the first
    # recipe under 'assets\dockerfiles' is used, and the road is asked when
    # an image was ever uploaded.
    [string]$Dockerfile,
    [string]$Image,

    # Must remain the VERY LAST parameter to allow valid PowerShell parsing
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$Ignored
)

$ErrorActionPreference = "Stop"

if ($Ignored) {
    Write-Host ""
    Write-Host "[ABORT] Unknown options after the command." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Run it on its own:  .\wsl.ps1 build" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# The run's mode, decided once: the window hands its form's answers over,
# the console asks. Everything that differs between the two roads reads
# this - never a parameter's presence. The answers are hydrated once, so
# the rest of the run reads plain values.
$Gui = $null -ne $Form
if ($Gui) {
    $Name       = $Form.Name
    $User       = $Form.User
    $Packs      = $Form.Packs
    $Dockerfile = $Form.Dockerfile
    $Image      = $Form.Image
    $FirstBoot  = $Form.FirstBoot
}
# A road was given - by the window's form or the command line - before any
# default below: the default is not a choice, the road question still owes.
$RoadGiven = $Gui -or $Dockerfile -or $Image

# Step 0, as a piece of its own: Docker answers before the questions, and a
# docker that does not aborts with nothing confirmed and nothing touched. It
# exits rather than throws - there is nothing to catch above it.
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

# The repository root, three levels above this script - src\windows\
# WslCommands\ - : it holds the Dockerfile, and that is the context the build
# below must run in, not this folder. The local build is the only caller that
# feels this; the CI builds from the checkout's own root.
$RepoRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
Set-Location -Path $RepoRoot

# The recipe: the chosen files, or the repository's own Dockerfile. Resolved
# here so a path typed on the command line may be relative to the repository,
# and checked before anything is asked or destroyed - a path that names no
# file stops the run with nothing confirmed and nothing touched. Only
# presence is checked: whether a Dockerfile builds, or an image loads, is the
# engine's own to say.
if ($Image -and $Dockerfile) {
    Write-Host ""
    Write-Host "[ABORT] Choose one recipe: a Dockerfile, or a Docker image - not both." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}
if (-not $Image -and -not $Dockerfile) {
    $RecipeRows = Get-BuildRecipes -AssetsDir (Join-Path $RepoRoot "assets")
    $DockerfileRows = @($RecipeRows.Dockerfiles)
    if ($DockerfileRows.Count -gt 0) {
        # The list's first row: the repository's own, seeded there.
        $Dockerfile = $DockerfileRows[0].Path
    } elseif ($RoadGiven -or @($RecipeRows.Images).Count -eq 0) {
        # Nothing to fall back on: a road was given and its list is empty, or
        # there is no image to ask about either.
        Write-Host ""
        Write-Host "[ABORT] No Dockerfile under 'assets\dockerfiles'." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Upload one, or delete that folder to get the repository's own back." -ForegroundColor (Get-MessageColour hint)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }
    # Nothing chosen here with images around, on a bare command line: the
    # road question below offers both, and refuses an empty Dockerfile list
    # itself.
}
# The onboarding: absent from the command line (the console road), it
# defaults to the first script under the assets - asked about below. None
# there at all, it is said and skipped. Present but empty (the window's
# unticked box), it means none.
$FirstBootAsked = -not $Gui
if ($FirstBootAsked) {
    $BootRows = @((Get-BuildRecipes -AssetsDir (Join-Path $RepoRoot "assets")).FirstBoots)
    if ($BootRows.Count -eq 0) {
        Write-Host "  No onboarding shell under 'assets\onboardings' - the instance will be built without one." -ForegroundColor (Get-MessageColour muted)
        $FirstBoot = ""
    } else {
        $FirstBoot = $BootRows[0].Path
    }
}
# An empty Dockerfile here is the one the road question below will fill.
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

# One build at a time: two runs would fight over the same image tag and
# distribution name. Taken before anything is asked or created, and let
# go when the deployment ends. A run that stops before that closes it with its
# process; a run already waiting when its holder dies reads it as abandoned and
# takes it (the catch below).
$BuildMutex = [System.Threading.Mutex]::new($false, "Global\wsl-stack-build")
$MutexHeld = $false
try {
    $MutexHeld = $BuildMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $MutexHeld = $true
} catch {
    Write-Host ""
    Write-Host "[ABORT] The build lock cannot be taken - another session may be holding it." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    $BuildMutex.Dispose()
    exit 1
}
if (-not $MutexHeld) {
    Write-Host ""
    Write-Host "[ABORT] Another build is already running." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Let it finish, then run this one again." -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    $BuildMutex.Dispose()
    exit 1
}

# 0. Preflight: Docker must answer BEFORE the destructive confirmation below -
# failing here aborts with nothing confirmed and nothing touched.
Assert-DockerReady

# 0-bis. What is being built, asked: the name and the folder. The window
# brings both in; the console is asked, by its own function. A name Windows
# already carries is refused on either road.
Write-Host ""
Write-Host "==> Creating a new instance" -ForegroundColor (Get-MessageColour info)

# Uses the Manager's configured root folder directly.
$Root = $Manager.InstancesRoot
if ($Gui) {
    # The name came with the form; the checks below are the console road's
    # same rules, applied again - a form is not trusted blind.
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
    $DistroName = $Name
    $InstallPath = [System.IO.Path]::GetFullPath((Join-Path $Root $DistroName))
    if ($Manager.IsPathOccupied($InstallPath)) {
        Write-Host ""
        Write-Host "[ABORT] The folder below already exists and is not empty:" -ForegroundColor (Get-MessageColour error)
        Write-Host "        $InstallPath" -ForegroundColor (Get-MessageColour hint)
        Write-Host "        Move or delete it, then run this again." -ForegroundColor (Get-MessageColour hint)
        exit 1
    }
} else {
    $Identity = Resolve-InstanceIdentity -Root $Root
    $DistroName = $Identity.Name
    $InstallPath = $Identity.InstallPath
}

# 0-bis-bis. What to build from, when neither the window nor the command
# line chose: the road first - a Dockerfile, or an image - then the list
# that road offers, uploads included. No image around, nothing is asked:
# the Dockerfile road, as always, and its default was taken above.
if (-not $RoadGiven) {
    $Recipes = Get-BuildRecipes -AssetsDir (Join-Path $RepoRoot "assets")
    if ($Recipes.Images.Count -gt 0) {
        # The roads the recipe class says a build can take - the same list the
        # window's combo shows: one source, so the two cannot drift.
        $Road = Select-FromList -Title "Build from" -Items @([WslRecipe]::Roads()) -Label { param($Row) $Row.Label }
        if ($null -eq $Road) { Stop-Cancelled }

        # One selection for both roads: the list the road offers, then the
        # path landing where the road keeps it.
        $Rows = if ($Road.Type -eq [WslBuildType]::Image) { @($Recipes.Images) } else { @($Recipes.Dockerfiles) }
        if ($Rows.Count -eq 0) {
            Write-Host ""
            Write-Host "[ABORT] No Dockerfile under 'assets\dockerfiles'." -ForegroundColor (Get-MessageColour error)
            Write-Host "        Upload one, or delete that folder to get the repository's own back." -ForegroundColor (Get-MessageColour hint)
            Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
            exit 1
        }
        $Picked = Select-FromList -Title "$($Road.Label)" -Items $Rows -Label { param($Row) $Row.Name }
        if ($null -eq $Picked) { Stop-Cancelled }
        if ($Road.Type -eq [WslBuildType]::Image) { $Image = $Picked.Path; $Dockerfile = "" }
        else { $Dockerfile = $Picked.Path }
    }
}

# 0-ter. The packs, asked here with everything else: nothing asks again once
# the machine starts working - the answer waits in a variable and is applied
# below. Empty, or Escape, means none, and the build goes on either way.
# What family the recipe belongs to is read first: it decides the boxes
# offered and the shell pack pre-ticked - the Dockerfile's FROM when there
# is one, and unknown for an image, whose rootfs nests inside a save-tar.
$RecipeFamily = if ($Image) { "" } else { Get-BuildRecipeFamily -Dockerfile $Dockerfile }
# A family that cannot be read is said above the checklist, not hidden: the
# packs stay in reach - the image may well be Debian under a name we cannot
# read - and the line is the guard for whoever does not know.
$FamilyNote = if ($RecipeFamily) { "" } else { "This recipe's system cannot be read - a pack made for another one will fail to install." }
$PackSelection = $null
$PackCatalog = $Manager.Catalog
if ($PackCatalog.AvailablePacks.Count -gt 0) {
    if ($Gui) {
        # The window answered this one too: names in, and the shared resolver
        # turns them into the list to apply - requirements included, in order.
        # Empty (or unknown) names simply leave nothing to install.
        $Wanted = @($Packs -split ',' | Where-Object { $_ })
        $Resolved = Resolve-PackSelection -Catalog $PackCatalog -Installed @() -Kept $Wanted
        if ($Resolved.ToAdd.Count -gt 0) {
            $PackSelection = [PSCustomObject]@{ ToAdd = $Resolved.ToAdd; ToRemove = @() }
        }
    } else {
        # The shell pack arrives ticked - every visible pack requires it - and
        # its box unticks like any other.
        $PreChecked = @(Get-BuildDefaultPacks -Catalog $PackCatalog -Family $RecipeFamily)

        # -Installed stays at its default: the instance this build makes carries
        # nothing yet - boxes to tick, no removal to compute.
        $PackSelection = Select-Packs -Title "Packs for '$DistroName'" -Catalog $PackCatalog -Checked $PreChecked -Family $RecipeFamily -Note $FamilyNote

        if ($null -eq $PackSelection -or $PackSelection.ToAdd.Count -eq 0) {
            Write-Host ""
            Write-Host "[OK] No pack selected." -ForegroundColor (Get-MessageColour success)
            $PackSelection = $null
        }
    }
}

# 0-quater. The onboarding, then the account it makes. The window's road
# hands both in - its box, its field; the console is asked. The account's
# name only matters when an onboarding runs: it is the onboarding that
# makes the account, and it receives the name. Without one, the instance
# opens as the image's own account and no name is asked.
if ($FirstBootAsked -and $FirstBoot) {
    Write-Host ""
    if (Confirm-YesNo "Run the onboarding shell?") {
        # Which one: the repository's own first_boot first, the uploaded
        # ones under it - the list the window's form offers.
        $Boots = @((Get-BuildRecipes -AssetsDir (Join-Path $RepoRoot "assets")).FirstBoots)
        $Picked = Select-FromList -Title "Onboarding shell" -Items $Boots -Label { param($Row) $Row.Name }
        if ($null -eq $Picked) { Stop-Cancelled }
        $FirstBoot = $Picked.Path
    } else {
        $FirstBoot = ""
    }
}

$UserName = ""
if ($FirstBoot) {
    if ($Gui) {
        if ("$User" -cnotmatch '^[a-z][a-z0-9_-]*$') {
            Write-Host ""
            Write-Host "[ABORT] '$User' is not a usable user name." -ForegroundColor (Get-MessageColour error)
            Write-Host "        Lowercase letters, digits, '_' and '-' only, starting with a letter." -ForegroundColor (Get-MessageColour hint)
            Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
            exit 1
        }
        $UserName = $User
    } else {
        $UserName = Resolve-DefaultUser -DistroName $DistroName -Proposed (Get-WindowsUserProposal)
    }
}

try {

    $Recipe = [WslRecipe]::new().
    WithImage($Image).
    WithDockerfile($Dockerfile, $RepoRoot).
    WithFirstBoot($FirstBoot).
    WithLook([WslTheme]::Default($DistroName)).
    WithPacks([WslPack[]]@($PackSelection ? $PackSelection.ToAdd : @())).
    WithKeepImage($Gui ? $Form.SaveImage : (-not $Image ? (Confirm-YesNo "Keep Docker image?") : $false)).
    WithRegisterDocker($Gui ? $Form.RegisterDocker : (Confirm-YesNo "Add '$DistroName' to Docker Desktop? (it will be restarted)"))

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

    # The window's console closes with the run: give the summary a moment to
    # be read before the shell's own window opens.
    if ($Gui) { $null = Read-Host "Press Enter to open the shell" }
    try {
        $Instance.OpenShell()
    }
    catch {
        Write-Host "The shell window could not be opened: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour warning)
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
finally {
    if ($MutexHeld) {
        $BuildMutex.ReleaseMutex()
    }
    $BuildMutex.Dispose()
}

# A success says so too: the failure paths exit 1, and a script that simply
# ends leaves the last native's code for the caller - the window's runner
# read it and waited on a build that had succeeded.
exit 0