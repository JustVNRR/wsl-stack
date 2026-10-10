# ==============================================================================
# THE RECIPE OF AN INSTANCE
# ==============================================================================
# Where the image comes from - a Dockerfile, an uploaded image, a registry
# name - the onboarding shell the account was made by, and the look the
# instance was born with. Status and Messages tell how the making went.
using module .\WslTheme.psm1
using module .\WslPack.psm1

# The roads to an image - every recipe comes by one. Registry is not walked
# yet: named here so the third road is a value, not a type to widen.
enum WslBuildType {
    Dockerfile
    Image
    Registry
}

# How the making went. Pending from creation - a recipe is made before it
# runs; Warning, born with reservations (Messages says which); Nok, a vital
# piece failed.
enum WslRecipeStatus {
    Pending
    Ok
    Warning
    Nok
}

class WslRecipe {
    [WslBuildType]$BuildType

    # The Dockerfile's or the uploaded image's full path as it was on this
    # machine; the image NAME, on the registry road.
    [string]$BuildPath

    # The folder docker builds FROM - the build context. The repository's
    # Dockerfiles write their COPY paths against the repository root, so
    # that root is what a build records here; the day an uploaded Dockerfile
    # brings files of its own beside it, this field says where they live.
    [string]$Context = ""

    # The onboarding shell the account was made by, full path too. Empty - an
    # unticked box, or a bare image - means none: the instance opens as what
    # the image already carries.
    [string]$FirstBoot

    # What the instance looks like: born with it, and the four gestures of
    # the look change it from there.
    [WslTheme]$Look

    [WslRecipeStatus]$Status = [WslRecipeStatus]::Pending

    # What could not be applied, one line each - a look piece that failed, a
    # step that was skipped. The build's summary shows them, instance.json
    # keeps them.
    [string[]]$Messages = @()

    # The caller's word on the working image: at the end of the birth it is
    # saved as a tar beside the other images (the image road loads it back,
    # no rebuild) - the working image itself goes back either way, nothing
    # needs it any more. The image road has no use for it: that image is not
    # the build's to keep or save.
    [bool]$KeepImage =$true

    # The caller's word on Docker Desktop: at the birth's end the instance's
    # name is written among the distros Docker Desktop knows and the app is
    # restarted, its docker client injected - both roads, the road an image
    # came by saying nothing about the distro's place there. The birth acts
    # on it and fails on what cannot be done; nothing needs it after.
    [bool]$RegisterDocker =$false

    # The packs chosen with the questions: the birth installs them on its
    # last step - the instance's own act. A making's word, like the two
    # above: nothing needs them after, and the file does not keep them.
    [WslPack[]]$Packs = @()

    # The tag a build's working image wears: one per instance, so two builds
    # cannot fight over the same name - the making and the taking-back both
    # ask here, and neither spells it itself.
    static [string] TagFor([string]$name) {
        return "wsl-stack:$name"
    }

    WslRecipe() {}

    # The roads a build can take, in the order a chooser offers them, each
    # with the word it goes by: the console's question and the window's combo
    # both read this - one list, so the two cannot drift. Registry waits for
    # the day it is walked.
    static [object[]] Roads() {
        return @(
            [PSCustomObject]@{ Type = [WslBuildType]::Dockerfile; Label = "Dockerfile" },
            [PSCustomObject]@{ Type = [WslBuildType]::Image; Label = "Docker image" }
        )
    }

    # --- Fluent Builder Methods -----------------------------------------------

    # An empty path means "not this road": the command hands both, and the
    # one it did not take sets nothing.
    [WslRecipe] WithDockerfile([string]$dockerfilePath, [string]$context) {
        if (-not $dockerfilePath) { return $this }
        $this.BuildType = [WslBuildType]::Dockerfile
        $this.BuildPath = $dockerfilePath
        $this.Context   = $context
        return $this
    }

    [WslRecipe] WithImage([string]$imagePath) {
        if (-not $imagePath) { return $this }
        $this.BuildType = [WslBuildType]::Image
        $this.BuildPath = $imagePath
        return $this
    }

    [WslRecipe] WithFirstBoot([string]$firstBoot) {
        $this.FirstBoot =$firstBoot
        return $this
    }

    [WslRecipe] WithLook([WslTheme]$theme) {
        $this.Look =$theme
        return $this
    }

    [WslRecipe] WithPacks([WslPack[]]$packs) {
        $this.Packs = @($packs)
        return $this
    }

    [WslRecipe] WithKeepImage([bool]$keep) {
        $this.KeepImage =$keep
        return $this
    }

    [WslRecipe] WithRegisterDocker([bool]$register) {
        $this.RegisterDocker =$register
        return $this
    }

    # --------------------------------------------------------------------------

    # Makes the image this recipe stands for, in the local Docker store, and
    # answers the name the birth works under from there: for the Dockerfile
    # road the working tag its instance's name wears - the image is built
    # under it - and for an uploaded image's tar whatever docker load read
    # out of it, name or bare id. The tar's own name, never a second one put
    # on it: an image made elsewhere keeps its name. The roads not walked -
    # Registry named before its time - throw.
    [string] MakeImage([string]$name) {
        $Tag = [WslRecipe]::TagFor($name)
        switch ($this.BuildType) {
            ([WslBuildType]::Dockerfile) {
                # Not named $Context: a method's local cannot carry a
                # property's name - "$Context =$this.Context" parses as a
                # property write and is refused (measured).
                $File =$this.BuildPath
                $BuildFrom =$this.Context
                # A process of its own: a native run under a class method has
                # its output swallowed whole (measured), and a docker build
                # is minutes of output the user must see.
                $Arguments = 'build -t {0} -f "{1}" "{2}"' -f $Tag,$File, $BuildFrom 
                $Process = Start-Process docker -ArgumentList $Arguments -NoNewWindow -PassThru
                $Process.WaitForExit()
                if ($Process.ExitCode -ne 0) {
                    throw "Docker build failed. (Exit code: $($Process.ExitCode))"
                }
                return $Tag
            }
            ([WslBuildType]::Image) {
                $ImagePath =$this.BuildPath
                # $global: on purpose: a class method reads no automatic from
                # the caller's scope - bare, either name throws "Variable is
                # not assigned in the method" (measured).
                $PreviousEAP = $global:ErrorActionPreference
                $global:ErrorActionPreference = "Continue"
                $Output = @(& docker load -i $ImagePath 2>&1)
                $Code =$global:LASTEXITCODE
                $global:ErrorActionPreference =$PreviousEAP
                if ($Code -ne 0) {
                    throw "The Docker image could not be loaded:`n$($Output -join "`n")"
                }

                # docker load says what it put where: "Loaded image: name:tag"
                # for a saved tagged image, "Loaded image ID: sha256:..." for
                # one saved by id.
                $Loaded =$null
                foreach ($Line in $Output) {
                    if ("$Line" -match '^Loaded image(?: ID)?: (.+)$') { $Loaded =$Matches[1].Trim(); break }
                }
                if (-not $Loaded) { throw "docker load told nothing usable about the image in '$ImagePath'." }
                return $Loaded
            }
            default {
                throw "Invalid WslBuildType: '$($this.BuildType)'."
            }
        }

        # Never reached - the switch covers every road and throws on the
        # rest: for the parser, which cannot prove it (the same shape the
        # menus carry).
        return ""
    }
}