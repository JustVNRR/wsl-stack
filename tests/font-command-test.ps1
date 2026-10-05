# The classes this file names, pulled in by the file itself.
using module ..\scripts\WslModel\WslModel.psd1

# Drives `font` - the command behind `.\wsl.ps1 theme` - the way a script would:
# the numbered prompt, answers on standard input, no console anywhere.
#
# The instance it works on exists for the length of the test: a registry key of
# its own, a folder carrying the marker, and the WSL fragment Terminal reads a
# profile from. All three are taken back out at the end.
#
# What is checked is what the command is for: the list is the fonts that carry
# the glyphs a prompt is drawn with, the font in use is marked, and picking one
# writes it into the profile this repository owns and into the instance's own
# file - the icon's recipe kept with it. The list is read from a first run
# that cancels, so the number given to
# the second was really there. A machine with no Nerd Font has a list of one -
# the font in use - and that is the list it should draw there.
#
# It needs no instance, no console and no Docker Desktop.
#
# Usage:  pwsh -NoProfile -File tests\font-command-test.ps1

$ErrorActionPreference = "Stop"

# For Get-Distros and the marker test: the list the command itself builds.
Import-Module (Join-Path $PSScriptRoot "..\scripts\WslStack\WslStack.psd1") -Force

$FontScript = Join-Path $PSScriptRoot "..\scripts\WslCommands\font.ps1"
# Child processes follow the engine this suite runs under, so a pass under 7
# tests the scripts under 7.
$Engine = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
# The commands are driven through invoke-command.ps1: a fresh pwsh has nothing
# loaded, and a command takes its manager as a parameter - the invoker loads
# the module first, as wsl.ps1 does, and hands one over.
$Invoker = Join-Path $PSScriptRoot "invoke-command.ps1"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("font-command-test-" + [Guid]::NewGuid().ToString("N"))
$FakeName = "font-command-test"
$FakeFolder = Join-Path $Tmp "instance"
$Recipe = Join-Path $FakeFolder "instance.json"
$Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e5f}"

# The profile Terminal knows an instance by - a fragment WSL writes, over which
# this repository layers its own.
$WslFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\Microsoft.WSL\{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e6f}.json"
$OurFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$FakeName.json"
$OurFragmentExisted = Test-Path $OurFragment

$Failures = 0
function Check {
    param([string]$Name, $Got, $Expected)
    if ("$Got" -eq "$Expected") {
        Write-Output "OK   $Name"
    } else {
        Write-Output "FAIL $Name : expected '$Expected', got '$Got'"
        $script:Failures++
    }
}

function Invoke-Font {
    param([string[]]$Answers)

    $Preference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Lines = $Answers | & $Engine -NoProfile -File $Invoker -Script $FontScript 2>&1
    } finally {
        $ErrorActionPreference = $Preference
    }
    return $Lines
}

# The rows of the numbered list, as the command drew them: the font names, in
# order, each row's first column being its number.
#
# Read from the title of the font menu down: the instance list drawn above it -
# number, name, more - is not fonts (counted as fonts once, the number given to
# the second run pointed at something else).
function Get-ListedFonts {
    param([object[]]$Lines)

    $Rows = @()
    $Inside = $false
    foreach ($Line in $Lines) {
        if ("$Line" -like "Font of '*'") { $Inside = $true; continue }
        if (-not $Inside) { continue }
        if ("$Line" -match '^\s*(\d+)\.\s+(\S.*?)\s*$') {
            if ($Matches[1] -eq "0") { return $Rows }
            $Rows += ($Matches[2] -replace '\s{2,}.*$', '')
        }
    }
    return $Rows
}

New-Item -ItemType Directory -Path $FakeFolder -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $FakeFolder ".wsl-stack") -Force | Out-Null

try {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $Key -Force | Out-Null
    Set-ItemProperty -Path $Key -Name DistributionName -Value $FakeName
    Set-ItemProperty -Path $Key -Name BasePath -Value $FakeFolder

    New-Item -ItemType Directory -Path (Split-Path -Parent $WslFragment) -Force | Out-Null
    Set-Content -Path $WslFragment -Encoding Utf8 -Value @"
{
    "profiles": [
        {
            "name": "$FakeName",
            "guid": "{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e6f}"
        }
    ]
}
"@

    # The recipe a drawing left behind: a font change must keep it - one change
    # keeps the others, and the icon command starts from these letters later.
    Set-InstanceLook -InstallPath $FakeFolder -Look (New-InstanceLook -Name $FakeName -Icon @{
        Text = "FT"; Top = "#111111"; Bottom = "#222222"; TextColor = "#FFFFFF" })

    $All = @(Get-Distros | Where-Object { Test-TemplateInstance -Folder $_.Path } | Sort-Object Name)
    $Pick = [array]::IndexOf(@($All.Name), $FakeName) + 1
    Check "the test's instance is in the list" ($Pick -ge 1) $true

    # 1. The list, read off a run that cancels: nothing is applied, and what it
    # drew is what the second run will be asked for
    $Out = Invoke-Font @("$Pick", "0")
    $Fonts = @(Get-ListedFonts $Out)
    Check "the list is not empty" ($Fonts.Count -ge 1) $true
    # Checked with the font that shows it: Consolas is monospaced, on every
    # Windows, and carries none of the glyphs a prompt is drawn with.
    Check "a font that carries no icons is not offered" ($Fonts -notcontains "Consolas") $true
    Check "and the symbol fonts are not" (@($Fonts | Where-Object { $_ -like "Wingdings*" }).Count) 0
    Check "the one in use is marked" (@($Out | Where-Object { "$_" -like "*(current)*" }).Count -gt 0) $true
    Check "it says where more of them come from" (@($Out | Where-Object { "$_" -like "*nerdfonts.com*" }).Count -gt 0) $true
    Check "cancelling applied nothing" (Test-Path $OurFragment) $OurFragmentExisted

    # 2. Picking one: the number it had in that list, given to a second run - a
    # font other than the one in use, or picking the current one would be
    # written the same way whether the choice was read or not.
    $Current = (Get-InstanceAppearance -Name $FakeName).FontName
    $Want = @($Fonts | Where-Object { $_ -ne $Current }) | Select-Object -First 1
    if (-not $Want) { $Want = $Fonts[0] }
    $Wanted = [array]::IndexOf($Fonts, $Want) + 1
    $null = Invoke-Font @("$Pick", "$Wanted")

    # A rule, not a diagnosis: a mark is not part of JSON, the fragments known
    # to work - WSL's own, Terminal's settings.json - begin with a brace, and
    # PowerShell's -Encoding Utf8 writes a mark whether anyone asked or not.
    $Bytes = [System.IO.File]::ReadAllBytes($OurFragment)
    Check "the fragment starts with a brace, not a mark" ([char]$Bytes[0]) "{"

    $Written = Get-Content $OurFragment -Raw | ConvertFrom-Json
    Check "the font is written into our profile" $Written.profiles[0].font.face "$Want"
    Check "  ... under the guid Terminal knows" $Written.profiles[0].updates "{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e6f}"
    Check "  ... and the look around it is kept" ($Written.profiles[0].PSObject.Properties.Name -contains "colorScheme") $true

    $Saved = Get-Content $Recipe -Raw | ConvertFrom-Json
    Check "and into the instance's own file" $Saved.Font "$Want"
    Check "which is still the instance's" $Saved.Name $FakeName
    Check "and the icon's recipe survives the change" $Saved.IconText "FT"
    Check "  ... colours and all" "$($Saved.IconTop) $($Saved.IconBottom) $($Saved.IconTextColor)" "#111111 #222222 #FFFFFF"

    # 3. The way in: the menu asks which instance, hands over, and is drawn
    # again when done. Answers: the instance, "font", Escape on the list, Escape
    # here.
    $Preference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Themed = @("$Pick", "2", "0", "0") | & $Engine -NoProfile -File $Invoker -Script (Join-Path $PSScriptRoot "..\scripts\WslCommands\theme.ps1") 2>&1
    } finally {
        $ErrorActionPreference = $Preference
    }
    Check "theme hands over to the font command" (@($Themed | Where-Object { "$_".Contains("Font of '$FakeName'") }).Count -gt 0) $true
    # Twice: once to start with, and once more when the theme menu is left -
    # Escape goes back up to the list.
    Check "and the list comes back when the menu is left" (@($Themed | Where-Object { "$_".Contains("Our Instances") }).Count) 2
    Check "and the menu comes back when it is done" (@($Themed | Where-Object { "$_".Contains("Theme of '$FakeName'") }).Count) 2

    # 4. The other half of the rule: the font in use is in the list whatever it
    # carries. The instance is put on Consolas - monospaced, on every Windows,
    # no icons - through the profile writer the command reads, and the list has
    # to show it anyway, marked.
    Set-InstanceFragment -Name $FakeName -Guid "{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e6f}" `
        -Theme ([WslTheme]::new($null, "One Half Dark", "Consolas", $FakeName))
    $Out2 = Invoke-Font @("$Pick", "0")
    $Fonts2 = @(Get-ListedFonts $Out2)
    Check "the font in use is listed even without icons" ($Fonts2 -contains "Consolas") $true
    Check "  ... and marked as the one in use" (@($Out2 | Where-Object { "$_" -like "*Consolas*(current)*" }).Count -gt 0) $true
} finally {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $WslFragment -Force -ErrorAction SilentlyContinue
    if (-not $OurFragmentExisted) { Remove-Item $OurFragment -Force -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
