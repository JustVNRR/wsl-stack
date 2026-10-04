# ==============================================================================
# THE ENGINE - THE FLEET, AND NOTHING OF THE SCREEN
# ==============================================================================
# What lives here: the fleet (our instances, the archives, the folders left
# behind), the template's rules (the root, the names, the paths), and one
# method per command of the main menu - the engine side of each: it takes what
# has been CHOSEN and does the work. No question, no line written, no colour.
# This class never talks to anybody.
#
# Who talks to the user, then - the whole wiring, from the way in:
#
#   wsl.ps1                            the menu of the commands, and the
#     |                                dispatch
#     +- scripts\<command>.ps1         the INTERFACE of one command: it asks,
#          |                           hands the answers to the engine, and
#          |                           shows what comes back
#          +- [WslDispatcher] / [WslTerminal]  the asking device (console today)
#          +- $Manager.<Command>(...)   THE ENGINE - this class
#          |     +- [WslInstance]...    the gestures, the state, the disk
#          +- prints the report
#
# The console menu is ONE interface. A graphical one would replace wsl.ps1,
# the scripts and the asking device - and call the same methods below,
# unchanged. The engine does not know there is a console at all.
#
# The contract, one line each:
#   - a method takes the CHOSEN things (an instance, a name, a pack) - it
#     never asks for them; the queries above the commands feed the questions;
#   - it ACTS through the model and re-reads what it changed;
#   - it RETURNS a report, or THROWS - the interface decides what either
#     means on screen, messages and exit codes included.
#
# Nothing without a caller lives here: StopAll and the single-gesture Restart
# were cut - no command calls the first, and the restart command composes Stop
# and Start so each half keeps its own failure line. A method waits until a
# command calls it.
#
# theme is both, and the split is the same as everywhere: WHAT it edits is a
# gesture of the instance, like a stop, and the engine carries the operations
# (SetFont, SetColourScheme, SetIcon, SetIconImage). HOW it navigates - the
# loop of menus, the samples, the questions - is the interface's, and a
# graphical one would replace that loop whole.
#
# This class loads with the other classes (its only class dependencies are
# WslInstance, WslTheme, WslState, WslPackCatalog); the scripts are the thin
# interface; the menu classes stay interface-side.
# ==============================================================================
class WslInstanceManager {
    # The one working folder, no guessing: D:\WSL when D: exists, the user's
    # profile otherwise. The rule lived in six scripts; it lives here once.
    static [string] Root() {
        if (Test-Path "D:\") { return "D:\WSL" }
        return "$env:USERPROFILE\WSL"
    }

    [string]$InstancesRoot
    [string]$ArchivesRoot
    [WslInstance[]]$Instances = @()

    # Folders under the root carrying the marker that no registered instance
    # claims - what an interrupted removal, or an outside `wsl --unregister`,
    # leaves behind. No command removes them: the list shows them, a hand
    # deletes them.
    [string[]]$ForgottenFolders = @()

    WslInstanceManager([string]$instancesRoot) {
        $this.InstancesRoot = $instancesRoot.TrimEnd('\')
        $this.ArchivesRoot  = Join-Path $this.InstancesRoot "archives"
        $this.Refresh()
    }

    # =========================================================================
    # DISCOVERY & INVENTORY
    # =========================================================================

    [void] Refresh() {
        $this.Instances = @()
        $this.ForgottenFolders = @()
        $knownNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $registeredPaths = @()

        # 1. The distributions registered in the Windows registry. Their state
        # comes from one batched question - wsl --list says what runs, about
        # everyone at once - not from one wsl.exe per instance.
        $Running = Get-DistroNames -Running
        foreach ($inst in [WslInstance]::GetAll()) {
            $inst.RefreshArchiveStatus()
            if ($Running -contains $inst.Name) {
                $inst.State = [WslState]::Running
            } else {
                $inst.State = [WslState]::Stopped
            }
            $this.Instances += $inst
            $registeredPaths += $inst.Path
            $null = $knownNames.Add($inst.Name)
        }

        # 2. The archives with no registered distribution left: an instance
        # that lives only as a folder under <root>\archives - the tar inside,
        # and the look beside it.
        if (Test-Path $this.ArchivesRoot) {
            foreach ($archiveDir in (Get-ChildItem -Path $this.ArchivesRoot -Directory | Sort-Object Name)) {
                $tar = Get-ChildItem -Path $archiveDir.FullName -Filter "*.tar*" -File |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if (-not $tar) { continue }
                if ($knownNames.Contains($archiveDir.Name)) { continue }

                $archivedInst = [WslInstance]::new()
                $archivedInst.Name = $archiveDir.Name
                $archivedInst.Path = Join-Path $this.InstancesRoot $archiveDir.Name
                $archivedInst.HasArchive = $true
                $archivedInst.ArchivePath = $archiveDir.FullName
                $archivedInst.State = [WslState]::Archived

                $this.Instances += $archivedInst
                $null = $knownNames.Add($archiveDir.Name)
            }
        }

        # 3. Marked folders that no instance claims
        if (Test-Path $this.InstancesRoot) {
            foreach ($folder in (Get-ChildItem -Path $this.InstancesRoot -Directory -ErrorAction SilentlyContinue)) {
                if ((Test-TemplateInstance -Folder $folder.FullName) -and
                    ($registeredPaths -notcontains $folder.FullName)) {
                    $this.ForgottenFolders += $folder.FullName
                }
            }
        }
    }

    # =========================================================================
    # LOOKUP & VALIDATION - WHAT THE QUESTIONS ARE BUILT ON
    # =========================================================================

    # What the commands call "ours": registered, carrying the marker, by name -
    # the filter every list applies before showing anything. Their state comes
    # along, from one batched question - wsl.exe says what runs, about
    # everyone at once - so a caller never has to ask a second time.
    static [WslInstance[]] Ours() {
        $Running = Get-DistroNames -Running
        $ours = @([WslInstance]::GetAll() | Where-Object { Test-TemplateInstance -Folder $_.Path })
        foreach ($instance in $ours) {
            if ($Running -contains $instance.Name) {
                $instance.State = [WslState]::Running
            } else {
                $instance.State = [WslState]::Stopped
            }
        }
        return @($ours | Sort-Object Name)
    }

    # The ones a question can offer: all of ours, running or stopped.
    [WslInstance[]] OursHere() {
        return @([WslInstanceManager]::Ours())
    }

    [WslInstance] FindByName([string]$name) {
        return ($this.Instances | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    }

    [bool] IsNameAvailable([string]$name) {
        return $null -eq $this.FindByName($name)
    }

    # The name rule every command applies: letters, digits, '.', '_' and '-',
    # starting with a letter or a digit.
    [bool] IsNameUsable([string]$name) {
        return [bool]("$name" -match '^[A-Za-z0-9][A-Za-z0-9_.-]*$')
    }

    [bool] IsPathOccupied([string]$path) {
        return (Test-Path $path) -and (@(Get-ChildItem -Path $path -Force).Count -gt 0)
    }

    # =========================================================================
    # QUERIES - WHAT FEEDS THE QUESTIONS AND THE REPORTS
    # =========================================================================

    # The packs an instance carries, by name - or $null when it cannot say
    # where its user's home is (the caller says so and stops).
    [object] InstalledPacks([WslInstance]$Instance) {
        # Not named $home: HOME is a PowerShell automatic variable, read-only,
        # and the assignment throws - paid once already, in RefreshPacks.
        $InstanceHome = Get-InstanceHome -DistroName $Instance.Name
        if (-not $InstanceHome) { return $null }
        $PacksDirectory = "$InstanceHome/.config/packs"
        return @(Get-InstalledPacks -DistroName $Instance.Name -PacksDirectory $PacksDirectory)
    }

    [string] PacksDirectoryOf([WslInstance]$Instance) {
        return "$(Get-InstanceHome -DistroName $Instance.Name)/.config/packs"
    }

    # The packs a question may offer: this checkout carries them and the
    # instance lacks them. -Offered only - an invisible pack arrives with the
    # pack that requires it, never offered.
    [WslPack[]] CandidatePacks([WslInstance]$Instance, [WslPackCatalog]$Catalog) {
        $PacksDirectory = $this.PacksDirectoryOf($Instance)
        $Installed = @(Get-InstalledPacks -DistroName $Instance.Name -PacksDirectory $PacksDirectory)
        return @($Catalog.AvailablePacks | Where-Object { $_.Offered -and $Installed -notcontains $_.Name })
    }

    # The packs this instance carries that a user may take out by hand: the
    # invisible ones leave with the last pack that requires them.
    [string[]] RemovablePacks([WslInstance]$Instance, [WslPackCatalog]$Catalog) {
        $PacksDirectory = $this.PacksDirectoryOf($Instance)
        $Installed = @(Get-InstalledPacks -DistroName $Instance.Name -PacksDirectory $PacksDirectory)
        $Offered = @()
        foreach ($Name in $Installed) {
            $Pack = $Catalog.GetPack($Name)
            if ($null -ne $Pack -and -not $Pack.Offered) { continue }
            $Offered += $Name
        }
        return $Offered
    }

    # What leaves with a pack: the chosen one first, then every pack nothing
    # installed requires any more - the other order would ask a remove.sh
    # whether a neighbour still claims its packages while it can still say
    # yes. -Missing names the ones installed before packs had a remove.sh.
    [object] RemovalPlan([WslInstance]$Instance, [string]$PackName) {
        $Catalog = Get-PackCatalog
        $PacksDirectory = $this.PacksDirectoryOf($Instance)
        $Installed = @(Get-InstalledPacks -DistroName $Instance.Name -PacksDirectory $PacksDirectory)
        $ToRemove = @($Catalog.ResolveRemoval($Installed, @($PackName), @()))

        $Missing = @()
        $Code = 0
        foreach ($Name in $ToRemove) {
            $Its = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Name
            if (-not (Test-PackScript -DistroName $Instance.Name -Target $Its -Script "remove.sh" -ExitCode ([ref]$Code))) {
                $Missing += $Name
            }
        }
        return [PSCustomObject]@{ ToRemove = $ToRemove; Missing = $Missing }
    }

    # What a copy of that instance under that name costs: the copy reads the
    # instance into an archive and unpacks it into the new folder, both at the
    # same time - twice the disk is the peak a caller checks against.
    [object] DuplicationCost([WslInstance]$Instance, [string]$Name) {
        $VhdxPath = Join-Path $Instance.Path "ext4.vhdx"
        $DiskBytes = if (Test-Path $VhdxPath) { (Get-Item $VhdxPath).Length } else { 0 }
        $NeededBytes = 2 * $DiskBytes
        $InstallPath = [System.IO.Path]::GetFullPath((Join-Path $this.InstancesRoot $Name))
        $DriveLetter = (Split-Path -Qualifier $InstallPath).TrimEnd(':')
        $FreeBytes = (Get-PSDrive -Name $DriveLetter).Free
        return [PSCustomObject]@{ DiskBytes = $DiskBytes; NeededBytes = $NeededBytes; FreeBytes = $FreeBytes; DriveLetter = $DriveLetter; InstallPath = $InstallPath }
    }

    # =========================================================================
    # THE MENU'S COMMANDS - ONE METHOD EACH, ENGINE SIDE
    # =========================================================================

    # list - the fleet as it is: ours, the archives on disk, the folders left
    # behind. Read-only, so it can run at any moment.
    [object] List() {
        $Archives = @()
        if (Test-Path $this.ArchivesRoot) {
            $Archives = @(Get-ChildItem -Path $this.ArchivesRoot -Directory |
                Where-Object { (Get-ChildItem -Path $_.FullName -Filter "*.tar*" -File).Count -gt 0 } |
                Sort-Object LastWriteTime -Descending)
        }
        return [PSCustomObject]@{
            Instances = @($this.OursHere())
            Archives  = $Archives
            Forgotten = @($this.ForgottenFolders)
        }
    }

    # build - the fleet side of it. The command keeps its own scene (the
    # image, the download, the questions of prompts.ps1); what is the fleet's
    # is here: the name and the folder are this template's rules, the creation
    # is the instance's own Build, and the fleet is re-read after.
    #
    # -Replace says the caller went through the destruction confirmation and
    # its last look: the old distribution was destroyed a moment ago, and the
    # name is its to take back. The name guard asks WINDOWS, live - not the
    # inventory this object read at its birth, which still carries the
    # destroyed one and would refuse a name the build is entitled to.
    [WslInstance] CreateNew([string]$name, [string]$tarRootfs, [string]$user, [WslTheme]$look, [bool]$Replace) {
        if (-not $this.IsNameUsable($name)) {
            throw "'$name' is not usable as an instance name (letters, digits, '.', '_' and '-' only)."
        }
        if (-not $Replace -and ((Get-DistroNames) -contains $name)) {
            throw "An instance named '$name' is registered on this machine."
        }

        $installPath = Join-Path $this.InstancesRoot $name
        if ($this.IsPathOccupied($installPath)) {
            throw "Installation folder '$installPath' already exists and is not empty."
        }

        $newInstance = [WslInstance]::Build($name, $installPath, $tarRootfs, $user, $look)
        $this.Refresh()
        return $newInstance
    }

    # start / stop - the menu's engine side, and nothing more than the route:
    # the gesture, the state it moves and the failure it throws all belong to
    # the instance's own Start()/Stop() - the state moves only once the gesture
    # succeeded, and the throw travels. Nothing here pretends otherwise: the
    # interface catches what it catches, and says it.
    #
    # No Restart: the restart command composes these two, because each half
    # fails on its own and the interface keeps a line for each. A single route
    # would have to guess which half broke.
    [WslInstance] Start([WslInstance]$Instance) {
        $Instance.Start()
        return $Instance
    }

    [WslInstance] Stop([WslInstance]$Instance) {
        $Instance.Stop()
        return $Instance
    }

    # shell - the session is a process that owns the console until the user
    # leaves; the exit code is the shell's own, handed back, not interpreted.
    [int] Shell([WslInstance]$Instance) {
        return $Instance.Shell()
    }

    # add_pack - the pack and whatever it requires, requirements first. Each
    # step: the folder copied in, the install script run from inside it, and a
    # step that halves is undone - a half-installed pack is worse than none,
    # the Makefile loads whatever folder is there.
    [object] AddPack([WslInstance]$Instance, [string]$PackName) {
        $Catalog = Get-PackCatalog
        $PacksDirectory = $this.PacksDirectoryOf($Instance)
        $Installed = @(Get-InstalledPacks -DistroName $Instance.Name -PacksDirectory $PacksDirectory)

        $ToInstall = @()
        foreach ($Name in @($Catalog.ResolveSelection(@($PackName), $Installed))) {
            $Entry = $Catalog.GetPack($Name)
            if ($null -ne $Entry) { $ToInstall += $Entry }
        }

        # The installs run behind WSL's own door: passwordless sudo for their
        # length, nothing of it after - their files stay the user's.
        $SudoWindow = $false
        if ($ToInstall.Count -gt 0) { $SudoWindow = Enable-PackSudo -DistroName $Instance.Name }
        try {
            $Steps = @()
            foreach ($Entry in $ToInstall) {
                $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Entry.Name
                $Code = 0

                if (-not (Copy-PackIntoInstance -DistroName $Instance.Name -PackPath $Entry.Path -Target $Target -ExitCode ([ref]$Code))) {
                    return [PSCustomObject]@{ Outcome = "copy-failed"; Steps = $Steps; Entry = $Entry; ExitCode = $Code; ToInstall = $ToInstall }
                }

                Invoke-PackScript -DistroName $Instance.Name -Target $Target -Script "install.sh" -ExitCode ([ref]$Code)
                $InstallCode = $Code

                # Exit code 2: the pack asked a question and the answer was no
                # (the claude pack asks about a second copy installed on Windows).
                # Its folder goes back out; nothing is broken.
                if ($InstallCode -eq 2) {
                    Remove-PackFolder -DistroName $Instance.Name -Target $Target -ExitCode ([ref]$Code)
                    $Steps += [PSCustomObject]@{ Name = $Entry.Name; Code = 2; Related = ($Entry.Name -ne $PackName) }
                    return [PSCustomObject]@{ Outcome = "declined"; Steps = $Steps; Entry = $Entry; ExitCode = 0; ToInstall = $ToInstall }
                }

                # The folder goes back out - and only it: what the install already
                # wrote stays, and running this again picks up there.
                if ($InstallCode -ne 0) {
                    Remove-PackFolder -DistroName $Instance.Name -Target $Target -ExitCode ([ref]$Code)
                    $Steps += [PSCustomObject]@{ Name = $Entry.Name; Code = $InstallCode; Related = ($Entry.Name -ne $PackName) }
                    return [PSCustomObject]@{ Outcome = "failed"; Steps = $Steps; Entry = $Entry; ExitCode = $InstallCode; ToInstall = $ToInstall }
                }

                $Steps += [PSCustomObject]@{ Name = $Entry.Name; Code = 0; Related = ($Entry.Name -ne $PackName) }
            }
            return [PSCustomObject]@{ Outcome = "installed"; Steps = $Steps; Entry = $null; ExitCode = 0; ToInstall = $ToInstall }
        } finally {
            if ($SudoWindow) { Disable-PackSudo -DistroName $Instance.Name }
        }
    }

    # remove_pack - each pack's own remove.sh runs from inside its folder (it
    # may ask for a password - it did not come alone, it travelled with the
    # pack), then the folder goes. The leftovers of the system side are tidied
    # once, at the end: a question about the instance, not about a pack.
    [object] RemovePack([WslInstance]$Instance, [string]$PackName) {
        $Plan = $this.RemovalPlan($Instance, $PackName)
        $PacksDirectory = $this.PacksDirectoryOf($Instance)

        $Steps = @()
        foreach ($Name in $Plan.ToRemove) {
            $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Name
            $Code = 0

            if ($Plan.Missing -notcontains $Name) {
                Invoke-PackScript -DistroName $Instance.Name -Target $Target -Script "remove.sh" -ExitCode ([ref]$Code) -AsRoot
                # The folder stays when the script failed: the pack is still
                # half in place, and its files are what a second attempt needs.
                if ($Code -ne 0) {
                    return [PSCustomObject]@{ Outcome = "self-failed"; Steps = $Steps; Name = $Name; ExitCode = $Code; Plan = $Plan }
                }
            }

            Remove-PackFolder -DistroName $Instance.Name -Target $Target -ExitCode ([ref]$Code)
            if ($Code -ne 0) {
                return [PSCustomObject]@{ Outcome = "folder-failed"; Steps = $Steps; Name = $Name; ExitCode = $Code; Plan = $Plan }
            }
            $Steps += [PSCustomObject]@{ Name = $Name; Code = 0 }
        }

        $CleanupCode = 0
        $Cleaned = Invoke-PackOrphanCleanup -DistroName $Instance.Name -ExitCode ([ref]$CleanupCode)
        return [PSCustomObject]@{ Outcome = "removed"; Steps = $Steps; Cleaned = $Cleaned; CleanupCode = $CleanupCode; Plan = $Plan }
    }

    # manage_packs - what was ticked arrives, what was unticked leaves; the
    # checklist itself is the interface's (prompts.ps1's Select-Packs). What
    # stands comes back read from the instance: the folder is the state.
    [object] ManagePacks([WslInstance]$Instance, [WslPack[]]$ToAdd, [string[]]$ToRemove, [string]$ResumeHint) {
        # A class method takes no default; the one packs.ps1 would have used
        # applies when the caller has none of its own (the build does).
        if (-not $ResumeHint) { $ResumeHint = "Run this again to finish." }
        $PacksDirectory = $this.PacksDirectoryOf($Instance)
        $Failure = Invoke-PackApply -DistroName $Instance.Name -PacksDirectory $PacksDirectory `
            -ToAdd $ToAdd -ToRemove $ToRemove -ResumeHint $ResumeHint
        $Now = @(Get-InstalledPacks -DistroName $Instance.Name -PacksDirectory $PacksDirectory)

        return [PSCustomObject]@{
            Failure  = $Failure
            Now      = $Now
            Added    = @($ToAdd | ForEach-Object { $_.Name })
            Removed  = @($ToRemove)
            ExitCode = if ($null -ne $Failure) { $Failure.ExitCode } else { 0 }
        }
    }

    # unregister - the destruction: the copy first when asked (the instance's
    # own name on disk), then the instance's own Unregister - its stop with
    # the failure ignored, the unregister, the folder, the Windows-side
    # housekeeping. What it found comes back for the report.
    [object] Unregister([WslInstance]$Instance, [bool]$ArchiveFirst) {
        $ArchiveReport = $null
        if ($ArchiveFirst) {
            # The copy is the last moment to keep something: a failed archive
            # stops here, and the sentence says nothing of the instance was
            # touched - the old command said as much before it handed over.
            try {
                $ArchiveReport = $this.Archive($Instance, $Instance.Name, "tar.gz")
            } catch {
                throw "The archive did not complete - nothing was destroyed. $($_.Exception.Message)"
            }
        }

        $Removed = $Instance.Unregister($false)
        return [PSCustomObject]@{ Archive = $ArchiveReport; Removed = $Removed }
    }

    # archive - the copy on disk: the export, then the look beside the tar (a
    # partial archive is removed inside the instance's own Archive - left on
    # disk it would look exactly like a backup later on). Stopping the
    # instance first, when it runs, is the interface's question; what becomes
    # of it after is the interface's choice.
    [object] Archive([WslInstance]$Instance, [string]$Name, [string]$Format) {
        if (-not (Test-Path -Path $this.ArchivesRoot)) {
            New-Item -ItemType Directory -Path $this.ArchivesRoot -Force | Out-Null
        }

        $ArchiveDir = [System.IO.Path]::GetFullPath((Join-Path $this.ArchivesRoot $Name))
        $Destination = Join-Path $ArchiveDir "$Name.$Format"

        $null = $Instance.Archive($Name, $Format)
        $Archive = Get-Item -Path $Destination
        $Look = $Instance.ArchiveLook($ArchiveDir)

        return [PSCustomObject]@{ Name = $Name; ArchiveDir = $ArchiveDir; Destination = $Destination; Archive = $Archive; Look = $Look }
    }

    # restore - an archive back on its feet, under a name of its own. The tar
    # does not carry the look; it sits next to it, and State re-applies it.
    # Version 2, like build: a tar does not carry the version it came from,
    # and WSL 1 is not what this repository builds.
    [WslInstance] RestoreFromArchive([string]$ArchiveDir, [string]$Name) {
        if (-not $this.IsNameUsable($Name)) {
            throw "'$Name' is not usable as an instance name (letters, digits, '.', '_' and '-' only)."
        }
        if (-not $this.IsNameAvailable($Name)) {
            throw "An instance named '$Name' already exists."
        }

        $InstallPath = [System.IO.Path]::GetFullPath((Join-Path $this.InstancesRoot $Name))
        if (Test-Path $InstallPath) {
            throw "A folder with that name already exists: $InstallPath"
        }

        $null = [WslInstance]::Restore($ArchiveDir, $Name, $InstallPath)

        # The look and Docker's entry, which a tar carries neither of - the
        # marker was written by Restore, right after the import.
        Set-InstanceState -Name $Name -InstallPath $InstallPath -Folder $ArchiveDir
        $this.Refresh()
        return $this.FindByName($Name)
    }

    # duplicate - the source is only read; the copy lands under a name of its
    # own, with the look captured before the export and re-applied after.
    # Stopping the source first, and starting it again after, is the
    # interface's doing: it is the one that asked the question.
    [object] Duplicate([WslInstance]$Instance, [string]$Name) {
        if (-not $this.IsNameUsable($Name)) {
            throw "'$Name' is not usable as an instance name (letters, digits, '.', '_' and '-' only)."
        }
        if (-not $this.IsNameAvailable($Name)) {
            throw "An instance named '$Name' already exists."
        }

        $FullDestination = [System.IO.Path]::GetFullPath((Join-Path $this.InstancesRoot $Name))
        $DestinationDir = Split-Path -Path $FullDestination -Parent
        if (-not (Test-Path -Path $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }

        # The source is only read; the temporary image is removed by the copy
        # itself, in all cases - it is worth twice the disk.
        $Copy = $Instance.Duplicate($Name)

        $CopyVhdx = Join-Path $FullDestination "ext4.vhdx"
        $CopyBytes = if (Test-Path $CopyVhdx) { (Get-Item $CopyVhdx).Length } else { 0 }

        # The copy has its own profile and its own guid: the look is re-applied
        # from the values captured before the export - Docker's entry too,
        # keyed by name.
        Set-InstanceState -Name $Name -InstallPath $FullDestination -Appearance $Copy.Look
        $this.Refresh()

        return [PSCustomObject]@{ Instance = $this.FindByName($Name); InstallPath = $FullDestination; CopyBytes = $CopyBytes }
    }

    # shrink - the compact, in place, working on a running instance; it
    # refuses on its own if the disk cannot be compacted. The instance is left
    # the way it was found. Archiving first, when asked, is the interface's:
    # it calls Archive before this.
    [object] Shrink([WslInstance]$Instance) {
        $WasRunning = ($Instance.State -eq [WslState]::Running)
        $Result = $Instance.Shrink()

        $Restarted = $false
        if ($WasRunning) {
            try { $Instance.Start(); $Restarted = $true } catch { $Restarted = $false }
        }

        return [PSCustomObject]@{
            Before     = $Result.Before
            After      = $Result.After
            Freed      = $Result.Freed
            WasRunning = $WasRunning
            Restarted  = $Restarted
        }
    }

    # =========================================================================
    # THE LOOK - THE INSTANCE'S WEAR, ONE GESTURE AT A TIME
    # =========================================================================
    # Same contract as start/stop, and the same correction: the writes - the
    # profile's guid, the fragment, the look, the recipe kept through (a font
    # or colour change must not eat the tile) - are the INSTANCE's own, next
    # to its ApplyTerminalProfile, which walks the same road. The manager
    # routes and pretends nothing; a machine without the profile throws, and
    # the interface says it.

    [WslInstance] SetFont([WslInstance]$Instance, [string]$FontName) {
        $Instance.SetFont($FontName)
        return $Instance
    }

    [WslInstance] SetColourScheme([WslInstance]$Instance, [string]$SchemeName) {
        $Instance.SetColourScheme($SchemeName)
        return $Instance
    }

    # The drawn recipe comes back from the instance - the drawing settles the
    # parts the recipe left open.
    [object] SetIcon([WslInstance]$Instance, [object]$Recipe) {
        return $Instance.SetIcon($Recipe)
    }

    [WslInstance] SetIconImage([WslInstance]$Instance, [string]$Source) {
        $Instance.SetIconImage($Source)
        return $Instance
    }

    # wslconfig - the machine's own settings file, created commented when
    # there is none. Opening it is the interface's (Windows picks the
    # application; a graphical interface would show its own editor).
    [object] WslConfig() {
        $Path = Join-Path $env:USERPROFILE ".wslconfig"
        $Created = $false
        if (-not (Test-Path $Path)) {
            @'
# WSL's Windows-wide settings. Read when the WSL machine starts: `wsl --shutdown`
# then a new start applies a change.
#
# The common keys: https://learn.microsoft.com/windows/wsl/wsl-config
#
# [wsl2]
# memory=8GB          # the machine's memory cap
# processors=4        # the CPUs it may use
# dnsTunneling=true   # WSL answers the DNS itself
'@ | Set-Content -Path $Path -Encoding ascii
            $Created = $true
        }
        return [PSCustomObject]@{ Path = $Path; Created = $Created }
    }

}
