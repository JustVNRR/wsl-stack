# ==============================================================================
# AN INSTANCE
# ==============================================================================
# One distribution: registered, or left as an archive. Its folder, its user,
# its WSL version, the look Windows Terminal gives it, the packs it carries -
# and the gestures: start, stop, restart, shell, shrink, archive, restore,
# duplicate, unregister.
class WslInstance {
    [string]$Name
    [string]$Path
    [string]$DefaultUser

    # The WSL version the instance runs as (1 or 2). A copy is imported with
    # the version of its source.
    [int]$Version = 2

    # Archive tracking: an archive is a folder under <root>\archives - the tar
    # inside, and the look (instance.json, terminal-icon.png) beside it.
    [bool]$HasArchive = $false
    [string]$ArchivePath

    [WslState]$State = [WslState]::Unknown

    [WslTheme]$Look

    # The packs the instance carries, by name: inside an instance a pack is its
    # folder - what it requires and whether it is ever offered come from the
    # catalog, the rule the commands have always followed.
    [string[]]$InstalledPacks = @()

    # The empty constructor only: an instance is built property by property,
    # never by a constructor that asks wsl.exe for the state - that question
    # belongs to the callers that actually need it (RefreshState).
    WslInstance() {}

    # The instance as a block of lines, its look and its packs included -
    # whose description is the theme's own. Whoever shows it decides where
    # and when; one Write-Host is enough.
    [string] ToString() {
        # Not named $Look: that is this class's own member (and PowerShell does
        # not tell the two cases apart).
        $LookLine = if ($this.Look) { "$($this.Look)" } else { "-" }
        $PacksLine = if ($this.InstalledPacks.Count -eq 0) { "none" } else { $this.InstalledPacks -join ", " }
        $Lines = @(
            "  * Distribution Name : $($this.Name)",
            "  * Default User      : $($this.DefaultUser)",
            "  * Install Path      : $($this.Path)",
            "  * Look              : $LookLine",
            "  * Packs             : $PacksLine"
        )
        return ($Lines -join "`n")
    }

    # =========================================================================
    # INSTANCE METHODS: Lifecycle (State, Start, Stop, Restart, Shrink)
    # =========================================================================

    [void] RefreshArchiveStatus() {
        $archiveDir = $null
        if ($this.Path) {
            $archiveDir = Join-Path (Split-Path $this.Path -Parent) "archives\$($this.Name)"
        }
        if ($archiveDir -and (Test-Path $archiveDir)) {
            $this.HasArchive  = $true
            $this.ArchivePath = $archiveDir
            return
        }
        $this.HasArchive  = $false
        $this.ArchivePath = $null
    }

    [void] RefreshState() {
        # Asked of wsl.exe: the registry does not say whether one is RUNNING.
        # An instance that is not there at all reads as Archived when an
        # archive carries its name, Unknown otherwise.
        $pattern = "^\s*\*?\s*$([regex]::Escape($this.Name))\s+(\w+)"
        $rawState = $null
        foreach ($line in @(& wsl.exe -l -v 2>$null)) {
            if ("$line" -match $pattern) { $rawState = $Matches[1]; break }
        }
        if ($rawState) {
            $this.State = if ($rawState -eq "Running") { [WslState]::Running } else { [WslState]::Stopped }
        } elseif ($this.HasArchive) {
            $this.State = [WslState]::Archived
        } else {
            $this.State = [WslState]::Unknown
        }
    }

    [void] Start() {
        if ($this.State -eq [WslState]::Archived) {
            throw "Cannot start an archived instance. Restore it first."
        }
        # --exec runs a command and returns: it comes up without opening a shell.
        Invoke-External { wsl.exe -d $this.Name --exec /bin/true } "Could not start '$($this.Name)'."
        $this.State = [WslState]::Running
    }

    [void] Stop() {
        Invoke-External { wsl.exe --terminate $this.Name } "Could not stop '$($this.Name)'."
        $this.State = [WslState]::Stopped
    }

    [void] Restart() {
        $this.Stop()
        $this.Start()
    }

    # Opens a shell on the caller's console and steps aside: the terminal
    # belongs to it until the user leaves. A process of its own (Start-Process),
    # because run from here the session's output would fall under the method's
    # own rule - swallowed. The name goes in unquoted - wsl.exe parses its own
    # line and does not strip quotes, so a quoted name stops matching - and the
    # `~` rides inside the string, where nothing expands it. The shell's own
    # exit code comes back - handed over, not read.
    [int] Shell() {
        $Arguments = '-d {0} --cd ~' -f $this.Name
        # -Wait waits on the process AND its descendants: a WSL helper that
        # outlives the shell holds the hand back. The session's own process is
        # the one to wait for.
        $Process = Start-Process wsl.exe -ArgumentList $Arguments -NoNewWindow -PassThru
        $Process.WaitForExit()
        return $Process.ExitCode
    }

    # The .vhdx's size on disk, not what its filesystem holds.
    [long] DiskSize() {
        $vhdx = Join-Path $this.Path "ext4.vhdx"
        if (Test-Path $vhdx) { return (Get-Item $vhdx).Length }
        return 0
    }

    # One command, in place, on a running instance; it refuses on its own when
    # the disk cannot be compacted. Returns the sizes for the caller's report.
    [object] Shrink() {
        $before = $this.DiskSize()
        Invoke-External { wsl.exe --manage $this.Name --compact } "The compact failed."
        $after = $this.DiskSize()
        return [PSCustomObject]@{ Before = $before; After = $after; Freed = $before - $after }
    }

    # =========================================================================
    # INSTANCE METHODS: Duplication, Archival & Destruction
    # =========================================================================

    # Copies the instance under another name: the export to a temporary tar,
    # the import at THIS instance's version, the marker, and a fresh capture
    # of the look for the caller to re-apply once the copy exists. The caller
    # stops the source first - stopping is a decision, and decisions belong to
    # the commands. Returns the copy's folder and that look.
    [PSCustomObject] Duplicate([string]$newName) {
        # Not named $Look: that is the instance's own member (and PowerShell
        # does not tell the two cases apart).
        $LookFile = New-InstanceLook -Name $this.Name -Icon (Get-IconRecipe -Name $this.Name)

        $targetRoot = Split-Path $this.Path -Parent
        $newPath = Join-Path $targetRoot $newName
        $tempTar = Join-Path $targetRoot "$newName-export.tar.gz"

        try {
            Invoke-External { wsl.exe --export $this.Name $tempTar --format tar.gz } "The export failed."
            # The copy is imported as the version of its source.
            Invoke-External { wsl.exe --import $newName $newPath $tempTar --version $this.Version } "The import failed."
        } finally {
            if (Test-Path $tempTar) {
                Remove-Item -Path $tempTar -Force -ErrorAction SilentlyContinue
            }
        }

        # Ours from here on, whatever happens next.
        New-InstanceMarker -Folder $newPath -By "duplicate"
        return [PSCustomObject]@{ Path = $newPath; Look = $LookFile }
    }

    # Writes the instance to <root>\archives\<name>: the tar
    # (<name>.<format>). The look follows with ArchiveLook - a tar carries
    # neither the icon nor the colours - and the caller stops the instance
    # first: stopping is a decision, and decisions belong to the commands.
    # Returns the archive folder. Two signatures because a class method takes
    # no default: the one-argument call is the ordinary tar.gz.
    [string] Archive([string]$name) {
        return $this.Archive($name, "tar.gz")
    }

    [string] Archive([string]$name, [string]$format) {
        $archiveDir = Join-Path (Split-Path $this.Path -Parent) "archives\$name"
        if (-not (Test-Path $archiveDir)) {
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        }

        $archiveFile = Join-Path $archiveDir "$name.$format"
        try {
            Invoke-External { wsl.exe --export $this.Name $archiveFile --format $format } "The export failed."
        } catch {
            # A partial archive left on disk would look like a backup later.
            if (Test-Path $archiveFile) {
                Remove-Item -Path $archiveFile -Force -ErrorAction SilentlyContinue
            }
            throw
        }

        $this.HasArchive  = $true
        $this.ArchivePath = $archiveDir
        return $archiveDir
    }

    # The other half of an archive: what Windows knows about the instance,
    # written beside the tar - the instance's own file, refreshed, and the
    # icon. Returns what the caller reports (a class does not write to the
    # screen): the font, the colours, whether the icon came, Docker's answer.
    [object] ArchiveLook([string]$folder) {
        $Appearance = Get-InstanceAppearance -Name $this.Name
        # The same file the instance keeps in its own folder, refreshed: what
        # this machine has right now, and the icon's recipe as the instance
        # noted it. Not named $Look: that is the instance's own member.
        $LookFile = New-InstanceLook -Name $this.Name -Icon (Get-IconRecipe -Name $this.Name)

        if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        $LookFile | ConvertTo-Json | Set-Content -Path (Join-Path $folder "instance.json") -Encoding Utf8

        $IconCopied = $false
        if ($Appearance.IconPath) {
            Copy-Item -Path $Appearance.IconPath -Destination (Join-Path $folder "terminal-icon.png") -Force
            $IconCopied = $true
        }

        return [PSCustomObject]@{
            Font        = $Appearance.FontName
            ColorScheme = $Appearance.ColorScheme
            IconCopied  = $IconCopied
            Docker      = $LookFile.Docker
        }
    }

    # Removes the instance from WSL and from the Windows side: the stop whose
    # own failure is ignored - a distro half gone must not block its own
    # removal - the archive when asked for, the unregister, what is left of
    # the install folder, and the Terminal and Docker traces, whose mechanics
    # are the shared cleanup functions' (the build prunes the same ghosts the
    # same way). Returns what the caller reports: the folder's fate, the
    # counts, Docker's answer.
    [object] Unregister([bool]$toArchive) {
        # The raw terminate, failure ignored on purpose, then the pause the
        # command always took: wsl --unregister right after would run too
        # early.
        $null = & wsl.exe --terminate $this.Name 2>$null
        Start-Sleep -Seconds 1

        # The archive first, when asked for: the copy exists before anything
        # is destroyed.
        if ($toArchive) {
            $ArchiveDir = $this.Archive($this.Name)
            [void]$this.ArchiveLook($ArchiveDir)
        }

        $FolderExisted = $this.Path -and (Test-Path $this.Path)
        Invoke-External { wsl.exe --unregister $this.Name } "WSL unregister failed."

        # wsl --unregister removes the install folder with the disk; anything
        # left here is the exception.
        $FolderState = "not found"
        if ($this.Path -and (Test-Path $this.Path)) {
            Remove-Item -Path $this.Path -Recurse -Force
            $FolderState = "removed"
        } elseif ($FolderExisted) {
            $FolderState = "removed with the distribution"
        }

        # Our own appearance fragment goes by name; the rest is the shared
        # cleanup.
        $Fragments = Get-WslFragmentGuids -Name $this.Name
        $Ghosts = Remove-TerminalGhostEntries -Name $this.Name -LiveGuids $Fragments.Guids
        $GhostTotal = 0
        foreach ($File in $Ghosts.Files) { $GhostTotal += $File.Pruned }

        $AppearanceRemoved = 0
        $OwnFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$($this.Name).json"
        if (Test-Path $OwnFragment) {
            Remove-Item -Path $OwnFragment -Force -ErrorAction SilentlyContinue
            $AppearanceRemoved++
        }
        $AppearanceRemoved += @(Remove-StaleAppearanceFragments -LiveGuids $Fragments.Guids).Count

        $Docker = Remove-DockerIntegration -Name $this.Name

        if ($this.HasArchive) {
            $this.State = [WslState]::Archived
        } else {
            $this.State = [WslState]::Unknown
        }

        return [PSCustomObject]@{
            FolderState      = $FolderState
            GhostsPruned     = $GhostTotal
            Unreadable       = $Ghosts.Unreadable
            FragmentsRemoved = $AppearanceRemoved
            DockerRemoved    = $Docker.Removed
            DockerError      = $Docker.Error
        }
    }

    # =========================================================================
    # INSTANCE METHODS: Terminal Appearance
    # =========================================================================

    [void] SetFont([string]$fontName) {
        if (-not $this.Look) { $this.Look = [WslTheme]::new() }
        $this.Look.FontName = $fontName
        $this.ApplyTerminalProfile()
    }

    [void] SetColorScheme([string]$schemeName) {
        if (-not $this.Look) { $this.Look = [WslTheme]::new() }
        $this.Look.ColorScheme = $schemeName
        $this.ApplyTerminalProfile()
    }

    # The image case: a file of the user's replaces the icon. Changing the
    # recipe (letters, colours) instead redraws it, with assets\make-icon.ps1.
    [void] SetIcon([string]$iconPath) {
        if (-not $this.Look) { $this.Look = [WslTheme]::new() }
        $this.Look.IconPath = $iconPath
        $this.ApplyTerminalProfile()
    }

    # Makes the look live on the Windows side: the font it names (fetched when
    # missing, best effort), the icon drawn from the instance's own name, the
    # fragment Windows Terminal reads under the guid WSL gave the instance,
    # and the instance's own file - the one an archive carries. Everything
    # derives from the instance and the look; the caller does the talking.
    # Answers whether a profile could be applied at all, with the odd news
    # worth a line.
    [object] ApplyTerminalProfile() {
        if (-not $this.Look) { $this.Look = [WslTheme]::Default($this.Name) }

        $Warnings = @()

        # The font the look names: Windows must have it before the fragment
        # points at it.
        if ($this.Look.FontMissing()) {
            $FontStatus = $this.Look.EnsureFont()
            if ($FontStatus.State -ne "installed") {
                $Warnings += "the font '$($this.Look.FontName)' would not install: $($FontStatus.Error)"
            }
        }

        # The icon is drawn from the instance's own name, letters and colours
        # both. It is decoration: a failure is said here, leaves no file, and
        # the fragment below drops the icon line.
        $IconPath = Join-Path $this.Path "terminal-icon.png"
        $IconDrawn = $false
        $Icon = @{}
        try {
            # -What: the letters and colours read back into the instance's file,
            # so a later change of one keeps the other. -Quiet: nothing said
            # about a drawing that worked. In a method, $PSScriptRoot is this
            # file's folder - two levels under the repository's root.
            $IconScript = Join-Path $PSScriptRoot "..\..\assets\make-icon.ps1"
            $Drawn = & $IconScript -Name $this.Name -Out $IconPath -Quiet -What | ConvertFrom-Json
            $IconDrawn = $true
            $Icon = @{ Text = $Drawn.Text; Top = $Drawn.Top; Bottom = $Drawn.Bottom; TextColor = $Drawn.TextColor }
        } catch {
            Remove-Item $IconPath -Force -ErrorAction SilentlyContinue
            $Warnings += "no icon ($($_.Exception.Message))"
        }

        # WSL writes one fragment per import - the guid changes on every
        # rebuild. The shared scan gives this name's guid and the full set of
        # live ones, for the ghost pruning below.
        $Fragments = Get-WslFragmentGuids -Name $this.Name

        # Every rebuild orphans the previous profile into the user's
        # settings.json: this instance's entries matching no live fragment go.
        if ($Fragments.Guids.Count -gt 0) {
            $Ghosts = Remove-TerminalGhostEntries -Name $this.Name -LiveGuids $Fragments.Guids
            foreach ($Path in $Ghosts.Unreadable) {
                $Warnings += "ghost entries NOT pruned in $Path (unreadable JSON - a // comment breaks ConvertFrom-Json; remove them by hand)"
            }
        }

        # Our own fragment files whose distro no longer exists go too.
        $null = Remove-StaleAppearanceFragments -LiveGuids $Fragments.Guids

        $Applied = $false
        if ($Fragments.Guid) {
            # No icon drawn, no icon line: Terminal shows its own. The look is
            # the instance's own, completed with the icon just drawn.
            $this.Look.IconPath = $(if ($IconDrawn) { $IconPath } else { "" })
            Set-InstanceFragment -Name $this.Name -Guid $Fragments.Guid -Theme $this.Look
            $Applied = $true
        } else {
            $Warnings += "no WSL fragment for '$($this.Name)' - the profile was not applied"
        }

        # What this instance looks like, in its own folder - the file an
        # archive carries. Written here, the fragment in place, so the font and
        # colours it reads are the ones just applied, icon recipe included.
        Set-InstanceLook -InstallPath $this.Path -Look (New-InstanceLook -Name $this.Name -Icon $Icon)

        # Asked to look again, so the new profile appears without closing
        # anything.
        Update-TerminalSettings

        return [PSCustomObject]@{ Applied = $Applied; Warnings = @($Warnings) }
    }

    # =========================================================================
    # INSTANCE METHODS: Packs Management
    # =========================================================================

    # Explicit, and the constructor does not run it: it asks the instance,
    # which boots it on the way - only the commands that need the packs pay.
    # A pack's folder is the one HOLDING pack.conf, and the path comes from the
    # home the instance names - a tilde only expands inside a shell.
    [void] RefreshPacks() {
        $this.InstalledPacks = @()
        # Not named $home: HOME is a PowerShell automatic variable, and the
        # assignment is refused - read-only.
        $InstanceHome = @(& wsl.exe -d $this.Name -- printenv HOME 2>$null |
            ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
        if (-not $InstanceHome) { return }

        $packsDirectory = "$($InstanceHome[0])/.config/packs"
        $found = & wsl.exe -d $this.Name -- find $packsDirectory -mindepth 2 -maxdepth 2 -name pack.conf 2>$null
        foreach ($conf in @($found)) {
            $clean = "$conf".Trim()
            if (-not $clean) { continue }
            $packName = (($clean -replace "/pack.conf$", "").Split("/") | Select-Object -Last 1)
            $this.InstalledPacks += $packName
        }
    }

    [bool] HasPack([string]$packName) {
        return ($this.InstalledPacks -contains $packName)
    }

    # The one order that works, mirrored from the real engine (packs.ps1):
    # newcomers' folders first (a remove.sh asking which installed pack claims
    # a package must see them), then what leaves, then the installs, then the
    # dependencies the removals left behind. Answers $null, or the pack that
    # stopped the run and its exit code - what that means is the caller's
    # sentence.
    #
    # TODO: port the moves from packs.ps1 - the copy into the instance (/mnt,
    # or \\wsl.localhost when the drives are unmounted), the scripts run from
    # inside the folder, the decline code (2: the folder goes back out, nothing
    # failed), the rollback of placed folders, and the cleanup_orphans.sh pass
    # when something left.
    #
    # The newcomers are the catalog's packs, requirements already resolved;
    # what leaves is named. Both lists are explicit, @() included: a class
    # method takes no default.
    [object] ApplyPacks([WslPack[]]$toAdd, [string[]]$toRemove) {
        return $null
    }

    # =========================================================================
    # STATIC METHODS: Factory, Restore & Queries
    # =========================================================================

    static [WslInstance] Build([string]$name, [string]$installPath, [string]$tarPath, [string]$user, [WslTheme]$look) {
        if (-not (Test-Path $installPath)) {
            New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        }

        Invoke-External { wsl.exe --import $name $installPath $tarPath --version 2 } "WSL import failed."

        # Ours from here on, whatever happens next - written before the steps
        # that can still fail, so a build that stops later leaves a real
        # instance behind, not an invisible one.
        New-InstanceMarker -Folder $installPath -By "build"

        $instance = [WslInstance]::new()
        $instance.Name        = $name
        $instance.Path        = $installPath
        $instance.DefaultUser = $user
        $instance.Look        = $look
        return $instance
    }

    # From an archive folder: the tar inside it is the one to import (the
    # newest *.tar*), and the marker lands right after - before the look,
    # which the caller re-applies from the instance.json beside the tar. A tar
    # does not carry the version it came from, and WSL 1 is not what this
    # repository builds: the import is version 2, like the build's.
    static [WslInstance] Restore([string]$archiveDir, [string]$name, [string]$installPath) {
        $tar = Get-ChildItem -Path $archiveDir -Filter "*.tar*" -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $tar) {
            throw "No tar in the archive folder: $archiveDir"
        }

        Invoke-External { wsl.exe --import $name $installPath $tar.FullName --version 2 } "The import failed."

        # Ours from here on, whatever happens next.
        New-InstanceMarker -Folder $installPath -By "restore"

        $instance = [WslInstance]::new()
        $instance.Name        = $name
        $instance.Path        = $installPath
        $instance.DefaultUser = "root"
        return $instance
    }

    static [void] Unregister([string]$name, [bool]$toArchive) {
        $instance = [WslInstance]::GetByName($name)
        if ($instance) {
            $instance.Unregister($toArchive)
        } else {
            # No metadata to archive from: unregister only.
            & wsl.exe --unregister $name
        }
    }

    static [WslInstance] GetByName([string]$name) {
        $all = [WslInstance]::GetAll()
        return ($all | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    }

    # Every registered instance: name, folder, WSL version (1 or 2). The empty
    # constructor on purpose - the four-argument one asks wsl.exe about the
    # state, and asking once per instance is not this call's business.
    static [WslInstance[]] GetAll() {
        $found = @()
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
        if (-not (Test-Path $regPath)) { return $found }

        foreach ($key in Get-ChildItem $regPath) {
            $props = Get-ItemProperty $key.PSPath
            if ($props.DistributionName) {
                $instance = [WslInstance]::new()
                $instance.Name = $props.DistributionName
                $instance.Path = ($props.BasePath -replace '^\\\\\?\\', '').TrimEnd('\')
                if ($props.Version) { $instance.Version = [int]$props.Version }
                $found += $instance
            }
        }
        return $found
    }
}
