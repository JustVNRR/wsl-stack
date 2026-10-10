# ==============================================================================
# PROMPTS: THE QUESTIONS A COMMAND ASKS
# ==============================================================================
# The build walks all of them - the instance's full name, the packs it will
# carry, the user it opens as - and manage_packs asks the same packs question
# about the instance it has in front of it. Each one asks and answers, and
# nothing else: where the answer goes and how it is shown stay with the
# command that asked. The yes/no confirmations and the deletions' gate come
# from here too, so no command writes one twice.
# ==============================================================================

# The classes the questions name - [WslState], [WslInstanceManager],
# [WslPackCatalog] - pulled in by the file itself: `using` resolves them for
# every function and filter here, whoever called in what shape (measured: a
# .\wsl.ps1 run used to filter restart's list against an unknown type, every
# instance falling through silently, while a -File run resolved).
using module ..\WslModel\WslModel.psd1

# The recipes are DATA, like the packs: the build's lists read the assets -
# assets\dockerfiles and assets\onboardings - seeded once from the
# repository's own src\distro\build when a folder is missing. The seed slots
# carry the source files' plain names (Dockerfile, onboarding), hash-less:
# they sort ahead of the same-named uploads, so a fresh checkout opens on
# them. Deleting a recipe is for good; deleting the folder brings the pair
# back.
$RecipesRepoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$SeedRecipes = @(
    @{ Kind = "dockerfiles"; Source = "src\distro\build\Dockerfile"; FileName = "Dockerfile"; Slot = "Dockerfile"; Sibling = "Dockerfile.dockerignore" }
    @{ Kind = "onboardings"; Source = "src\distro\build\onboarding.sh"; FileName = "onboarding.sh"; Slot = "onboarding"; Sibling = "" }
)
foreach ($Seed in $SeedRecipes) {
    $SeedRoot = Join-Path $RecipesRepoRoot "assets\$($Seed.Kind)"
    if (Test-Path $SeedRoot) { continue }
    $SeedSource = Join-Path $RecipesRepoRoot $Seed.Source
    if (-not (Test-Path $SeedSource)) { continue }
    $SeedSlot = Join-Path $SeedRoot $Seed.Slot
    $null = New-Item -ItemType Directory -Path $SeedSlot -Force
    Copy-Item -LiteralPath $SeedSource -Destination (Join-Path $SeedSlot $Seed.FileName) -Force
    # The Dockerfile's ignore file rides along, under the very name a builder
    # reads beside a `-f` Dockerfile.
    if ($Seed.Sibling) {
        $SeedBeside = Join-Path (Split-Path $SeedSource -Parent) $Seed.Sibling
        if (Test-Path $SeedBeside) { Copy-Item -LiteralPath $SeedBeside -Destination (Join-Path $SeedSlot $Seed.Sibling) -Force }
    }
}

# ---------------------------------------------------------------------------
# THE PIECES EVERY QUESTION SHARES
# ---------------------------------------------------------------------------

# The ending every cancelled question shares: a blank line, the word that says
# what was NOT touched - "created" or "run" when the command was making
# something, "modified" otherwise - and the run stops here.
function Stop-Cancelled {
    param([string]$What = "modified")

    Write-Host ""
    Write-Host "[ABORT] Operation cancelled by user. Nothing was $What." -ForegroundColor (Get-MessageColour success)
    exit 0
}

# Is this the shape an instance takes a name in? Letters, digits, '.', '_' and
# '-', starting with a letter or a digit - the rule the name questions and
# their checks apply, written once.
function Test-InstanceName {
    param([string]$Name)

    return ($Name -match '^[A-Za-z0-9][A-Za-z0-9_.-]*$')
}

# One yes/no question, the shape every one of them shows: [Y/n] when the
# answer is yes unless told otherwise, [y/N] when it is no. Answers as a
# boolean; what the answer means - cancelling, or going on without - stays
# with the caller.
function Confirm-YesNo {
    param([string]$Question, [switch]$DefaultNo)

    $Shown = if ($DefaultNo) { "$Question [y/N]" } else { "$Question [Y/n]" }
    $Answer = [string](Read-Host $Shown)
    if ($DefaultNo) { return ($Answer -match "^[yY]") }
    return ($Answer -notmatch "^[nN]")
}

# The gate every deletion goes through: the banner, the sentence that says
# which deletion this is, the exact name typed back. The folder line shows
# when the caller can name the folder it is about to erase. Answers whether
# the name was typed back; what a no means stays with the caller.
function Confirm-Destruction {
    param(
        [string]$DistroName,
        [string]$Lead,
        [string]$InstallPath = ""
    )

    [Console]::Beep(1000, 400)
    Write-Host ""
    Write-DangerBanner
    Write-Host ""
    Write-Host "  $Lead" -ForegroundColor (Get-MessageColour error)
    Write-Host ""
    Write-Host "  Proceeding will PERMANENTLY DESTROY this distribution:" -ForegroundColor (Get-MessageColour warning)
    Write-Host "    - Executing: wsl --unregister $DistroName" -ForegroundColor (Get-MessageColour muted)
    if ($InstallPath) {
        Write-Host "    - Erasing the install folder: $InstallPath" -ForegroundColor (Get-MessageColour muted)
    }
    Write-Host "    - IRREVERSIBLE DELETION of the virtual disk (VHDX)" -ForegroundColor (Get-MessageColour muted)
    Write-Host "    - TOTAL LOSS of projects, SSH keys, and all files in /home" -ForegroundColor (Get-MessageColour muted)
    Write-Host ""
    Write-Host "  THIS OPERATION CANNOT BE UNDONE." -ForegroundColor (Get-MessageColour error)
    Write-Host ""
    Write-Host " ----------------------------------------------------------------------" -ForegroundColor (Get-MessageColour muted)
    Write-Host " Press ENTER to abort immediately." -ForegroundColor (Get-MessageColour hint)
    Write-Host " To confirm DESTRUCTION, type the exact name of the distribution:" -ForegroundColor (Get-MessageColour hint)
    $Confirmation = Read-Host " Confirm"
    Write-Host " ----------------------------------------------------------------------" -ForegroundColor (Get-MessageColour muted)
    Write-Host ""

    # -ceq, not -eq: PowerShell's -eq ignores case, while the banner above
    # asks for the exact name. The point is that the name is read and typed,
    # not that a reflexive Enter carries through.
    return ($Confirmation -ceq $DistroName)
}

# ---------------------------------------------------------------------------
# READING AN ANSWER
# ---------------------------------------------------------------------------

# One answer typed by the user, its empty answer a cancel like any other: the
# question is written here and Read-Host asked bare, because what Read-Host
# writes itself never reaches a pipe.
function Read-Answer {
    param([string]$Question, [string]$What = "modified")

    Write-Host -NoNewline "${Question}: "
    $Answer = [string](Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($Answer)) { Stop-Cancelled -What $What }
    return $Answer
}

# One instance name, asked until it is one: the shape checked, the refusal
# hint shown, and the empty answer cancelling - the -What word says what was
# not touched, "modified" unless the caller creates something.
function Read-InstanceName {
    param([string]$Question, [string]$What = "modified")

    while ($true) {
        $Answer = [string](Read-Host $Question)
        if ([string]::IsNullOrWhiteSpace($Answer)) { Stop-Cancelled -What $What }
        $Answer = $Answer.Trim()
        if (Test-InstanceName $Answer) { return $Answer }
        Write-Host "  Letters, digits, '.', '_' and '-' only." -ForegroundColor (Get-MessageColour hint)
    }
}

# The folder question, whole: the proposal, the three refusals, the folder
# asked again, and the two checks the erasing depends on. An empty answer
# cancels the run, like the question it replaces.
function Resolve-InstallPath {
    param([string]$DistroName, [string]$Root, [object[]]$Registered)

    $Folder = $Root
    $InstallPath = $null
    while (-not $InstallPath) {
        # A path Windows refuses is a typo, not a reason to stop. The refused
        # characters are spelled out: .NET Framework - 5.1 - threw on them from
        # inside GetFullPath, .NET Core - 7 - walks past them.
        $Full = $null
        $Refused = ($Folder.IndexOfAny([char[]]'"<>|') -ge 0) -or ($Folder -match '[\x00-\x1f]')
        if (-not $Refused) {
            try {
                $Full = [System.IO.Path]::GetFullPath((Join-Path $Folder $DistroName)).TrimEnd('\')
            } catch { }
        }

        # Step 4 erases this path recursively: a folder holding another instance
        # would take that instance with it.
        $Elsewhere = $null
        if ($Full) {
            $Elsewhere = $Registered | Where-Object {
                $_.Name -ne $DistroName -and
                ($_.Path -eq $Full -or $_.Path.StartsWith("$Full\", [System.StringComparison]::OrdinalIgnoreCase))
            } | Select-Object -First 1
        }

        # The folder belongs to a name that was just proven free: an existing
        # one is occupied by definition - nothing here is ours to erase any
        # more, builds never take an instance over.
        $Occupied = $false
        if ($Full -and (Test-Path $Full)) {
            $Occupied = @(Get-ChildItem -Path $Full -Force -ErrorAction SilentlyContinue).Count -gt 0
        }

        if (-not $Full) {
            Write-Host "  '$Folder' is not a usable path." -ForegroundColor (Get-MessageColour warning)
        } elseif ($Elsewhere) {
            Write-Host "  $Full is, or holds, the folder of '$($Elsewhere.Name)'." -ForegroundColor (Get-MessageColour warning)
            Write-Host "  Erasing it would take that instance with it." -ForegroundColor (Get-MessageColour warning)
        } elseif ($Occupied) {
            Write-Host "  $Full already exists, please choose another location." -ForegroundColor (Get-MessageColour warning)
        } else {
            # Shown before it is created; a no is a change of mind about the
            # location - nothing has been written yet.
            $Answer = [string](Read-Host "Create [$Full]? [Y/n]")
            if ($Answer -notmatch "^[nN]") {
                $InstallPath = $Full
                continue
            }
        }

        # Another folder, asked the same way; an empty answer cancels.
        $Answer = [string](Read-Host "Folder for '$DistroName' (or Enter to cancel)")
        if ([string]::IsNullOrWhiteSpace($Answer)) {
            Write-Host ""
            Write-Host "[ABORT] Operation cancelled by user." -ForegroundColor (Get-MessageColour warning)
            exit 0
        }
        $Folder = $Answer.Trim()
    }
    return $InstallPath
}

# The instance's full name, resolved: which instance it is, and where it will
# live. One question after the other, all of it before the machine starts. An
# empty answer anywhere cancels the run with nothing modified. A name Windows
# already carries is refused on the spot - an instance is never built over,
# the window's road refusing the same way - and the strict list read also
# answers "is this path another instance's folder" below.
function Resolve-InstanceIdentity {
    param([string]$Root)

    $DistroName = Read-InstanceName "Name of the instance (CTRL+C to abort)"

    # What Windows already knows, read once and read strictly: this one list
    # answers "is this name taken" right now, and "is this path another
    # instance's folder" below. A list that cannot be read stops the run
    # rather than passing for an empty one.
    try {
        $Registered = @(Get-RegisteredDistros)
    } catch {
        Write-Host ""
        Write-Host "[ABORT] The list of registered WSL distributions cannot be read." -ForegroundColor (Get-MessageColour error)
        Write-Host "        See what 'wsl --list --verbose' says, then run this script again." -ForegroundColor (Get-MessageColour hint)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }
    if (@($Registered | Where-Object { $_.Name -eq $DistroName }).Count -gt 0) {
        Write-Host ""
        Write-Host "[ABORT] '$DistroName' is already registered." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Remove it first:  .\wsl.ps1 unregister" -ForegroundColor (Get-MessageColour hint)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }

    $InstallPath = Resolve-InstallPath -DistroName $DistroName -Root $Root -Registered $Registered
    return [PSCustomObject]@{ Name = $DistroName; InstallPath = $InstallPath }
}

# ---------------------------------------------------------------------------
# ASKING WHICH INSTANCE A LIFECYCLE COMMAND ACTS ON
# ---------------------------------------------------------------------------
# The filter, the label every list in the family shows, and the two lines a
# machine with none of them gets - stop, restart and start asked this by
# writing it three times. An empty answer, and a machine with nothing to act
# on, walks out of the command with nothing touched, like every question here.
function Select-EligibleInstance {
    param(
        [WslInstanceManager]$Manager,
        [ValidateSet("Running", "Stopped")][string]$State,
        [string]$Title,
        [string]$None,
        [string]$Nothing
    )

    $All = @($Manager.OursHere())
    if ($All.Count -eq 0) {
        Write-Host ""
        Write-Host "[ABORT] No instance of this template is registered on this machine." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Build one with  .\wsl.ps1 build" -ForegroundColor (Get-MessageColour hint)
        exit 1
    }

    $Eligible = if ($State -eq "Running") {
        @($All | Where-Object { $_.State -eq [WslState]::Running })
    } else {
        @($All | Where-Object { $_.State -ne [WslState]::Running })
    }
    if ($Eligible.Count -eq 0) {
        Write-Host ""
        Write-Host "[ABORT] $None" -ForegroundColor (Get-MessageColour error)
        Write-Host "        $Nothing" -ForegroundColor (Get-MessageColour hint)
        exit 1
    }

    $Picked = Select-FromList -Title $Title -Items $Eligible -Label {
        param($Entry)
        "{0,-30} {1,10}" -f $Entry.Name, (Format-Size (Get-VhdxSize $Entry.Path))
    }

    if (-not $Picked) { Stop-Cancelled }
    return $Picked
}

# ---------------------------------------------------------------------------
# ASKING WHICH PACKS, AND DOING WHAT THE ANSWER SAYS
# ---------------------------------------------------------------------------
# Two commands ask the same question - manage_packs, about an instance that
# exists, and build, about one that is about to. It is asked here, once, so
# that the two commands cannot drift apart.

# What the ticked boxes mean: the diff, the requirements that ride along, the
# packs nothing claims any more. Split from the checklist below so a second
# asker - the window - can read the same rules; the two must not drift. The
# two lists come back ready to apply, requirements already in, in order, and
# with them what a caller still has to say: the boxes taken back, and the
# packs carried here that this checkout does not carry at all.
function Resolve-PackSelection {
    param(
        [WslPackCatalog]$Catalog,
        [string[]]$Installed = @(),
        [string[]]$Kept = @(),
        [string]$Family = "debian"
    )

    # The checklist's own surface: what a question shows is what can be taken
    # back - and only that. A folder this checkout does not carry was never
    # shown, so nobody can have unchecked it; it is named in grey instead. The
    # family narrows the surface further: a pack from another apt is no more
    # shown than one that is not carried.
    $OfferedNames = @($Catalog.OfferedFor($Family) | ForEach-Object { $_.Name })
    $Carried = @($Catalog.AvailablePacks | ForEach-Object { $_.Name })

    # Each list is read from a different side: kept and not installed goes in,
    # installed and not kept comes out. Reading the first off the available
    # packs instead is how a first run installed the pack nobody had asked for.
    $Unticked = @($Installed | Where-Object { $OfferedNames -contains $_ -and $Kept -notcontains $_ })
    $NotCarried = @($Installed | Where-Object { $Carried -notcontains $_ })

    # What a pack requires travels with it, and what nothing requires any more
    # leaves with it - both resolved here, so the console's lines, the window's
    # preview and the run read the same lists.
    #
    # Kept and installed is not added: the resolver is given what the instance
    # already has, and answers what is missing.
    $ToAdd = @()
    foreach ($Name in @($Catalog.ResolveSelection($Kept, $Installed))) {
        $Pack = $Catalog.GetPack($Name)
        if ($null -ne $Pack) { $ToAdd += $Pack }
    }
    # What arrives is worked out before what leaves, and that order matters: a
    # pack on its way in holds the invisible pack it requires, so the removal
    # must know about it.
    $ToRemove = @($Catalog.ResolveRemoval($Installed, $Unticked, @($ToAdd | ForEach-Object { $_.Name })))

    # What cannot leave yet: a pack a still-standing pack requires. Resolved
    # here, with both lists in hand, so the console and the window refuse
    # from the same answer.
    $Conflicts = @($Catalog.GetRemovalConflicts($Installed, $ToRemove, @($ToAdd | ForEach-Object { $_.Name })))

    return [PSCustomObject]@{
        ToAdd      = $ToAdd
        ToRemove   = $ToRemove
        Unticked   = $Unticked
        NotCarried = $NotCarried
        Conflicts  = $Conflicts
    }
}

# The packs a build ticks before the user does: the oh_my_shell pack, which carries
# the settings every visible pack requires - and only where its family is the
# recipe's own. The family is handed in (Get-BuildRecipeFamily reads it off
# the recipe; "" when nothing is known), and a shell pack of another family
# is left unticked, as is a catalog without one. The box is a default, not a
# command: the user unticks it like any other.
function Get-BuildDefaultPacks {
    param([WslPackCatalog]$Catalog, [string]$Family = "debian")

    $Shell = $Catalog.GetPack('oh_my_shell')
    if ($Shell -and $Shell.Offered -and $Shell.Family -eq $Family) { return @('oh_my_shell') }
    return @()
}

# What family a recipe belongs to, read off a Dockerfile's first FROM - the
# build's own question, asked before the image exists. The known Debian
# derivatives answer "debian" (the fold os-release would apply), anything
# else answers its base name (alpine, fedora...), and a file that cannot be
# read, or one whose FROM hides behind an ARG, answers "" - unknown, which
# filters and ticks nothing. An uploaded IMAGE answers "" by its caller: a
# docker-save tar keeps its rootfs in nested layers, and no half-cheap read
# exists.
function Get-BuildRecipeFamily {
    param([string]$Dockerfile)

    if (-not $Dockerfile -or -not (Test-Path -LiteralPath $Dockerfile)) { return "" }

    $Base = $null
    foreach ($Line in @(Get-Content -LiteralPath $Dockerfile -ErrorAction SilentlyContinue)) {
        # --platform and friends ride in front of the image name.
        if ("$Line" -match '^\s*FROM\s+(?:--\S+\s+)*(\S+)') { $Base = $Matches[1]; break }
    }
    if (-not $Base) { return "" }

    # registry/path/image:tag@digest -> the image name alone.
    $Name = ($Base -split '[@:]')[0].ToLower()
    $Name = ($Name -split '/')[-1]
    if ($Name -in @('debian', 'ubuntu', 'linuxmint', 'mint', 'kali', 'pop', 'raspbian',
                    'elementary', 'zorin', 'parrot', 'deepin', 'neon')) {
        return 'debian'
    }
    return $Name
}

# The checklist, the two lists, and the one question that carries them. $null
# means the user backed out (Escape, or "n" to the confirmation); otherwise
# { ToAdd; ToRemove }, either possibly empty - empty is an answer, not a
# cancellation.
#
# -Installed and -Checked differ at build time: a rebuilt instance has no pack
# yet, while the boxes expected ticked are the ones its predecessor carried.
# The lists come back ready to apply, requirements already in, in order.
function Select-Packs {
    param(
        [string]$Title,
        [WslPackCatalog]$Catalog,
        [string[]]$Installed = @(),
        [string[]]$Checked = $null,
        [string]$Family = "debian",
        [string]$Note = ""
    )

    if ($null -eq $Checked) { $Checked = $Installed }

    # What the checklist shows: the packs a user chooses, on this machine's
    # family - build passes nothing and the image's own family stands, debian.
    # An invisible one is installed by a visible pack that requires it and
    # leaves with the last one, so it is in neither list and is never named
    # here.
    $Offered = @($Catalog.OfferedFor($Family))

    $CheckedIndexes = @()
    for ($Index = 0; $Index -lt $Offered.Count; $Index++) {
        if ($Checked -contains $Offered[$Index].Name) { $CheckedIndexes += $Index }
    }

    # The family rides on each row, in brackets: a pack made for another
    # system is spotted before it is ticked - the only guard there is when
    # the recipe's own family cannot be read.
    $Chosen = Select-FromList -Title $Title -Items $Offered -Multi `
        -CheckedIndexes $CheckedIndexes -Note $Note -Label {
            param($Pack)
            "{0,-12} [{1}] {2}" -f $Pack.Name, $Pack.Family, $Pack.Description
        }

    if ($null -eq $Chosen) { return $null }

    # The ticked names go to the shared resolver - the window reads its answer
    # from the same rules - and what it says is then read out loud below.
    $Chosen = @($Chosen)
    $Kept = @($Chosen | ForEach-Object { $_.Name })

    $Resolved = Resolve-PackSelection -Catalog $Catalog -Installed $Installed -Kept $Kept -Family $Family
    $ToAdd = @($Resolved.ToAdd)
    $ToRemove = @($Resolved.ToRemove)
    $Unticked = @($Resolved.Unticked)

    # A pack a standing pack requires cannot leave: the whole answer is
    # refused, the claimant named - applying the rest without it would break
    # what stays. The checklist is the question; this is its guard.
    if ($Resolved.Conflicts.Count -gt 0) {
        Write-Host ""
        foreach ($Conflict in $Resolved.Conflicts) {
            Write-Host ("[ABORT] '{0}' cannot be removed: required by {1}." -f $Conflict.Name, ($Conflict.Blockers -join " and ")) -ForegroundColor (Get-MessageColour error)
            Write-Host ("        Untick {0} as well, or leave '{1}' ticked." -f ($Conflict.Blockers -join " and "), $Conflict.Name) -ForegroundColor (Get-MessageColour hint)
        }
        return $null
    }

    if ($Resolved.NotCarried.Count -gt 0) {
        Write-Host ""
        Write-Host ("       Installed here, not from this repository - left alone: {0}" -f ($Resolved.NotCarried -join ", ")) -ForegroundColor (Get-MessageColour muted)
    }

    if ($ToAdd.Count -eq 0 -and $ToRemove.Count -eq 0) {
        return [PSCustomObject]@{ ToAdd = @(); ToRemove = @() }
    }

    # Both lists, one question - the checklist was the choice, and asking again
    # pack by pack would only read it out loud. A list with nothing in it gets
    # no line. A pack the user did not tick is named with its reason under the
    # list: a pack that comes or goes without that line reads like a mistake.
    Write-Host ""
    if ($ToAdd.Count -gt 0) {
        Write-Host "Will install : " -NoNewline
        Write-Host (($ToAdd | ForEach-Object { $_.Name }) -join ", ") -ForegroundColor (Get-MessageColour info)
        $Because = @()
        foreach ($Pack in $ToAdd) {
            if ($Kept -notcontains $Pack.Name) {
                $Who = @($ToAdd | Where-Object { $_.Requires -contains $Pack.Name } | ForEach-Object { $_.Name })
                $Because += ("{0}: required by {1}" -f $Pack.Name, ($Who -join " and "))
            }
        }
        if ($Because.Count -gt 0) { Write-Host ("               (" + ($Because -join "; ") + ")") -ForegroundColor (Get-MessageColour muted) }
    }
    if ($ToRemove.Count -gt 0) {
        Write-Host "Will remove  : " -NoNewline
        Write-Host ($ToRemove -join ", ") -ForegroundColor (Get-MessageColour info)
        $Because = @()
        foreach ($Name in $ToRemove) {
            if ($Unticked -notcontains $Name) { $Because += ("{0}: nothing installed requires it any more" -f $Name) }
        }
        if ($Because.Count -gt 0) { Write-Host ("               (" + ($Because -join "; ") + ")") -ForegroundColor (Get-MessageColour muted) }
        Write-Host "               Their tools leave, and the dependencies nothing needs any more." -ForegroundColor (Get-MessageColour muted)
    }
    Write-Host ""

    $Confirm = [string](Read-Host "Proceed? [Y/n]")
    if ($Confirm -match "^[nN]") { return $null }

    return [PSCustomObject]@{ ToAdd = $ToAdd; ToRemove = $ToRemove }
}

# The Windows account's name, cleaned into a user name this family accepts:
# lowercase, accents unfolded, separators turned into single dashes, and the
# dashes and underscores framing it trimmed. Nothing is proposed when what
# remains cannot be a user name - a name the build made up would be worse
# than no proposal. Reads $env:USERNAME, so a test can drive it with names of
# its own.
function Get-WindowsUserProposal {
    $Name = "$env:USERNAME".ToLower()
    $Name = $Name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $Name = $Name -replace '[^a-z0-9_-]+', '-'
    $Name = $Name.Trim('-', '_')
    if ($Name -cmatch '^[a-z][a-z0-9_-]*$') { return $Name }
    return ""
}

# The user the instance opens as: asked with the rest, so the build knows it
# before the machine starts. The Windows account's name is offered as the
# answer when it cleans into one; the shape is checked here, with the same
# rule the onboarding applies; and whether the account is already one of the
# image's is read from the tar itself, just before the import.
function Resolve-DefaultUser {
    param([string]$DistroName, [string]$Proposed = "")

    $Prompt = "User name for '$DistroName' (CTRL+C to abort): "
    if ($Proposed) { $Prompt = "User name for '$DistroName' [$Proposed] (CTRL+C to abort): " }

    # A blank line, and the questions' yellow - the warning colour, the one
    # that stands out; the question lands right after another answer and must
    # not read as more of it. Read-Host cannot colour its own prompt, so the
    # line is written here - Read-Host only reads.
    Write-Host ""
    $UserName = $null
    while (-not $UserName) {
        Write-Host $Prompt -NoNewline -ForegroundColor (Get-MessageColour warning)
        $Answer = [string](Read-Host)
        # Interpolated first: Read-Host at end of input hands back null, and
        # Trim() on it would throw instead of falling back to the question.
        $Answer = "$Answer".Trim()
        # An empty answer takes the proposal, when there is one to take.
        if (-not $Answer -and $Proposed) { $Answer = $Proposed }
        # -cmatch, not -match: PowerShell's -match ignores case, and 'Root'
        # would pass here only to be refused inside.
        if ($Answer -cmatch '^[a-z][a-z0-9_-]*$') {
            $UserName = $Answer
        } else {
            Write-Host "  Lowercase letters, digits, '_' and '-' only, starting with a letter." -ForegroundColor (Get-MessageColour hint)
        }
    }
    return $UserName
}

# The files a build may start from: whatever the assets carry - Dockerfiles
# in assets\dockerfiles\<name>\Dockerfile, first boots in
# assets\onboardings\<name>\onboarding.sh, images in assets\dockerimages\
# under the name they arrived with. The repository's own Dockerfile and
# first_boot are seeded among them (see above): one source for the console's
# lists and the window's. One row per file: Name (what a list shows), Path
# (what the build takes), Uploaded (what the form's trash reads).
function Get-BuildRecipes {
    param([string]$AssetsDir)

    $dockerfiles = [System.Collections.Generic.List[object]]::new()
    $firstboots = [System.Collections.Generic.List[object]]::new()
    $images = [System.Collections.Generic.List[object]]::new()

    # A slot counts only when its file is there - a folder half-copied is not
    # a recipe, and neither is one whose file was deleted since.
    $dockerRoot = Join-Path $AssetsDir "dockerfiles"
    if (Test-Path $dockerRoot) {
        foreach ($slot in @(Get-ChildItem $dockerRoot -Directory | Sort-Object Name)) {
            $file = Join-Path $slot.FullName "Dockerfile"
            if (Test-Path $file) {
                $dockerfiles.Add([PSCustomObject]@{
                    Name     = Format-BuildRecipeName -BaseName ($slot.Name -replace '-[0-9a-f]{8}$', '') -Path $file
                    Path     = $file
                    Uploaded = $true
                })
            }
        }
    }
    $bootRoot = Join-Path $AssetsDir "onboardings"
    if (Test-Path $bootRoot) {
        foreach ($slot in @(Get-ChildItem $bootRoot -Directory | Sort-Object Name)) {
            $file = Join-Path $slot.FullName "onboarding.sh"
            if (Test-Path $file) {
                $firstboots.Add([PSCustomObject]@{
                    Name     = Format-BuildRecipeName -BaseName ($slot.Name -replace '-[0-9a-f]{8}$', '') -Path $file
                    Path     = $file
                    Uploaded = $true
                })
            }
        }
    }
    # An image slot holds the one file it was uploaded with, whatever its
    # name.
    $imageRoot = Join-Path $AssetsDir "dockerimages"
    if (Test-Path $imageRoot) {
        foreach ($slot in @(Get-ChildItem $imageRoot -Directory | Sort-Object Name)) {
            $file = @(Get-ChildItem -LiteralPath $slot.FullName -File | Select-Object -First 1)
            if ($file.Count -gt 0) {
                $images.Add([PSCustomObject]@{
                    Name     = Format-BuildRecipeName -BaseName ([IO.Path]::GetFileNameWithoutExtension($file[0].Name)) -Path $file[0].FullName
                    Path     = $file[0].FullName
                    Uploaded = $true
                })
            }
        }
    }
    return [PSCustomObject]@{ Dockerfiles = $dockerfiles; FirstBoots = $firstboots; Images = $images }
}

# What a recipe's row shows: its plain name and the day and minute it
# arrived. Two versions of one name - an iterated Dockerfile - are told
# apart by their dates, and the one just added carries today's.
function Format-BuildRecipeName {
    param([string]$BaseName, [string]$Path)

    return "$BaseName ($((Get-Item -LiteralPath $Path).LastWriteTime.ToString("dd'/'MM HH:mm")))"
}
