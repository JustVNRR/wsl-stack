# The window's files, where they live now: every .xaml under scripts/gui must
# be well-formed XML, every resource reference - in the theme and in the
# windows - must name a key the theme itself defines (or one the code sets),
# the colour sets under assets\colours must be well-formed and tell only keys
# the theme knows, and the three runners must parse and keep calling the
# engine's ways. Before the split this markup lived inside gui.ps1 and rode
# along in parse-check; on disk, nothing else in the repository reads it.
#
# Usage:  pwsh -NoProfile -File tests\gui-test.ps1

$bad = 0
$GuiRoot = Join-Path $PSScriptRoot "..\src\windows\gui"

# 1. The XAML files: well-formed XML, each one.
$xamlFiles = @(Get-ChildItem $GuiRoot -Recurse -Filter *.xaml)
foreach ($f in $xamlFiles) {
    try {
        $null = [xml]([IO.File]::ReadAllText($f.FullName))
    } catch {
        Write-Host "::error file=$($f.FullName)::not well-formed XML"
        Write-Host "  $($_.Exception.Message)"
        $bad = 1
    }
}
Write-Host "$($xamlFiles.Count) .xaml file(s) read from scripts/gui."

# 2. The theme's own bookkeeping: every reference points at a key it defines.
$keys = @()
$themePath = Join-Path $GuiRoot "Theme\theme.xaml"
if (Test-Path $themePath) {
    $theme = [IO.File]::ReadAllText($themePath)
    $keys = @([regex]::Matches($theme, 'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $refs = @([regex]::Matches($theme, '\{(?:Static|Dynamic)Resource ([A-Za-z][A-Za-z0-9]*)\}') | ForEach-Object { $_.Groups[1].Value })
    $missing = @($refs | Where-Object { $_ -notin $keys })
    if ($missing.Count -gt 0) {
        Write-Host "::error file=$themePath::a resource reference names a key the theme does not define"
        Write-Host "  missing: $($missing -join ', ')"
        $bad = 1
    }
    Write-Host "theme: $($keys.Count) key(s), $($refs.Count) reference(s)."

    # 2b. And the windows resolve the same way: a key that is neither in the
    # theme nor set by the code (IconFace, handed to the window by gui.ps1)
    # fails SILENTLY - WPF falls back without a word.
    $codeKeys = @("IconFace")
    $viewRefs = @{}
    foreach ($f in $xamlFiles) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName), '\{(?:Static|Dynamic)Resource ([A-Za-z][A-Za-z0-9]*)\}')) {
            $viewRefs[$m.Groups[1].Value] = $true
        }
    }
    $missingView = @($viewRefs.Keys | Where-Object { $_ -notin $keys -and $_ -notin $codeKeys })
    if ($missingView.Count -gt 0) {
        Write-Host "::error file=$GuiRoot\Views::a window references a key nothing defines"
        Write-Host "  missing: $($missingView -join ', ')"
        $bad = 1
    }
    Write-Host "views: $($viewRefs.Count) key(s) referenced."
} else {
    Write-Host "::error file=$themePath::the theme is not there"
    $bad = 1
}

# 3. The runners: they parse, and the engine call each verb rides on stays
#    pinned - a rewrite that quietly changes the call is the bug this catches.
$runners = @(Get-ChildItem (Join-Path $GuiRoot "Runners") -Filter *.ps1)
foreach ($f in $runners) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($f.FullName), [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Host "::error file=$($f.FullName)::$($errors.Count) parse error(s)"
        foreach ($e in $errors) { Write-Host ("  line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
        $bad = 1
    }
}

$pins = @(
    @{ File = "JobRunner.ps1";   Pattern = 'RestoreFromArchive\(\$ArchiveFirst, \$Name\)';        What = "RestoreFromArchive(archive, name)" },
    @{ File = "JobRunner.ps1";   Pattern = 'DeleteArchive\(\$Name\)';                             What = "DeleteArchive(name)" },
    @{ File = "JobRunner.ps1";   Pattern = 'Archive\(\$inst, \$ArchiveFirst, "tar\.gz"\)';        What = "Archive(inst, name, tar.gz)" },
    @{ File = "JobRunner.ps1";   Pattern = 'Duplicate\(\$inst, \$ArchiveFirst\)';                 What = "Duplicate(inst, name)" },
    @{ File = "EditRunner.ps1";  Pattern = 'ManagePacks\(\$inst, \$toAdd, \$toRemove, ""\)';      What = 'ManagePacks(inst, add, remove, "")' },
    @{ File = "BuildRunner.ps1"; Pattern = '& \$BuildScript -Name \$Name -User \$User -Packs \$Packs -Manager \$mgr'; What = "build.ps1 with its named arguments" }
)
foreach ($pin in $pins) {
    $runnerPath = Join-Path $GuiRoot "Runners\$($pin.File)"
    if (-not (Test-Path $runnerPath) -or ([IO.File]::ReadAllText($runnerPath) -notmatch $pin.Pattern)) {
        Write-Host "::error file=$runnerPath::no longer calls $($pin.What)"
        $bad = 1
    }
}
Write-Host "$($runners.Count) runner(s) read, $($pins.Count) call(s) pinned."

# 4. The colour sets: well-formed, and every key they tell - the Dark and
#    Light block names excepted - exists in the theme. A misspelled one is
#    ignored in silence and keeps the default, near impossible to notice
#    by eye.
$setsRoot = Join-Path $PSScriptRoot "..\assets\colours"
$setFiles = if (Test-Path $setsRoot) { @(Get-ChildItem $setsRoot -Filter *.xaml) } else { @() }
foreach ($f in $setFiles) {
    try {
        $null = [xml]([IO.File]::ReadAllText($f.FullName))
    } catch {
        Write-Host "::error file=$($f.FullName)::not well-formed XML"
        $bad = 1
        continue
    }
    $setKeys = @([regex]::Matches([IO.File]::ReadAllText($f.FullName), 'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $strange = @($setKeys | Where-Object { $_ -notin $keys -and $_ -notin @("Dark", "Light") })
    if ($strange.Count -gt 0) {
        Write-Host "::error file=$($f.FullName)::names a key the theme does not define"
        Write-Host "  unknown: $($strange -join ', ')"
        $bad = 1
    }
}
Write-Host "$($setFiles.Count) colour set(s) read."

Write-Host "gui: $($xamlFiles.Count + $runners.Count + $setFiles.Count) file(s), $bad failure(s)."
exit $bad
