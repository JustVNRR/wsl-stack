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

    # The window's road: the identity questions answered in a form, their
    # answers riding in. Absent one, its question is asked here as it always
    # was - the console's road is unchanged. On the window's road a name that
    # exists is refused, never destroyed: that road offers no destruction to
    # confirm, and the rails below hold it.
    [string]$Name,
    [string]$User,
    [string]$Packs,

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

# The last look before erasing: the image was built in between, and the machine
# may have moved. A distribution that was never confirmed must not be destroyed,
# a folder that has become another instance's must not be taken with it, and a
# list that cannot be read is a refusal - not an absence. Answers with the
# registration found now, or nothing when the name is free.
function Assert-DestructionStillMatches {
    param([string]$DistroName, [string]$InstallPath, [bool]$ConfirmedDestruction)

    try {
        $Now = @(Get-RegisteredDistros)
    } catch {
        throw "The list of registered WSL distributions cannot be read: refusing to erase anything."
    }

    $Here = $Now | Where-Object { $_.Name -eq $DistroName } | Select-Object -First 1
    if ($Here -and -not $ConfirmedDestruction) {
        throw "'$DistroName' is registered now and was not when the questions were asked: it was never confirmed for destruction."
    }

    $Invader = $Now | Where-Object {
        $_.Name -ne $DistroName -and
        ($_.Path -eq $InstallPath -or $_.Path.StartsWith("$InstallPath\", [System.StringComparison]::OrdinalIgnoreCase))
    } | Select-Object -First 1
    if ($Invader) {
        throw "$InstallPath is now, or holds, the folder of '$($Invader.Name)': erasing it would take that instance with it."
    }

    return $Here
}

# The deployment's steps, named one by one: each goes through the checked
# wrapper, so a program that fails stops the run instead of writing a line the
# script walks past.
function Invoke-DockerBuild {
    param([string]$Tag)
    # The recipe lives under distro\build\, the context stays the repository
    # root - the Dockerfile's COPY paths are written against it.
    Invoke-NativeCommand { docker build -t $Tag -f src/distro/build/Dockerfile . } "Docker build failed."
}

function New-DockerContainer {
    param([string]$Name, [string]$Image)
    Invoke-NativeCommand { docker create --name $Name $Image } "Container creation failed."
}

function Export-DockerContainer {
    param([string]$Container, [string]$OutputPath)
    Invoke-NativeCommand { docker export -o $OutputPath $Container } "Docker export failed."
}

function Stop-WslDistro {
    param([string]$Name)
    Invoke-NativeCommand { wsl.exe --terminate $Name } "Could not stop '$Name'." -SuppressOutput
}

function Invoke-WslFirstBoot {
    param([string]$DistroName, [string]$User)
    Invoke-NativeCommand { wsl.exe -d $DistroName -u root /root/first_boot.sh $User } "The first_boot.sh configuration script failed."
}

# Best effort, and nothing here may raise: the finally block calls this after a
# failure, and an error raised here would bury the message the catch has
# printed. The container may never have existed - removing nothing succeeds.
function Remove-DeploymentArtifacts {
    param([string]$ContainerName, [string]$TarPath)

    $null = Test-NativeCommand { docker rm -f $ContainerName }

    if (Test-Path -Path $TarPath) {
        Remove-Item -Path $TarPath -Force -ErrorAction SilentlyContinue
    }
}

# The packs, asked earlier and installed now - in a try of their own, because a
# pack that fails must not reach the deployment's catch, which would announce
# "[ERROR] DURING DEPLOYMENT" for an instance that is built, registered and
# usable. The applying itself is the engine's; what is left here is the story -
# the lines to print and the colour they take.
function Install-SelectedPacks {
    param([WslInstanceManager]$Manager, [WslInstance]$Instance, [object]$PackSelection)

    $Report = @()
    $Colour = "Green"
    if ($null -eq $PackSelection) { return @{ Report = $Report; Colour = $Colour } }

    try {
        # Asked of the instance after the install rather than trusted from the
        # answer: a pack whose install failed took its folder back out.
        $NewHome = Get-InstanceHome -DistroName $Instance.Name
        if (-not $NewHome) { throw "'$($Instance.Name)' did not say where its user's home is." }

        Write-Host ""
        Write-Host "==> Installing the packs..." -ForegroundColor (Get-MessageColour info)
        $Apply = $Manager.ManagePacks($Instance, $PackSelection.ToAdd, @(), "Run .\wsl.ps1 manage_packs to finish.")

        $PacksNow = @($Apply.Now)
        if ($null -ne $Apply.Failure) {
            # Three facts, each only when it has something to say: what is
            # really installed, the pack that stopped the run, and the packs
            # that never ran - their folders went back out with it, so they
            # cannot be read as installed anywhere (packs.ps1).
            $Skipped = @($PackSelection.ToAdd |
                Where-Object { $_.Name -ne $Apply.Failure.Pack -and $PacksNow -notcontains $_.Name } |
                ForEach-Object { $_.Name })

            $Report = @()
            if ($PacksNow.Count -gt 0) {
                $Report += "$($PacksNow -join ', ') successfully installed."
            }
            $Report += "'$($Apply.Failure.Pack)' installation failed."
            if ($Skipped.Count -gt 0) {
                $Report += "$($Skipped -join ', ') installation skipped."
            }
            $Report += "Run .\wsl.ps1 manage_packs on '$($Instance.Name)' to finish."
            $Colour = "Red"
        } else {
            # What is there now, and nothing else: falling back on the names
            # asked for is how a fresh build announced "Packs: claude
            # installed." over an instance whose install had declined.
            $Landed = $PacksNow
            if ($Landed.Count -eq 0) {
                $Report = @("none installed.")
            } else {
                $Report = @("$($Landed -join ', ') installed.")
            }
        }
    } catch {
        $Report = @("not installed - $($_.Exception.Message)")
        $Colour = "Red"
    }
    return @{ Report = $Report; Colour = $Colour }
}

# The Docker Desktop question, moved whole: Docker Desktop injects its docker
# client into the distros it lists and reads that list only when it starts, so
# being in the settings file proves nothing and the question is asked every
# time - it restarts Docker Desktop, so it defaults to yes. Answers the lines
# to print once the shell is open and their colour, or nothing when the user
# said no and there is nothing to say.
function Configure-DockerDesktopIntegration {
    param([string]$DistroName)

    $DockerSettings = Join-Path $env:APPDATA "Docker\settings-store.json"
    if (-not (Test-Path $DockerSettings)) { return $null }

    try {
        Write-Host ""
        if (-not (Confirm-YesNo "Restart Docker Desktop to add support for '$DistroName'?")) { return $null }

        # The shared recipe: a backup beside the file, the name rebuilt rather
        # than appended twice, and a byte-order-mark-free write - Docker
        # Desktop's file carries none.
        Set-DockerState -Name $DistroName

        if (Test-NativeCommand { docker desktop restart }) {
            # The restart says nothing about what happened inside: the client is
            # injected at Docker Desktop's own pace, and the user can be left
            # without the right to use it - which only shows up in the session
            # this build is about to open. So the thing itself is asked, as the
            # default user and never as root, which would pass whatever the
            # answer is.
            $DockerUsable = $false
            for ($Attempt = 1; $Attempt -le 5 -and -not $DockerUsable; $Attempt++) {
                $DockerUsable = Test-NativeCommand { wsl.exe -d $DistroName -- docker version }
                if (-not $DockerUsable) { Start-Sleep -Seconds 2 }
            }
            if ($DockerUsable) {
                return @{ Lines = @("Docker Desktop: ready - 'docker' works in this instance."); Colour = "Green" }
            }
            return @{
                Lines  = @(
                    "Docker Desktop: 'docker' does not answer in this instance yet.",
                    "  Run 'docker version' in there; if it names the socket's permissions, restart",
                    "  Docker Desktop and open a new terminal."
                )
                Colour = "Yellow"
            }
        }
        return @{ Lines = @("Docker Desktop: not restarted - 'docker' will not work in this instance yet."); Colour = "Yellow" }
    } catch {
        return @{ Lines = @("Docker Desktop: settings not updated - $($_.Exception.Message)"); Colour = "Yellow" }
    }
}

# The repository root, three levels above this script - src\windows\
# WslCommands\ - : it holds the Dockerfile, and that is the context the build
# below must run in, not this folder. The local build is the only caller that
# feels this; the CI builds from the checkout's own root.
$RepoRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
Set-Location -Path $RepoRoot

$ImageTag = "wsl-stack:latest"
$ContainerName = "wsl-temp-export-$([guid]::NewGuid().ToString().Substring(0, 8))"

# One build at a time: two runs would fight over the same image tag, container,
# tar and distribution name. Taken before anything is asked or created, and let
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

# 0-bis. What is being built, asked: the name, the folder, and - when Windows
# already carries the name - the destruction it takes. All of it resolved
# before the machine starts, by its own function.
Write-Host ""
Write-Host "==> Creating a new instance" -ForegroundColor (Get-MessageColour info)

# Uses the Manager's configured root folder directly.
$Root = $Manager.InstancesRoot
if ($PSBoundParameters.ContainsKey('Name')) {
    # The name came with the form, and the window already refused what exists.
    # On this road a taken name is refused here too - never destroyed: the
    # destruction gate belongs to the console road, and this one offers no
    # destruction to confirm.
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
    $WasRegistered = $false
} else {
    $Identity = Resolve-InstanceIdentity -Root $Root
    $DistroName = $Identity.Name
    $InstallPath = $Identity.InstallPath
    $WasRegistered = $Identity.WasRegistered
}

# 1. The export tar lands beside the install path - never on C:.
$ParentInstallDir = Split-Path -Path $InstallPath -Parent
if (-not (Test-Path -Path $ParentInstallDir)) {
    New-Item -ItemType Directory -Path $ParentInstallDir -Force | Out-Null
}
$TarPath = Join-Path -Path $ParentInstallDir -ChildPath "$DistroName-rootfs.tar"

# 0-ter. The packs, asked here with everything else: nothing asks again once
# the machine starts working - the answer waits in a variable and is applied
# below. Empty, or Escape, means none, and the build goes on either way.
$PackSelection = $null
$PackCatalog = Get-PackCatalog
if ($PackCatalog.AvailablePacks.Count -gt 0) {
    if ($PSBoundParameters.ContainsKey('Packs')) {
        # The window answered this one too: names in, and the shared resolver
        # turns them into the list to apply - requirements included, in order.
        # Empty (or unknown) names simply leave nothing to install.
        $Wanted = @($Packs -split ',' | Where-Object { $_ })
        $Resolved = Resolve-PackSelection -Catalog $PackCatalog -Installed @() -Kept $Wanted
        if ($Resolved.ToAdd.Count -gt 0) {
            $PackSelection = [PSCustomObject]@{ ToAdd = $Resolved.ToAdd; ToRemove = @() }
        }
    } else {
        # The instance being replaced still exists here: what it carries is what
        # the boxes show. On top of it - and alone on a first build - the shell
        # pack arrives ticked: every visible pack requires it, and its box
        # unticks like any other.
        $PreChecked = @()
        if ($WasRegistered) {
            $PreviousHome = Get-InstanceHome -DistroName $DistroName
            if ($PreviousHome) {
                $PreChecked = @(Get-InstalledPacks -DistroName $DistroName -PacksDirectory "$PreviousHome/.config/packs")
            } else {
                Write-Host "  Could not read what '$DistroName' carries: no pack arrives checked." -ForegroundColor (Get-MessageColour warning)
            }
        }
        $PreChecked += @(Get-BuildDefaultPacks -Catalog $PackCatalog)

        # -Installed stays at its default: the instance this build makes carries
        # nothing yet - boxes to tick, no removal to compute.
        $PackSelection = Select-Packs -Title "Packs for '$DistroName'" -Catalog $PackCatalog -Checked $PreChecked

        if ($null -eq $PackSelection -or $PackSelection.ToAdd.Count -eq 0) {
            Write-Host ""
            Write-Host "[OK] No pack selected." -ForegroundColor (Get-MessageColour success)
            $PackSelection = $null
        }
    }
}

# 0-quater. The user the instance opens as, asked here with everything else:
# nothing asks again once the machine starts working - the answer waits in a
# variable, the instance is born with it at step 5, and the onboarding
# receives it at step 6. On the window's road the answer rides in, checked
# with the same rule the question applies - the window could not know this one.
if ($PSBoundParameters.ContainsKey('User')) {
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

# What this run has done, for the finally block and the exit code to read:
# whether the instance that was there went away, whether this run registered
# one, and whether it reached the end. Read from the run rather than asked of
# WSL again - a list that fails to come back must never read as "no
# distribution".
$Deployment = [ordered]@{
    OldDistroRemoved = $false
    DistroRegistered = $false
    Succeeded        = $false
}

try {
    Write-Host "==> 1. Building Docker rootfs image..." -ForegroundColor (Get-MessageColour info)
    Invoke-DockerBuild -Tag $ImageTag

    Write-Host "==> 2. Creating temporary export container..." -ForegroundColor (Get-MessageColour info)
    New-DockerContainer -Name $ContainerName -Image $ImageTag

    Write-Host "==> 3. Exporting filesystem to temporary archive ($TarPath)..." -ForegroundColor (Get-MessageColour info)
    Export-DockerContainer -Container $ContainerName -OutputPath $TarPath

    Write-Host "==> 4. Preparing installation folder: $InstallPath" -ForegroundColor (Get-MessageColour info)

    # The image was built and exported in between: the machine may have moved.
    # The last look before anything is erased - an answer that cannot be
    # trusted stops the run.
    $StillRegistered = Assert-DestructionStillMatches -DistroName $DistroName `
        -InstallPath $InstallPath -ConfirmedDestruction $WasRegistered

    if ($StillRegistered) {
        Stop-WslDistro -Name $DistroName
        Start-Sleep -Seconds 1
        Invoke-NativeCommand { wsl.exe --unregister $DistroName } "Could not unregister '$DistroName'." -SuppressOutput
        $Deployment.OldDistroRemoved = $true
    }

    if (Test-Path -Path $InstallPath) {
        Remove-Item -Recurse -Force $InstallPath
    }
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

    # The accounts the imported instance will carry are the image's own, and
    # the tar holds its /etc/passwd whole: the list is read from it, once,
    # and the question below answers from that list. A tar that cannot be
    # read yields no list - the import fails on it moments later anyway.
    $Accounts = @()
    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Accounts = @(tar -xOf $TarPath etc/passwd 2>$null | ForEach-Object { ($_ -split ":")[0] })
    } finally {
        $ErrorActionPreference = $PreviousEAP
    }
    while ($Accounts -contains $UserName) {
        Write-Host "  The account '$UserName' already exists - pick another name." -ForegroundColor (Get-MessageColour warning)
        $UserName = Resolve-DefaultUser -DistroName $DistroName
    }

    Write-Host "==> 5. Importing into WSL ($DistroName)..." -ForegroundColor (Get-MessageColour info)
    # The creation is the engine's: CreateNew imports, writes the marker and
    # re-reads the fleet. -Replace is $WasRegistered - the name was just
    # confirmed for destruction, so it is the build's to take back; a fresh
    # name still passes the guard.
    $Instance = $Manager.CreateNew($DistroName, $TarPath, $UserName, [WslTheme]::Default($DistroName), $WasRegistered)
    $Deployment.DistroRegistered = $true

    Write-Host "==> 6. Running initial onboarding setup..." -ForegroundColor (Get-MessageColour info)
    Invoke-WslFirstBoot -DistroName $DistroName -User $UserName

    Write-Host "==> 7. Shutting down distro so the next boot reads the user configuration..." -ForegroundColor (Get-MessageColour info)
    Stop-WslDistro -Name $DistroName

    # The profile - the font, the icon, the fragment, the tab - belongs to the
    # instance; what it could not do is said in the summary below - this screen
    # is wiped before anyone can read it.
    $ProfileResult = $Instance.ApplyTerminalProfile()

    # Installed after the instance exists; the instance then reads what it
    # carries - its description says so - and the failures are told in the
    # summary below and on the screen the shell opens on.
    $PackResult = Install-SelectedPacks -Manager $Manager -Instance $Instance -PackSelection $PackSelection
    $Instance.RefreshPacks()

    Clear-Host
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
    Write-Host "         WSL Stack Instance Successfully Deployed!          " -ForegroundColor (Get-MessageColour success)
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
    Write-Host ""
    # The instance describes itself; one call shows the lot.
    Write-Host "$Instance"
    foreach ($Note in $ProfileResult.Warnings) {
        Write-Host "  * Terminal profile  : $Note" -ForegroundColor (Get-MessageColour warning)
    }
    if (-not $ProfileResult.Applied) {
        Write-Host "  * Terminal profile  : not automated - configure the appearance manually (Ctrl+,)" -ForegroundColor (Get-MessageColour hint)
    }
    # What it carries is in the description above; only the failures are news.
    if ($PackResult.Colour -eq "Red") {
        Write-Host "  * Packs             : " -NoNewline
        Write-Host "$($PackResult.Report[0])" -ForegroundColor $PackResult.Colour
        foreach ($Line in @($PackResult.Report | Select-Object -Skip 1)) {
            Write-Host "$(' ' * 24)$Line" -ForegroundColor $PackResult.Colour
        }
    }
    Write-Host ""

    $Deployment.Succeeded = $true
}
catch {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour error)
    Write-Host " [ERROR] DURING DEPLOYMENT" -ForegroundColor (Get-MessageColour error)
    Write-Host "============================================================" -ForegroundColor (Get-MessageColour error)
    Write-Host $_.Exception.Message -ForegroundColor (Get-MessageColour error)
    Write-Host ""
}
finally {
    Write-Host "==> Cleaning up temporary build artifacts..." -ForegroundColor (Get-MessageColour info)

    Remove-DeploymentArtifacts -ContainerName $ContainerName -TarPath $TarPath

    if ($Deployment.Succeeded) {
        Write-Host ""
        Write-Host ("-" * 60) -ForegroundColor (Get-MessageColour muted)

        if (-not (Confirm-YesNo "Keep Docker image?")) {
            Write-Host "==> Removing Docker image '$ImageTag'..." -ForegroundColor (Get-MessageColour info)
            if (Test-NativeCommand { docker rmi -f $ImageTag }) {
                Write-Host "Docker image removed." -ForegroundColor (Get-MessageColour success)
            } else {
                Write-Host "The image could not be removed - a container is probably using it. It stays on disk." -ForegroundColor (Get-MessageColour warning)
            }
        } else {
            Write-Host "Docker image retained." -ForegroundColor (Get-MessageColour success)
        }
    } else {
        # Nothing was deployed: the image is what a retry starts from, and there
        # is no deployment to ask about. The retry is only cheap while the run
        # stopped before the import - past that point a distro exists, and the
        # next run opens on the destruction prompt instead.
        Write-Host ""
        Write-Host ("-" * 60) -ForegroundColor (Get-MessageColour muted)
        # Read off the run rather than asked of WSL again: a list that fails to
        # come back must never read as "no distribution".
        $RegisteredNow = $Deployment.DistroRegistered -or ($WasRegistered -and (-not $Deployment.OldDistroRemoved))
        if ($RegisteredNow) {
            Write-Host "A distribution named '$DistroName' is registered: the next run will offer to destroy and rebuild it." -ForegroundColor (Get-MessageColour warning)
        } else {
            Write-Host "The Docker image was kept: the next run reuses it and rebuilds only what changed." -ForegroundColor (Get-MessageColour muted)
        }

        # What became of the packs is told from the run itself: the report
        # exists the moment the install ran - whatever failed after it - and
        # only before it is the chosen list the whole news.
        if ($null -ne $PackResult) {
            Write-Host "The packs chosen earlier: " -NoNewline
            Write-Host "$($PackResult.Report[0])" -ForegroundColor $PackResult.Colour
            foreach ($Line in @($PackResult.Report | Select-Object -Skip 1)) {
                Write-Host "  $Line" -ForegroundColor $PackResult.Colour
            }
        } elseif ($null -ne $PackSelection) {
            $WantedPacks = ($PackSelection.ToAdd | ForEach-Object { $_.Name }) -join ", "
            Write-Host "The packs chosen earlier ($WantedPacks) were not installed: the build stopped before them." -ForegroundColor (Get-MessageColour warning)
            if ($RegisteredNow) {
                Write-Host "Once it is usable, .\wsl.ps1 manage_packs installs them in it." -ForegroundColor (Get-MessageColour muted)
            }
        }
    }

    if ($MutexHeld) {
        $BuildMutex.ReleaseMutex()
    }
    $BuildMutex.Dispose()
}

if ($Deployment.Succeeded) {
    # The report waits for the screen the shell opens on: the Clear-Host below
    # wipes everything written before it, and an answer nobody reads is not an
    # answer.
    $DockerReport = $null
    $DockerReportColour = "Yellow"
    $Docker = Configure-DockerDesktopIntegration -DistroName $DistroName
    if ($Docker) {
        $DockerReport = $Docker.Lines
        $DockerReportColour = $Docker.Colour
    }

    # The window the user came for: the fresh instance in its own Terminal
    # window, its look riding along - icon, name, colours, font - the way the
    # window's open button opens it. A shell borrowed in THIS console would
    # carry none of that, and this console closes with the run.
    #
    # The welcome note used to print here, and it lied - "you are now logged
    # in" is true in the instance's window, not in this one. Handing the note
    # to that window's command line was tried and dropped: Windows Terminal
    # re-splits the line it is given, and the phrases come out as a program
    # name (measured: 0x80070002). The report below is this console's own,
    # and the packs' first-gesture lines went with the note.
    Clear-Host
    if ($DockerReport) {
        foreach ($Line in $DockerReport) { Write-Host $Line -ForegroundColor $DockerReportColour }
    }
    Write-Host ""
    $Instance.OpenShell()
}

# A failed deployment must not look like a success to whatever called this
# script - a shortcut, a wrapper, a future CI job.
if (-not $Deployment.Succeeded) { exit 1 }
