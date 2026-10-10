# The build's conversation, out of the command file: the console asks
# everything here - the recipe, the onboarding, the name and its folder, the
# packs, the account, both tick questions - fed by the command line's own
# words, read here and nowhere else, and renders the same answers object the
# window's form carries. The command holds the making: nothing past this
# returns asks anything.
using module ..\..\WslModel\WslModel.psd1

function Read-BuildAnswers {
    param(
        [WslInstanceManager]$Manager,
        [string]$RepoRoot,

        # What was typed after the command, untouched. The vocabulary lives
        # here: -Dockerfile, -Image and -FirstBoot answer their questions in
        # advance; anything else stops the run before a single question.
        [object[]]$Options = @()
    )

    # The words, paired up: -Name value, or a bare -Name meaning an empty
    # one. A splatted pair arrives as '-Name:' followed by the value - the
    # binder's own spelling, colon included (measured) - and a glued
    # '-Name:value' is taken whole. A word with no dash is kept as an option
    # named itself, so it lands in the refusal below like any stranger.
    $Typed = @{}
    $Pending = ""
    foreach ($Word in @($Options)) {
        $Word = "$Word"
        if ($Word.StartsWith('-')) {
            $Rest = $Word.TrimStart('-')
            $Cut = $Rest.IndexOf(':')
            if ($Cut -ge 0) {
                $Pending = $Rest.Substring(0, $Cut)
                $Glued = $Rest.Substring($Cut + 1)
                if ($Glued) { $Typed[$Pending] = $Glued; $Pending = "" }
                elseif (-not $Typed.ContainsKey($Pending)) { $Typed[$Pending] = "" }
            } else {
                $Pending = $Rest
                if (-not $Typed.ContainsKey($Pending)) { $Typed[$Pending] = "" }
            }
            continue
        }
        if ($Pending) { $Typed[$Pending] = $Word; $Pending = "" }
        else { $Typed[$Word] = "" }
    }
    foreach ($Option in @($Typed.Keys)) {
        if ($Option -notin @("Dockerfile", "Image", "FirstBoot")) {
            Write-Host ""
            Write-Host "[ABORT] Unknown options after the command." -ForegroundColor (Get-MessageColour error)
            Write-Host "        Run it on its own:  .\wsl.ps1 build" -ForegroundColor (Get-MessageColour hint)
            return $null
        }
    }
    $Dockerfile = "$($Typed.Dockerfile)"
    $Image = "$($Typed.Image)"
    $FirstBootGiven = $Typed.ContainsKey("FirstBoot")
    $FirstBoot = "$($Typed.FirstBoot)"

    # A road was given on the command line - before any default below: the
    # default is not a choice, the road question still owes.
    $RoadGiven = [bool]$Dockerfile -or [bool]$Image

    # The recipe: the chosen files, or the repository's own Dockerfile.
    # Resolved here so a path typed on the command line may be relative to
    # the repository, and checked before anything is asked - a path that
    # names no file stops the run with nothing confirmed and nothing
    # touched. Only presence is checked: whether a Dockerfile builds, or an
    # image loads, is the engine's own to say.
    if ($Image -and $Dockerfile) {
        Write-Host ""
        Write-Host "[ABORT] Choose one recipe: a Dockerfile, or a Docker image - not both." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        return $null
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
            return $null
        }
        # Nothing chosen here with images around, on a bare command line: the
        # road question below offers both, and refuses an empty Dockerfile list
        # itself.
    }

    # The onboarding: given on the command line, it is THE answer - nothing
    # asks it again. Absent, it defaults to the first script under the
    # assets - asked about below. None there at all, it is said and skipped.
    if (-not $FirstBootGiven) {
        $BootRows = @((Get-BuildRecipes -AssetsDir (Join-Path $RepoRoot "assets")).FirstBoots)
        if ($BootRows.Count -eq 0) {
            Write-Host "  No onboarding shell under 'assets\onboardings' - the instance will be built without one." -ForegroundColor (Get-MessageColour muted)
            $FirstBoot = ""
        } else {
            $FirstBoot = $BootRows[0].Path
        }
    }
    $ToCheck = @()
    if ($FirstBoot) { $ToCheck += @{ What = "first_boot"; Path = $FirstBoot } }
    if ($Image) { $ToCheck += @{ What = "Docker image"; Path = $Image } }
    elseif ($Dockerfile) { $ToCheck += @{ What = "Dockerfile"; Path = $Dockerfile } }
    foreach ($Named in $ToCheck) {
        if (-not (Test-Path -Path $Named.Path -PathType Leaf)) {
            Write-Host ""
            Write-Host "[ABORT] The $($Named.What) is not a file: $($Named.Path)" -ForegroundColor (Get-MessageColour error)
            Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
            return $null
        }
    }

    # 0-bis. What is being built, asked: the name and the folder.
    $Identity = Resolve-InstanceIdentity -Root $Manager.InstancesRoot

    # 0-bis-bis. What to build from, when the command line did not choose:
    # the road first - a Dockerfile, or an image - then the list that road
    # offers, uploads included. No image around, nothing is asked: the
    # Dockerfile road, as always, and its default was taken above.
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
                return $null
            }
            $Picked = Select-FromList -Title "$($Road.Label)" -Items $Rows -Label { param($Row) $Row.Name }
            if ($null -eq $Picked) { Stop-Cancelled }
            if ($Road.Type -eq [WslBuildType]::Image) { $Image = $Picked.Path; $Dockerfile = "" }
            else { $Dockerfile = $Picked.Path }
        }
    }

    # 0-ter. The packs, asked here with everything else: nothing asks again
    # once the machine starts working - the answer waits in a variable and is
    # applied by the command. Empty, or Escape, means none, and the build
    # goes on either way. What family the recipe belongs to is read first: it
    # decides the boxes offered and the shell pack pre-ticked - the
    # Dockerfile's FROM when there is one, and unknown for an image, whose
    # rootfs nests inside a save-tar.
    $PackNames = ""
    $PackCatalog = $Manager.Catalog
    if ($PackCatalog.AvailablePacks.Count -gt 0) {
        $RecipeFamily = if ($Image) { "" } else { Get-BuildRecipeFamily -Dockerfile $Dockerfile }
        # A family that cannot be read is said above the checklist, not hidden:
        # the packs stay in reach - the image may well be Debian under a name we
        # cannot read - and the line is the guard for whoever does not know.
        $FamilyNote = if ($RecipeFamily) { "" } else { "This recipe's system cannot be read - a pack made for another one will fail to install." }

        # The shell pack arrives ticked - every visible pack requires it - and
        # its box unticks like any other. -Installed stays at its default: the
        # instance this build makes carries nothing yet - boxes to tick, no
        # removal to compute.
        $PreChecked = @(Get-BuildDefaultPacks -Catalog $PackCatalog -Family $RecipeFamily)
        $Selection = Select-Packs -Title "Packs for '$($Identity.Name)'" -Catalog $PackCatalog -Checked $PreChecked -Family $RecipeFamily -Note $FamilyNote

        if ($null -eq $Selection -or $Selection.ToAdd.Count -eq 0) {
            Write-Host ""
            Write-Host "[OK] No pack selected." -ForegroundColor (Get-MessageColour success)
        } else {
            $PackNames = (@($Selection.ToAdd | ForEach-Object { $_.Name }) -join ',')
        }
    }

    # 0-quater. The onboarding, then the account it makes. The account's name
    # only matters when an onboarding runs: it is the onboarding that makes
    # the account, and it receives the name. Without one, the instance opens
    # as the image's own account and no name is asked.
    if (-not $FirstBootGiven -and $FirstBoot) {
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
    $Account = ""
    if ($FirstBoot) {
        $Account = Resolve-DefaultUser -DistroName $Identity.Name -Proposed (Get-WindowsUserProposal)
    }

    # The last two answers, asked with everything else: what becomes of the
    # working image (the Dockerfile road's own - an image road has nothing to
    # keep), and Docker Desktop's question.
    $KeepAnswer = if (-not $Image) { Confirm-YesNo "Keep Docker image?" } else { $false }
    $DockerAnswer = Confirm-YesNo "Add '$($Identity.Name)' to Docker Desktop? (it will be restarted)"

    # The answers, in the window's own shape.
    return [PSCustomObject]@{
        Name           = $Identity.Name
        User           = $Account
        Packs          = $PackNames
        Dockerfile     = $Dockerfile
        Image          = $Image
        FirstBoot      = $FirstBoot
        SaveImage      = $KeepAnswer
        RegisterDocker = $DockerAnswer
    }
}
