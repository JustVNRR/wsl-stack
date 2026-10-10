# ==============================================================================
# AN INSTANCE
# ==============================================================================
# One distribution: registered, or left as an archive. Its folder, its user,
# its WSL version, the look Windows Terminal gives it, the packs it carries -
# and the gestures: start, stop, restart, shell, shrink, archive, restore,
# duplicate, unregister.
# What this one names, declared here: a module resolves a type it pulled in
# itself, never a neighbour's.
using module .\WslState.psm1
using module .\WslTheme.psm1
using module .\WslRecipe.psm1
using module .\WslPack.psm1

class WslInstance {
    [string]$Name
    [string]$Path
    [string]$DefaultUser

    # The WSL version the instance runs as (1 or 2). A copy is imported with
    # the version of its source.
    [int]$Version = 2

    # Archive tracking: an archive is a folder under <root>\archives - the tar
    # inside, and the instance's own file beside it (instance.json - look and
    # recipe - with terminal-icon.png).
    [bool]$HasArchive = $false
    [string]$ArchivePath

    [WslState]$State = [WslState]::Unknown

    # The recipe it was made with - where the image came from, the onboarding
    # shell, the look, and how the making went. Born empty and Pending: the
    # build fills it, the profile step writes it out with the look
    # (instance.json), and an archive or a copy carries it along.
    [WslRecipe]$Recipe = [WslRecipe]::new()

    # The empty constructor only: an instance is built property by property,
    # never by a constructor that asks wsl.exe for the state - that question
    # belongs to the callers that actually need it (RefreshState).
    WslInstance() {}

    # The instance as a block of lines, its look and its packs included -
    # whose description is the theme's own. Whoever shows it decides where
    # and when; one Write-Host is enough. The packs are asked live: nothing
    # caches them, so the line cannot go stale - a read that fails says none.
    [string] ToString() {
        $LookLine = if ($this.Recipe.Look) { "$($this.Recipe.Look)" } else { "-" }
        $Packs = try { @($this.GetPacks()) } catch { @() }
        $PacksLine = if ($Packs.Count -eq 0) { "none" } else { $Packs -join ", " }
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

    # Opens the instance's Terminal profile in a window of its own - the look
    # the profile carries comes with it: icon, name, colours, font. The
    # profile is the one WSL registered under the instance's name, so the
    # name matches. A bare console (plain wsl.exe) opens a shell too, but
    # carries none of the look: it is the fallback, and the honest one when
    # there is no profile to ask for. Nothing is waited on either way - the
    # window outlives this call.
    #
    # No command line is offered with the profile: Windows Terminal re-splits
    # whatever follows `-p`, and a note passed there came out as a program
    # name (measured: 0x80070002). The profile opens bare.
    [void] OpenShell() {
        # The fragment WSL wrote for the instance, on disk: without it
        # `wt -p` resolves to nothing and Terminal opens its DEFAULT profile
        # instead - a Windows PowerShell, measured. The scan is quick and has
        # no retries (the retrying sibling is Get-WslProfileGuid, for the
        # build flows).
        $FragmentDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
        $HasProfile = $false
        if (Test-Path $FragmentDir) {
            foreach ($File in @(Get-ChildItem $FragmentDir -Filter *.json)) {
                try {
                    $Named = @((Get-Content $File.FullName -Raw | ConvertFrom-Json).profiles |
                        Where-Object { $_.name -eq $this.Name })
                    if ($Named.Count -gt 0) { $HasProfile = $true; break }
                } catch { }
            }
        }

        if ($HasProfile) {
            # The running Terminal re-reads its profiles when its settings are
            # touched - the touch this repository already uses to show a new
            # look without closing anything. A fragment that landed after the
            # last touch (a fresh import, a restore) would otherwise not
            # resolve yet; the pause lets the reload finish.
            try {
                Update-TerminalSettings
                Start-Sleep -Milliseconds 400
                $null = Start-Process wt.exe -ArgumentList ('-p "{0}"' -f $this.Name) -PassThru
                return
            } catch { }
        }

        # Same line as Shell(): the name goes in unquoted - wsl.exe parses
        # its own line and does not strip quotes - and the `~` rides inside
        # the string, where nothing expands it.
        $null = Start-Process wsl.exe -ArgumentList ('-d {0} --cd ~' -f $this.Name) -PassThru
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
    # of the recipe - look and Docker's answer - for the caller to re-apply
    # once the copy exists. The caller stops the source first - stopping is a
    # decision, and decisions belong to the commands. Returns the copy's
    # folder, that recipe and that answer.
    [PSCustomObject] Duplicate([string]$newName) {
        # What Windows shows now, captured before the export; the icon's
        # recipe rides along (KeepIconRecipe).
        $this.Recipe.Look = $this.KeepIconRecipe((Get-InstanceAppearance -Name $this.Name))
        $Docker = Get-DockerState -Name $this.Name

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
        return [PSCustomObject]@{ Path = $newPath; Recipe = $this.Recipe; Docker = $Docker }
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
        # noted it. Written into the archive's folder - the instance's own
        # file is not touched.
        $this.Recipe.Look = $this.KeepIconRecipe($Appearance)
        $Content = ConvertTo-InstanceFile -Name $this.Name -Recipe $this.Recipe -Docker (Get-DockerState -Name $this.Name)

        if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        Set-InstanceFile -InstallPath $folder -Content $Content

        $IconCopied = $false
        if ($Appearance.IconPath) {
            Copy-Item -Path $Appearance.IconPath -Destination (Join-Path $folder "terminal-icon.png") -Force
            $IconCopied = $true
        }

        return [PSCustomObject]@{
            Font        = $Appearance.FontName
            ColorScheme = $Appearance.ColorScheme
            IconCopied  = $IconCopied
            Docker      = $Content.Docker
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

    # Writes the instance's own file - its state of composition: the recipe,
    # the look inside, Docker's answer. The one place that knows the file's
    # shape.
    [void] Save() {
        if (-not $this.Recipe.Look) { $this.Recipe.Look = [WslTheme]::Default($this.Name) }
        Set-InstanceFile -InstallPath $this.Path -Content (ConvertTo-InstanceFile -Name $this.Name `
            -Recipe $this.Recipe -Docker (Get-DockerState -Name $this.Name))
    }

    # The icon's recipe carried from the instance's own look onto the one
    # Windows shows now - a font or colour change must not eat the tile; that
    # was a real defect once.
    hidden [WslTheme] KeepIconRecipe([WslTheme]$Now) {
        if ($this.Recipe.Look) {
            $Now.IconText      = $this.Recipe.Look.IconText
            $Now.IconTop       = $this.Recipe.Look.IconTop
            $Now.IconBottom    = $this.Recipe.Look.IconBottom
            $Now.IconTextColor = $this.Recipe.Look.IconTextColor
        }
        return $Now
    }

    # Makes the look live on the Windows side: the font it names (fetched when
    # missing, best effort), the icon drawn from the instance's own name, the
    # fragment Windows Terminal reads under the guid WSL gave the instance,
    # and the instance's own file - the one an archive carries. Everything
    # derives from the instance and the look; the caller does the talking.
    # Answers whether a profile could be applied at all, with the odd news
    # worth a line.
    [object] ApplyTerminalProfile() {
        if (-not $this.Recipe.Look) { $this.Recipe.Look = [WslTheme]::Default($this.Name) }

        $Warnings = @()

        # The font the look names: Windows must have it before the fragment
        # points at it.
        if ($this.Recipe.Look.FontMissing()) {
            # The repository's own copy when it has one - the download is the
            # fallback, not the road.
            $FontStatus = $this.Recipe.Look.EnsureFont((Get-BundledFont -FileName "MesloLGS NF Regular.ttf"))
            if ($FontStatus.State -ne "installed") {
                $Warnings += "the font '$($this.Recipe.Look.FontName)' would not install: $($FontStatus.Error)"
            }
        }

        # The icon is drawn from the instance's own name, letters and colours
        # both. It is decoration: a failure is said here, leaves no file, and
        # the fragment below drops the icon line.
        $IconPath = Join-Path $this.Path "terminal-icon.png"
        $IconDrawn = $false
        try {
            # -What: the letters and colours read back into the instance's file,
            # so a later change of one keeps the other. -Quiet: nothing said
            # about a drawing that worked. In a method, $PSScriptRoot is this
            # file's folder - under scripts\, where the icon script lives.
            $IconScript = Join-Path $PSScriptRoot "..\make-icon.ps1"
            $Drawn = & $IconScript -Name $this.Name -Out $IconPath -Quiet -What | ConvertFrom-Json
            $IconDrawn = $true
            $this.Recipe.Look.IconText      = $Drawn.Text
            $this.Recipe.Look.IconTop       = $Drawn.Top
            $this.Recipe.Look.IconBottom    = $Drawn.Bottom
            $this.Recipe.Look.IconTextColor = $Drawn.TextColor
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
            $this.Recipe.Look.IconPath = $(if ($IconDrawn) { $IconPath } else { "" })
            Set-InstanceFragment -Name $this.Name -Guid $Fragments.Guid -Theme $this.Recipe.Look
            $Applied = $true
        } else {
            $Warnings += "no WSL fragment for '$($this.Name)' - the profile was not applied"
        }

        # The file an archive carries, written here, the fragment in place, so
        # the font and colours it reads are the ones just applied, icon recipe
        # included. The recipe rides in it - the road, the path, the
        # onboarding - and the verdict on the making: Ok, or Warning when the
        # look had news.
        $this.Recipe.Status   = if ($Warnings.Count -gt 0) { [WslRecipeStatus]::Warning } else { [WslRecipeStatus]::Ok }
        $this.Recipe.Messages = @($Warnings)
        $this.Save()

        # Asked to look again, so the new profile appears without closing
        # anything.
        Update-TerminalSettings

        return [PSCustomObject]@{ Applied = $Applied; Warnings = @($Warnings) }
    }

    # The distro's place in Docker Desktop, taken: its name written among the
    # ones Docker Desktop knows, the app restarted so its docker client is
    # injected - it reads that list only when it starts - then the thing
    # itself asked, as the default user and never root, which would pass
    # whatever the answer is. What was asked is done or the birth fails: the
    # write and the restart go through unwrapped - registering was the
    # caller's word, not a fancy. What the client then does is the recipe's
    # verdict, like the look's - ready, or a warning and why: the injection
    # runs at Docker Desktop's own pace, and being slow is not being
    # impossible. The name is read out first, so the blocks below carry a
    # plain local.
    [void] RegisterDockerDesktop() {
        $DistroName = $this.Name
        try { Set-DockerState -Name $DistroName }
        catch { throw "Docker Desktop's settings could not take '$DistroName': $($_.Exception.Message)" }
        if (-not (Test-NativeCommand { docker desktop restart })) {
            throw "Docker Desktop would not restart to pick '$DistroName' up."
        }

        $DockerUsable = $false
        for ($Attempt = 1; $Attempt -le 5 -and -not $DockerUsable; $Attempt++) {
            $DockerUsable = Test-NativeCommand { wsl.exe -d $DistroName -- docker version }
            if (-not $DockerUsable) { Start-Sleep -Seconds 2 }
        }
        if ($DockerUsable) {
            $this.Recipe.Messages = @($this.Recipe.Messages) + "Docker Desktop: ready - 'docker' works in this instance."
        } else {
            $this.Recipe.Status = [WslRecipeStatus]::Warning
            $this.Recipe.Messages = @($this.Recipe.Messages) + @(
                "Docker Desktop: 'docker' does not answer in this instance yet.",
                "run 'docker version' in there; if it names the socket's permissions, restart Docker Desktop and open a new terminal."
            )
        }
        try { $this.Save() } catch { }
    }

    # The four gestures of the look: what the theme's children change, one at a
    # time. ApplyTerminalProfile above walks the same road (the profile's guid,
    # the fragment, then the look - the icon recipe kept through: a font or
    # colour change must not eat the tile; that was a real defect once); the
    # two should share that walk one day instead of walking it twice.

    [void] SetFont([string]$FontName) {
        $Guid = Get-WslProfileGuid -Name $this.Name
        if (-not $Guid) {
            throw "Windows Terminal has no profile for '$($this.Name)' - the font cannot be applied."
        }
        $Theme = $this.KeepIconRecipe((Get-InstanceAppearance -Name $this.Name))
        $Theme.FontName = $FontName
        Set-InstanceFragment -Name $this.Name -Guid $Guid -Theme $Theme
        $this.Recipe.Look = $Theme
        $this.Save()
    }

    [void] SetColourScheme([string]$SchemeName) {
        $Guid = Get-WslProfileGuid -Name $this.Name
        if (-not $Guid) {
            throw "Windows Terminal has no profile for '$($this.Name)' - the colours cannot be applied."
        }
        $Theme = $this.KeepIconRecipe((Get-InstanceAppearance -Name $this.Name))
        $Theme.ColorScheme = $SchemeName
        Set-InstanceFragment -Name $this.Name -Guid $Guid -Theme $Theme
        $this.Recipe.Look = $Theme
        $this.Save()
    }

    # The recipe is drawn to the instance's own icon file
    # (terminal-icon.png, next to its disk), then worn. $PSScriptRoot in a
    # class method is the class file's folder - scripts\WslModel - so the
    # drawing script is two levels up, in assets. The drawn recipe comes
    # back whole: the drawing settles the parts the recipe left open.
    [object] SetIcon([object]$Drawing) {
        $IconPath = Join-Path $this.Path "terminal-icon.png"
        # Key by key, not a table merge: "Name" travels in the drawing too, and
        # a hashtable += over a key already there throws - a plain drawing must
        # not die on that.
        $Draw = @{ Name = $this.Name }
        if ($Drawing) {
            foreach ($Key in @($Drawing.Keys)) {
                if ("$Key" -ne "Name") { $Draw[$Key] = $Drawing[$Key] }
            }
        }
        $Drawn = & (Join-Path $PSScriptRoot "..\make-icon.ps1") @Draw -Out $IconPath -Quiet -What | ConvertFrom-Json

        # The drawn recipe replaces the old one whole - the look around it is
        # what Windows shows now.
        $this.Recipe.Look = Get-InstanceAppearance -Name $this.Name
        $this.Recipe.Look.IconText      = $Drawn.Text
        $this.Recipe.Look.IconTop       = $Drawn.Top
        $this.Recipe.Look.IconBottom    = $Drawn.Bottom
        $this.Recipe.Look.IconTextColor = $Drawn.TextColor
        $this.Save()

        return @{
            Text      = $Drawn.Text
            Top       = $Drawn.Top
            Bottom    = $Drawn.Bottom
            TextColor = $Drawn.TextColor
        }
    }

    # A file replaces the picture; the drawing behind it (the recipe) stays,
    # and comes back if the drawing is chosen again.
    [void] SetIconImage([string]$Source) {
        Copy-Item -LiteralPath $Source -Destination (Join-Path $this.Path "terminal-icon.png") -Force
    }

    # =========================================================================
    # INSTANCE METHODS: Packs Management
    # =========================================================================

    # The user's home, asked live - the anchor of every path that goes in. An
    # instance that cannot name it says so here, at the moment it matters;
    # nobody checks it beforehand.
    [string] Home() {
        $InstanceHome = Get-InstanceHome -DistroName $this.Name
        if (-not $InstanceHome) { throw "'$($this.Name)' did not say where its user's home is." }
        return $InstanceHome
    }

    # Where its packs live, once: every gesture that touches them anchors
    # here - the home, then the one folder.
    [string] PacksDirectory() {
        return "$($this.Home())/.config/packs"
    }

    # What the instance carries, asked live: a pack's folder is the one
    # HOLDING pack.conf, and the path comes from the home the instance names -
    # a tilde only expands inside a shell. Answers live; nothing caches it -
    # the manager's reads and the description both come through here.
    [string[]] GetPacks() {
        $PacksDirectory = $this.PacksDirectory()
        return @(Get-InstalledPacks -DistroName $this.Name -PacksDirectory $PacksDirectory)
    }

    # The packs, one pack at a time. AddPack brings one in - its folder
    # placed, its root half as root, its install behind WSL's own
    # passwordless door - and RemovePack takes one out - its remove.sh, its
    # folder. Neither speaks: the sentences belong to the caller. Each
    # answers $null, or where it stopped - the pack, its exit code, the step
    # ("copy", "root", "install", "remove", "folder"). A pack that declines
    # (exit code 2) is not a failure: its folder goes back out, and the null
    # says so.
    [object] AddPack([WslPack]$pack) {
        $DistroName = $this.Name
        $PacksDirectory = $this.PacksDirectory()
        $ErrorLog = if ($this.Path) { Join-Path $this.Path "pack-errors.log" } else { "" }
        $Code = 0

        # The folder first: a remove.sh running later in the same gesture
        # asks which installed pack claims a package, and this one must be
        # among them.
        $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $pack.Name
        if (-not (Copy-PackIntoInstance -DistroName $DistroName -PackPath $pack.Path -Target $Target -ExitCode ([ref]$Code))) {
            return [PSCustomObject]@{ Pack = $pack.Name; ExitCode = $Code; Step = "copy" }
        }

        # The root half, as WSL's own root, before the door opens: the shell
        # pack carries sudo itself, and on a bare Debian its install_root.sh
        # must run where no door can open yet.
        if (Test-PackScript -DistroName $DistroName -Target $Target -Script "install_root.sh" -ExitCode ([ref]$Code)) {
            Invoke-PackScript -DistroName $DistroName -Target $Target -Script "install_root.sh" -ExitCode ([ref]$Code) -AsRoot -ErrorLog $ErrorLog
            if ($Code -ne 0) {
                # Nothing of this pack has run its install yet: its folder
                # goes back out. What its root part put in place stays -
                # running it again picks up there.
                $RootCode = $Code
                Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Code)
                return [PSCustomObject]@{ Pack = $pack.Name; ExitCode = $RootCode; Step = "root" }
            }
        }

        # The install, behind WSL's own door: passwordless sudo for its
        # length, nothing of it after - the files stay the user's.
        $sudoWindow = $false
        try {
            $sudoWindow = Enable-PackSudo -DistroName $DistroName
            Invoke-PackScript -DistroName $DistroName -Target $Target -Script "install.sh" -ExitCode ([ref]$Code) -ErrorLog $ErrorLog
        } finally {
            if ($sudoWindow) { Disable-PackSudo -DistroName $DistroName }
        }

        # Exit code 2 is the pack's way of saying it asked a question and the
        # answer was no - the oh_my_code pack asks before adding a second copy
        # of a program already installed on Windows. Its folder goes back out
        # - the folder is what the menu reads, and a pack with no tool behind
        # it is a menu that lies - but nothing failed. Spelled out here rather
        # than guessed from the output, so a failure and a decline are never
        # taken one for the other (docs/packs.md).
        if ($Code -eq 2) {
            $Declined = 0
            Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Declined)
            return $null
        }

        # A half-installed pack is worse than none: its folder goes back out,
        # and what its install had already written to the system stays.
        if ($Code -ne 0) {
            $InstallCode = $Code
            Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Code)
            return [PSCustomObject]@{ Pack = $pack.Name; ExitCode = $InstallCode; Step = "install" }
        }

        return $null
    }

    # One pack out: its remove.sh - as root, the removals' own gesture - then
    # its folder. A pack without a remove.sh was installed before packs had
    # one: its folder leaves, nothing is undone, and no line says it.
    [object] RemovePack([string]$name) {
        $DistroName = $this.Name
        $PacksDirectory = $this.PacksDirectory()
        $ErrorLog = if ($this.Path) { Join-Path $this.Path "pack-errors.log" } else { "" }
        $Code = 0

        $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $name
        if (Test-PackScript -DistroName $DistroName -Target $Target -Script "remove.sh" -ExitCode ([ref]$Code)) {
            Invoke-PackScript -DistroName $DistroName -Target $Target -Script "remove.sh" -ExitCode ([ref]$Code) -AsRoot -ErrorLog $ErrorLog
            if ($Code -ne 0) {
                return [PSCustomObject]@{ Pack = $name; ExitCode = $Code; Step = "remove" }
            }
        }

        Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Code)
        if ($Code -ne 0) {
            return [PSCustomObject]@{ Pack = $name; ExitCode = $Code; Step = "folder" }
        }
        return $null
    }

    # The whole gesture, in the engine's one working order: the newcomers
    # first - a remove.sh asks which installed pack claims a package and must
    # see them - then what leaves, then the dependencies the removals left
    # behind. The first failure stops the run; the packs already done stay.
    [object] ApplyPacks([WslPack[]]$toAdd, [string[]]$toRemove) {
        # The run's errors, kept aside: the scripts' error channel lands in
        # one file beside the instance, reset at the start of every run - the
        # build opens it when something failed.
        $ErrorLog = if ($this.Path) { Join-Path $this.Path "pack-errors.log" } else { "" }
        if ($ErrorLog) { Remove-Item -Path $ErrorLog -Force -ErrorAction SilentlyContinue }

        foreach ($Pack in $toAdd) {
            $Failure = $this.AddPack($Pack)
            if ($null -ne $Failure) { return $Failure }
        }
        foreach ($Name in $toRemove) {
            $Failure = $this.RemovePack($Name)
            if ($null -ne $Failure) { return $Failure }
        }

        # The dependencies the removals left behind, taken back only where
        # nothing can still need them. An early stop is not a failure: the
        # packs are in place, and the news of it is the caller's to say.
        if ($toRemove.Count -gt 0) {
            $CleanupCode = 0
            $null = Invoke-PackOrphanCleanup -DistroName $this.Name -ExitCode ([ref]$CleanupCode)
        }
        return $null
    }

    # =========================================================================
    # STATIC METHODS: Factory, Restore & Queries
    # =========================================================================

    # The birth, from the recipe to a complete instance: the image is made
    # (the recipe's own move), exported as a rootfs tar, imported, the
    # recipe's onboarding placed and run, the look applied, and the working
    # image kept or taken back, the recipe's word.
    # The old instance of the same name, if there was one, is already gone:
    # destroying it was the calling command's act - confirmation and last
    # look included - and the name is free by the time this runs. The image
    # still comes first: every step after it writes, and a Docker that fails
    # leaves nothing of this birth behind. The look is tried, never owed: an
    # instance born with a plain shell is better than none, and what could
    # not be applied is said in the status and the messages - never in a
    # thrown birth.
    static [WslInstance] Build([string]$name, [string]$installPath, [WslRecipe]$recipe, [string]$user) {
        $Tag = [WslRecipe]::TagFor($name)
        # The name the image is worked under from here: the recipe's own
        # build tag, or the name - or bare id - its tar carried.
        $ImageRef = $recipe.MakeImage($name)

        try {
            $tarPath = Join-Path (Split-Path $installPath -Parent) "$name-rootfs.tar"
            Export-DockerRootfs -Image $ImageRef -OutputPath $tarPath

            if (-not (Test-Path $installPath)) {
                New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            }

            Invoke-External { wsl.exe --import $name $installPath $tarPath --version 2 } "WSL import failed."
        } catch {
            # A birth that did not register leaves no folder behind: the
            # machine is found again the way this run found it.
            Remove-Item -Recurse -Force $installPath -ErrorAction SilentlyContinue
            throw
        } finally {
            Remove-Item $tarPath -Force -ErrorAction SilentlyContinue
        }

        # Ours from here on, whatever happens next - written before the look,
        # which can still fail, so a build that stops later leaves a real
        # instance behind, not an invisible one.
        New-InstanceMarker -Folder $installPath -By "build"

        $instance = [WslInstance]::new()
        $instance.Name        = $name
        $instance.Path        = $installPath
        $instance.DefaultUser = $user
        $instance.Recipe      = $recipe

        # The recipe's onboarding, when it names one: placed, run as root
        # with the account name as its argument, and the distro stopped so
        # the next boot reads the account it made. What the script makes of
        # the name is its own business.
        if ($recipe.FirstBoot) {
            Install-FirstBootScript -DistroName $name -Source $recipe.FirstBoot
            Invoke-WslFirstBoot -DistroName $name -User $user
            Invoke-NativeCommand { wsl.exe --terminate $name } "Could not stop '$name'." -SuppressOutput
        } else {
            # An image used as it is keeps its own account: who opens the
            # instance is what its /etc/wsl.conf says - asked of the
            # instance, WSL opening root when it names nobody.
            $ImageDefaultUser = ""
            foreach ($Line in @(Get-InInstanceOutput -DistroName $name -Command @("cat", "/etc/wsl.conf"))) {
                if ("$Line" -match '^\s*default\s*=\s*(\S+)\s*$') { $ImageDefaultUser = $Matches[1]; break }
            }
            $instance.DefaultUser = if ($ImageDefaultUser) { $ImageDefaultUser } else { "root" }
        }

        try {
            $null = $instance.ApplyTerminalProfile()
        } catch {
            $instance.Recipe.Status = [WslRecipeStatus]::Warning
            $instance.Recipe.Messages = @($instance.Recipe.Messages) + "the look failed: $($_.Exception.Message)"
            try { $instance.Save() } catch { }
        }

        # The working image, the recipe's word: a Dockerfile build's image is
        # saved as a tar beside the other images when the caller asked to
        # keep it - the image road loads it back in seconds, no rebuild -
        # and its working tag goes back either way: nothing needs it any
        # more. Best effort throughout - a birth never fails on its own
        # leavings, a failed save is said in the recipe.
        if ($recipe.BuildType -eq [WslBuildType]::Dockerfile) {
            if ($recipe.KeepImage) {
                $SavePath = Join-Path $recipe.Context "assets\dockerimages\$name\$name.tar"
                if (-not (Save-DockerImage -Tag $Tag -OutputPath $SavePath)) {
                    $instance.Recipe.Status = [WslRecipeStatus]::Warning
                    $instance.Recipe.Messages = @($instance.Recipe.Messages) + "the image could not be saved to '$SavePath'."
                    try { $instance.Save() } catch { }
                }
            }
            $null = Remove-DockerImage -Tag $Tag
        }

        # The recipe's word on Docker Desktop, the birth's last act - after
        # the image's taking-back above, which a restart mid-way would break.
        # The instance's own method does the whole of it; the verdict rides
        # on the recipe like the look's, and saves itself there.
        if ($recipe.RegisterDocker) {
            $instance.RegisterDockerDesktop()
        }

        # The recipe's packs, the birth's last step: the instance installs
        # what was chosen - its own act, the one the commands use too. Best
        # effort, like the look: a failure is a note on the recipe, never a
        # failed birth - the instance is born, registered and usable.
        if ($recipe.Packs.Count -gt 0) {
            try {
                $PacksFailure = $instance.ApplyPacks($recipe.Packs, @())
                if ($null -ne $PacksFailure) {
                    $Now = @($instance.GetPacks())
                    $Skipped = @($recipe.Packs | Where-Object { $_.Name -ne $PacksFailure.Pack -and $Now -notcontains $_.Name } | ForEach-Object { $_.Name })
                    $instance.Recipe.Status = [WslRecipeStatus]::Warning
                    $instance.Recipe.Messages = @($instance.Recipe.Messages) + "'$($PacksFailure.Pack)' installation failed."
                    if ($Skipped.Count -gt 0) {
                        $instance.Recipe.Messages = @($instance.Recipe.Messages) + "$($Skipped -join ', ') installation skipped."
                    }
                    try { $instance.Save() } catch { }
                }
            } catch {
                $instance.Recipe.Status = [WslRecipeStatus]::Warning
                $instance.Recipe.Messages = @($instance.Recipe.Messages) + "not installed - $($_.Exception.Message)"
                try { $instance.Save() } catch { }
            }
        }
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

    # Every registered instance: name, folder, WSL version (1 or 2), and its
    # recipe - off its own file, born empty (Pending) when there is none: an
    # instance always carries its state. The empty constructor on purpose -
    # the four-argument one asks wsl.exe about the state, and asking once per
    # instance is not this call's business.
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
                $instance.Recipe = Get-InstanceRecipe -Name $instance.Name
                $found += $instance
            }
        }
        return $found
    }
}
