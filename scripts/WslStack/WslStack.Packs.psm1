# ==============================================================================
# PACKS: WHAT THE CHECKOUT CARRIES, WHAT AN INSTANCE HAS, HOW ONE TRAVELS
# ==============================================================================
# A pack is a folder, installed when its folder is in ~/.config/packs, and its
# folder is the only thing that travels: add_pack copies it in and runs its
# install.sh there; remove_pack runs remove.sh, takes the folder back out, and
# the pack's leftovers on the system side are cleaned up after.
#
# Add, remove, and the bulk command share these moves - they are here once, for
# the same reason the instance helpers are in instance.ps1: a second copy is how
# the copies start. Nothing here sends a bash script as text through wsl.exe:
# only plain paths, one argument at a time.
# ==============================================================================

# The class this family names - the catalog below is a [WslPackCatalog] -
# pulled in by the file itself: `using` resolves it for every function here,
# whoever called in what shape (measured in the questions next door).
using module ..\WslModel\WslModel.psd1

# Where the packs live, and the cleanup that travels with a removal. Read here,
# at load time, and not inside the functions: $PSScriptRoot means the file being
# executed, and a function belongs to whichever script called it.
$PacksRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "packs"
$OrphanCleanupScript = Join-Path (Split-Path $PSScriptRoot -Parent) "cleanup_orphans.sh"

# The catalog of packs this checkout carries, read by the model: the line a
# menu shows, the folder to copy from, the declarations both checklists read -
# and the two resolutions. One list, so add_pack, the checklist and the run
# cannot disagree about what travels with what.
function Get-PackCatalog {
    param([string]$Root = $PacksRoot)
    return [WslPackCatalog]::new($Root)
}

# A pack is its folder WITH its pack.conf: that is what the gmake side counts
# (packs_list), and the two sides must answer the same thing. A copy that failed
# once left its empty folder behind and they disagreed; the folder is taken back
# now, and this definition makes older ones harmless too.
#
# Wrap the call in @(): PowerShell unrolls a one-element list into its element,
# and the caller then holds a string - where [0] is its first LETTER, not the
# pack. Cost of the other way: a menu that offers 'g'.
function Get-InstalledPacks {
    param([string]$DistroName, [string]$PacksDirectory)
    $Found = Get-InInstanceOutput -DistroName $DistroName -Command @("find", $PacksDirectory, "-mindepth", "2", "-maxdepth", "2", "-name", "pack.conf")
    return @($Found | ForEach-Object { ($_ -replace "/pack.conf$", "").Split("/")[-1] } | Sort-Object)
}

# Where a pack's folder is, once it is in the instance. One place, so that the
# three commands cannot disagree about where a pack lives.
function Get-PackFolder {
    param([string]$PacksDirectory, [string]$Name)
    return "$PacksDirectory/$Name"
}

# Does the pack carry that script? Asked before anything is promised: a pack
# installed before packs had a remove.sh is one whose folder can leave, but
# nothing of it will be undone on the system side.
function Test-PackScript {
    param([string]$DistroName, [string]$Target, [string]$Script, [ref]$ExitCode)

    Invoke-InInstance -DistroName $DistroName -Command @("test", "-f", "$Target/$Script") -ExitCode $ExitCode -Quiet
    return ($ExitCode.Value -eq 0)
}

# Copy a pack's folder into the instance - the whole of what "travelling"
# means. Two ways in, decided by asking the instance first:
#   - the usual one: the pack's Windows folder becomes the working directory
#     (`--cd` has WSL translate it through the mounted drives), and `.` is all
#     there is to name - no wslpath, which the instance does not carry;
#   - with the drives unmounted, `--cd` cannot be honoured and the first way
#     ends on "cannot copy a directory into itself": Windows' own share into
#     the running distro, \\wsl.localhost\<distro>, needs no drive.
#
# The test is the path's presence under /mnt, so the drive letter decides.
# Whichever way it travelled, the scripts are made executable: the Windows side
# has no Unix bit to carry.
function Copy-PackIntoInstance {
    param([string]$DistroName, [string]$PackPath, [string]$Target, [ref]$ExitCode)

    Invoke-InInstance -DistroName $DistroName -Command @("mkdir", "-p", $Target) -ExitCode $ExitCode -Quiet
    if ($ExitCode.Value -ne 0) { return $false }

    $ThroughTheDrives = "/mnt/" + $PackPath.Substring(0, 1).ToLower() + ($PackPath.Substring(2) -replace "\\", "/")
    Invoke-InInstance -DistroName $DistroName -Command @("test", "-d", $ThroughTheDrives) -ExitCode $ExitCode -Quiet

    $Copied = $false
    if ($ExitCode.Value -eq 0) {
        # | Out-Host for the reason written above Invoke-PackScript: this
        # function answers a value, and the copy must not speak through it.
        Invoke-InInstance -DistroName $DistroName -Command @("cp", "-r", ".", "$Target/") -WorkingDirectory $PackPath -ExitCode $ExitCode | Out-Host
        $Copied = ($ExitCode.Value -eq 0)
    } else {
        $Unc = "\\wsl.localhost\$DistroName" + ($Target -replace "/", "\")
        try {
            Copy-Item -Path (Join-Path $PackPath "*") -Destination $Unc -Recurse -Force -ErrorAction Stop
            $Copied = $true
            $ExitCode.Value = 0
        } catch {
            Write-Host "  * pack copy  : the drives are unmounted here, so the pack went through Windows' own share - and Windows refused: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour warning)
            $ExitCode.Value = 1
        }
    }

    if ($Copied) {
        # The globs travel single-quoted inside a `sh -c`: bare arguments are
        # at the mercy of how wsl.exe hands the command over, and one of the
        # ways globs them - where nothing matches, the shell stops, and the
        # pack arrives with every script unexecutable without a word.
        Invoke-InInstance -DistroName $DistroName -Command @("sh", "-c", "find '$Target' -name '*.sh' -exec chmod +x {} +") -ExitCode $ExitCode -Quiet
        # And it is checked rather than trusted: a script that cannot run is a
        # pack that fails on its first target, far from where it went wrong.
        $Still = @(Get-InInstanceOutput -DistroName $DistroName -Command @("sh", "-c", "find '$Target' -name '*.sh' ! -perm -u+x"))
        if ($Still.Count -gt 0) {
            Write-Host "  * pack copy  : some scripts arrived without their executable bit - one command fixes them:" -ForegroundColor (Get-MessageColour warning)
            Write-Host "                 find ~/.config/packs -name '*.sh' -exec chmod +x {} +" -ForegroundColor (Get-MessageColour hint)
        }
    } else {
        # A failed copy leaves nothing behind: the empty folder would make
        # add_pack call the pack present while the gmake side calls it absent.
        # The copy's own exit code is what the caller reports, so it is kept.
        $CopyCode = $ExitCode.Value
        Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode $ExitCode
        $ExitCode.Value = $CopyCode
    }
    return $Copied
}

# Run one of the pack's own scripts from inside its folder. Output streams to
# the HOST, and that word is the point: the callers write this function's result
# into a variable, and a captured function captures whatever its own calls print
# too - that is how a pack's install went SILENT, everything the script said
# going into the variable that held the answer. Out-Host writes to the screen
# and leaves the value where it was. (It may ask for a password - another
# reason the lines must reach the console.)
# -AsRoot, for the remove.sh scripts: through this tool sudo's question never
# crossed the pipe (its prompt carries no line of its own, and the capture only
# ever showed whole lines), so the call hung on a password nobody could type.
# A removal only takes things away, so the script runs as root, with the user's
# home in HOME so the files it names are still theirs.
function Invoke-PackScript {
    param([string]$DistroName, [string]$Target, [string]$Script, [ref]$ExitCode, [switch]$AsRoot)

    if ($AsRoot) {
        # Not named $home: the automatic is read-only, and the assignment throws.
        $UserHome = Get-InstanceHome -DistroName $DistroName
        Invoke-InInstance -DistroName $DistroName -Command @("env", "HOME=$UserHome", "bash", $Script) `
            -WorkingDirectory $Target -RunAs "root" -ExitCode $ExitCode | Out-Host
        return
    }

    Invoke-InInstance -DistroName $DistroName -Command @("bash", $Script) -WorkingDirectory $Target -ExitCode $ExitCode | Out-Host
}

# The passwordless door, opened for a run: WSL trusts its Windows side with
# root and no password (wsl -u root), and the pack scripts run as the
# instance's user - their files must be his. The engine opens that same door to
# sudo for the length of the installs and closes it after: sudo inside a pack
# asks nothing, and nothing of it remains once the run ends.
#
# Written through visudo's own check, never beside it: a broken rule in
# /etc/sudoers.d breaks sudo itself. -Quiet: the answer is this function's.
function Enable-PackSudo {
    param([string]$DistroName)

    $User = Split-Path -Leaf (Get-InstanceHome -DistroName $DistroName)
    if (-not $User) { return $false }
    $Command = "printf '%s`n' '$User ALL=(ALL) NOPASSWD: ALL' > /tmp/wsl-stack-pack-sudo" +
        " && chmod 0440 /tmp/wsl-stack-pack-sudo" +
        " && visudo -cf /tmp/wsl-stack-pack-sudo > /dev/null" +
        " && mv /tmp/wsl-stack-pack-sudo /etc/sudoers.d/90-wsl-stack-packs"

    $Code = 0
    Invoke-InInstance -DistroName $DistroName -Command @("bash", "-c", $Command) -RunAs "root" -ExitCode ([ref]$Code) -Quiet
    return ($Code -eq 0)
}

function Disable-PackSudo {
    param([string]$DistroName)

    $Code = 0
    Invoke-InInstance -DistroName $DistroName -Command @("rm", "-f", "/etc/sudoers.d/90-wsl-stack-packs") -RunAs "root" -ExitCode ([ref]$Code) -Quiet
}

# The folder, and with it the pack: the Makefile loads whatever folder is there,
# so a folder that stays is a pack that stays.
function Remove-PackFolder {
    param([string]$DistroName, [string]$Target, [ref]$ExitCode)
    Invoke-InInstance -DistroName $DistroName -Command @("rm", "-rf", $Target) -ExitCode $ExitCode -Quiet
}

# Folders this run placed but never installed - taken back out with the failure
# that stopped the run, because the folder is what the menu reads: one left
# behind passes for an installation that never happened. The folder alone,
# never remove.sh: nothing of the pack reached the system, so there is nothing
# to undo.
function Remove-PlacedFolders {
    param([string]$DistroName, [string]$PacksDirectory, [object[]]$Packs, [ref]$ExitCode)
    foreach ($Pack in $Packs) {
        if ($null -eq $Pack) { continue }
        $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Pack.Name
        Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode $ExitCode
    }
}

# What the pack left on the system side: what its remove.sh did not name - the
# DEPENDENCIES nobody owns. The script asks apt and ldd, and only then removes;
# it travels the way a pack does - a copy, then a plain path.
function Invoke-PackOrphanCleanup {
    param([string]$DistroName, [ref]$ExitCode)

    if (-not (Test-Path $OrphanCleanupScript)) {
        # Nothing to run: the caller says so rather than pretend it happened.
        return $false
    }

    $RemoteScript = "/tmp/cleanup_orphans.sh"
    $Sent = 0
    Invoke-InInstance -DistroName $DistroName -Command @("cp", "cleanup_orphans.sh", $RemoteScript) `
        -WorkingDirectory $PSScriptRoot -ExitCode ([ref]$Sent) -Quiet
    if ($Sent -ne 0) { return $false }

    Invoke-PackScript -DistroName $DistroName -Target "/tmp" -Script "cleanup_orphans.sh" -ExitCode $ExitCode -AsRoot
    $Cleaned = $ExitCode.Value

    $Gone = 0
    Invoke-InInstance -DistroName $DistroName -Command @("rm", "-f", $RemoteScript) -ExitCode ([ref]$Gone) -Quiet
    return ($Cleaned -eq 0)
}

# Do what the two lists say, in the one order that works: newcomers' folders
# first (a remove.sh asking which installed pack claims a package must see
# them), then what leaves, then the installs, then the dependencies the
# removals left behind.
#
# It prints as it goes, and hands back $null or the pack that stopped the run -
# what that means is the caller's sentence.
function Invoke-PackApply {
    param(
        [string]$DistroName,
        [string]$PacksDirectory,
        [object[]]$ToAdd = @(),
        [string[]]$ToRemove = @(),
        [string]$ResumeHint = "Run this again to finish."
    )

    $Code = 0

    # 1. Folders first, before anything leaves: the remove.sh scripts below ask
    # which packs are installed, and these count from here on. What was placed
    # and never installed is remembered: a failure takes those folders back out.
    Write-Host ""
    $Placed = @()
    foreach ($Pack in $ToAdd) {
        $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Pack.Name
        Write-Host "==> Placing '$($Pack.Name)'..." -ForegroundColor (Get-MessageColour info)
        if (-not (Copy-PackIntoInstance -DistroName $DistroName -PackPath $Pack.Path -Target $Target -ExitCode ([ref]$Code))) {
            $CopyCode = $Code
            Remove-PlacedFolders -DistroName $DistroName -PacksDirectory $PacksDirectory -Packs $Placed -ExitCode ([ref]$Code)
            Write-Host ""
            Write-Host "[FAIL] Could not copy '$($Pack.Name)' into '$DistroName' (exit code $CopyCode)." -ForegroundColor (Get-MessageColour error)
            Write-Host "       Nothing was installed or removed; the folders already placed were taken back out." -ForegroundColor (Get-MessageColour hint)
            Write-Host "       $ResumeHint" -ForegroundColor (Get-MessageColour hint)
            return [PSCustomObject]@{ Pack = $Pack.Name; ExitCode = $CopyCode }
        }
        $Placed += $Pack
    }

    # 2. What leaves. A pack without a remove.sh was installed before packs had
    # one: its folder leaves, nothing is undone, and that is said.
    foreach ($Name in $ToRemove) {
        $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Name
        Write-Host ""
        if (Test-PackScript -DistroName $DistroName -Target $Target -Script "remove.sh" -ExitCode ([ref]$Code)) {
            Write-Host "==> Removing '$Name'..." -ForegroundColor (Get-MessageColour info)
            Invoke-PackScript -DistroName $DistroName -Target $Target -Script "remove.sh" -ExitCode ([ref]$Code) -AsRoot
            if ($Code -ne 0) {
                $RemoveCode = $Code
                Remove-PlacedFolders -DistroName $DistroName -PacksDirectory $PacksDirectory -Packs $Placed -ExitCode ([ref]$Code)
                Write-Host ""
                Write-Host "[FAIL] '$Name' could not remove itself (exit code $RemoveCode)." -ForegroundColor (Get-MessageColour error)
                Write-Host "       It is still installed; the new packs had not run yet, and their folders were taken back out." -ForegroundColor (Get-MessageColour hint)
                Write-Host "       $ResumeHint" -ForegroundColor (Get-MessageColour hint)
                return [PSCustomObject]@{ Pack = $Name; ExitCode = $RemoveCode }
            }
        } else {
            Write-Host "==> '$Name' carries no remove.sh: only its files leave." -ForegroundColor (Get-MessageColour info)
            Write-Host "    Its tool stays on the system - take it out by hand if you want it gone." -ForegroundColor (Get-MessageColour hint)
        }

        Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Code)
        if ($Code -ne 0) {
            $FolderCode = $Code
            Remove-PlacedFolders -DistroName $DistroName -PacksDirectory $PacksDirectory -Packs $Placed -ExitCode ([ref]$Code)
            Write-Host ""
            Write-Host "[FAIL] The folder of '$Name' could not be deleted (exit code $FolderCode)." -ForegroundColor (Get-MessageColour error)
            Write-Host "       The instance is half way through; the new packs were taken back out - none had run." -ForegroundColor (Get-MessageColour warning)
            Write-Host "       $ResumeHint" -ForegroundColor (Get-MessageColour hint)
            return [PSCustomObject]@{ Pack = $Name; ExitCode = $FolderCode }
        }
    }

    # The installs run behind WSL's own door: passwordless sudo for
    # their length, nothing of it after - their files stay the user's.
    $sudoWindow = $false
    if ($ToAdd.Count -gt 0) { $sudoWindow = Enable-PackSudo -DistroName $DistroName }
    try {
        # 3. What arrives: the folders are already there, so this is their install.sh.
        for ($Index = 0; $Index -lt $ToAdd.Count; $Index++) {
            $Pack = $ToAdd[$Index]
            $Target = Get-PackFolder -PacksDirectory $PacksDirectory -Name $Pack.Name
            Write-Host ""
            Write-Host "==> Installing '$($Pack.Name)' in '$DistroName'..." -ForegroundColor (Get-MessageColour info)
            Invoke-PackScript -DistroName $DistroName -Target $Target -Script "install.sh" -ExitCode ([ref]$Code)

            # Exit code 2 is the pack's way of saying it asked a question and the
            # answer was no - the claude pack asks before adding a second copy of a
            # program that is already installed on Windows. Its folder goes back out,
            # because the folder is what the menu reads and a pack with no tool
            # behind it is a menu that lies; but nothing failed, and the run goes on:
            # the packs after it still arrive, and the callers have no failure to
            # report. The code is spelled out here rather than guessed from the
            # output, because a pack that failed must not be mistaken for one that
            # was declined, nor the other way round (docs/packs.md).
            if ($Code -eq 2) {
                $Declined = 0
                Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Declined)
                Write-Host "       Its files were removed: the pack is not installed." -ForegroundColor (Get-MessageColour hint)
                continue
            }

            # A half-installed pack is worse than none, exactly as in add_pack: the
            # folder is what the menu reads, so it goes back out, and what the
            # install had already written to the system stays.
            if ($Code -ne 0) {
                # Kept aside before the folder goes back out: Remove-PackFolder
                # answers through the same [ref], and the code this run reports has
                # to be the install's - a failed install that says 0 is a failure
                # the caller cannot see.
                $InstallCode = $Code
                Write-Host ""
                Write-Host "[FAIL] The installation of '$($Pack.Name)' did not complete (exit code $InstallCode)." -ForegroundColor (Get-MessageColour error)
                Remove-PackFolder -DistroName $DistroName -Target $Target -ExitCode ([ref]$Code)
                # The packs after it were placed but never ran: their folders go
                # back out too, or the menu reads them as installations that never
                # were. The queue is ordered, so the position says as much.
                Remove-PlacedFolders -DistroName $DistroName -PacksDirectory $PacksDirectory -Packs @($ToAdd | Select-Object -Skip ($Index + 1)) -ExitCode ([ref]$Code)
                Write-Host "       Its files were removed, and the folders of the packs that had not run yet." -ForegroundColor (Get-MessageColour hint)
                Write-Host "       The packs before it are installed." -ForegroundColor (Get-MessageColour hint)
                Write-Host "       $ResumeHint" -ForegroundColor (Get-MessageColour hint)
                return [PSCustomObject]@{ Pack = $Pack.Name; ExitCode = $InstallCode }
            }
        }

        # 4. The dependencies the removals left behind, taken back only where
        # nothing can still need them - silently: only an early stop is worth a
        # line. Nothing to ask when nothing left.
        if ($ToRemove.Count -gt 0) {
            $CleanupCode = 0
            if (-not (Invoke-PackOrphanCleanup -DistroName $DistroName -ExitCode ([ref]$CleanupCode))) {
                Write-Host ""
                Write-Host "[WARN] The cleanup stopped early (exit code $CleanupCode)." -ForegroundColor (Get-MessageColour warning)
                Write-Host "       The packs are in place; some dependencies may remain." -ForegroundColor (Get-MessageColour hint)
            }
        }
    } finally {
        if ($sudoWindow) { Disable-PackSudo -DistroName $DistroName }
    }

    return $null
}
