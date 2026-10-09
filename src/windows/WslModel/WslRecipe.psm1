# ==============================================================================
# THE RECIPE OF AN INSTANCE
# ==============================================================================
# Where the image comes from - a Dockerfile, an uploaded image, a registry
# name - the onboarding shell the account was made by, and the look the
# instance was born with. Status and Messages tell how the making went.
using module .\WslTheme.psm1

# The three roads to an image - Unknown standing for a file from before the
# field, or an archive that carried none. Registry is not walked yet: named
# here so the third road is a value, not a type to widen.
enum WslBuildType {
    Unknown
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

    WslRecipe() {}
}
