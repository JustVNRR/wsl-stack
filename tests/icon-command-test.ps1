# Drives `icon` the way a script would: the numbered prompt, answers on standard
# input, no console anywhere - it is the command behind `.\wsl.ps1 theme`.
#
# The instance it works on exists for the length of the test: a registry key of
# this test's own, a folder carrying the marker, a name of its own. The answers
# are numbers, worked out from the same list the command shows, so the number
# points at ours whatever else is installed; the key is taken back out at the
# end.
#
# What is checked is what the command is for: one change keeps the others, Enter
# takes the letters offered, an image of your own leaves the recipe in place.
#
# It needs no instance, no console and no Docker Desktop.
#
# Usage:  pwsh -NoProfile -File tests\icon-command-test.ps1

$ErrorActionPreference = "Stop"

# For Get-Distros and the marker test: the list the command itself builds.
. (Join-Path $PSScriptRoot "..\scripts\instance.ps1")

$IconScript = Join-Path $PSScriptRoot "..\scripts\icon.ps1"
# Child processes follow the engine this suite runs under, so a pass under 7
# tests the scripts under 7.
$Engine = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
# The commands are driven through invoke-command.ps1: a fresh pwsh has no
# classes, and a command's typed -Manager parameter is settled before the
# command runs - the shared half must be loaded first, as wsl.ps1 does.
$Invoker = Join-Path $PSScriptRoot "invoke-command.ps1"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("icon-command-test-" + [Guid]::NewGuid().ToString("N"))
$FakeName = "icon-command-test"
$FakeFolder = Join-Path $Tmp "instance"
$IconPath = Join-Path $FakeFolder "terminal-icon.png"
# One file per instance, in its folder: the same shape an archive carries.
$Recipe = Join-Path $FakeFolder "instance.json"
$Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e5f}"

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

# The command, with its answers on standard input. Its own error output is read
# rather than thrown: a failure is a result to report, not the end of the suite.
function Invoke-Icons {
    param([string[]]$Answers)

    $Preference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Lines = $Answers | & $Engine -NoProfile -File $Invoker -Script $IconScript 2>&1
    } finally {
        $ErrorActionPreference = $Preference
    }
    return $Lines
}

function Get-Recipe {
    if (-not (Test-Path $Recipe)) { return $null }
    return (Get-Content $Recipe -Raw | ConvertFrom-Json)
}

# `.\wsl.ps1 theme` names the commands, and the one it names is the one that
# runs - the only door, driven from here.
function Invoke-Theme {
    param([string[]]$Answers)

    $Preference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Lines = $Answers | & $Engine -NoProfile -File $Invoker -Script (Join-Path $PSScriptRoot "..\scripts\theme.ps1") 2>&1
    } finally {
        $ErrorActionPreference = $Preference
    }
    return $Lines
}

New-Item -ItemType Directory -Path $FakeFolder -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $FakeFolder ".wsl-stack") -Force | Out-Null

try {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $Key -Force | Out-Null
    Set-ItemProperty -Path $Key -Name DistributionName -Value $FakeName
    Set-ItemProperty -Path $Key -Name BasePath -Value $FakeFolder

    # Which number our instance is in the list the command draws - worked out
    # with the same code, so the answer is right whatever else is installed.
    $All = @(Get-Distros | Where-Object { Test-TemplateInstance -Folder $_.Path } | Sort-Object Name)
    $Pick = [array]::IndexOf(@($All.Name), $FakeName) + 1
    Check "the test's instance is in the list" ($Pick -ge 1) $true

    # 1. The automatic icon, drawn from the name of the instance
    $Out = Invoke-Icons @("$Pick", "1")
    Check "the icon is drawn" (Test-Path $IconPath) $true
    Check "on the instance this test made" (@($Out | Where-Object { "$_".Contains("Icon of '$FakeName'") }).Count -gt 0) $true
    $Saved = Get-Recipe
    Check "the instance's own file is written" (Test-Path $Recipe) $true
    Check "and says whose it is" $Saved.Name $FakeName
    Check "with the look it was built with" $Saved.Font "MesloLGS NF"
    Check "the letters of the name" $Saved.IconText "IC"
    $Auto = "$($Saved.IconTop) $($Saved.IconBottom) $($Saved.IconTextColor)"

    # 2. Escape is not a change: the icon is redrawn, the note says the same
    $Before = (Get-FileHash $IconPath).Hash
    $null = Invoke-Icons @("$Pick", "0")
    Check "cancelling changes nothing" (Get-FileHash $IconPath).Hash $Before

    # 3. Other letters: they are the ones drawn, the colours stay
    $null = Invoke-Icons @("$Pick", "2", "xyz")
    $Saved = Get-Recipe
    Check "other letters, typed and capitalised" $Saved.IconText "XYZ"
    Check "other letters, the colours stay" "$($Saved.IconTop) $($Saved.IconBottom) $($Saved.IconTextColor)" $Auto

    # 4. Other letters, answered with Enter: the question offers the letters the
    # icon has now, and taking that answer changes nothing
    $Out = Invoke-Icons @("$Pick", "2", "")
    $Saved = Get-Recipe
    Check "text: the letters are offered in the question" (@($Out | Where-Object { "$_".Contains("[XYZ]") }).Count -gt 0) $true
    Check "text: Enter keeps them" $Saved.IconText "XYZ"

    # 5. Other colours: the pair is the one picked, the letters stay, and each
    # pair is shown with those letters on it
    $Out = Invoke-Icons @("$Pick", "3", "2")
    $Saved = Get-Recipe
    Check "other colours, the letters stay" $Saved.IconText "XYZ"
    Check "other colours, the pair picked is on" "$($Saved.IconTop) $($Saved.IconBottom)" "#3B82F6 #2563EB"
    Check "and every pair shows the letters" (@($Out | Where-Object { "$_".Contains("XYZ  orange") }).Count -gt 0) $true
    Check "and the pair in use was marked in the list" (@($Out | Where-Object { "$_" -like "*(current)*" }).Count -gt 0) $true

    # 6. An image of your own: copied in place, and the recipe stays - it is what
    # changing your mind starts from, not a description of the picture
    $Mine = Join-Path $Tmp "mine.png"
    Copy-Item -Path $IconPath -Destination $Mine -Force
    $null = Invoke-Icons @("$Pick", "4", $Mine)
    Check "an image of my own is copied in place" (Get-FileHash $IconPath).Hash (Get-FileHash $Mine).Hash
    $Saved = Get-Recipe
    Check "and the recipe is kept" $Saved.IconText "XYZ"

    # 7. Changing your mind after an image: the letters come back from the recipe,
    # not from the name
    $null = Invoke-Icons @("$Pick", "3", "1")
    $Saved = Get-Recipe
    Check "colours again after an image: the letters are the ones drawn" $Saved.IconText "XYZ"
    Check "and the pair is the one picked" "$($Saved.IconTop) $($Saved.IconBottom)" "#CF7040 #B95E30"

    # 8. The automatic one is the one that starts over from the name
    $null = Invoke-Icons @("$Pick", "1")
    $Saved = Get-Recipe
    Check "the automatic one starts over from the name" $Saved.IconText "IC"

    # 9. What an archive carries: that same file, refreshed from the machine,
    # recipe inside - and the picture beside it
    $Archive = Join-Path $Tmp "archive"
    New-Item -ItemType Directory -Path $Archive -Force | Out-Null
    $null = [WslInstance]::GetByName($FakeName).ArchiveLook($Archive)
    Check "an archive carries the instance's file" (Test-Path (Join-Path $Archive "instance.json")) $true
    Check "and its picture" (Test-Path (Join-Path $Archive "terminal-icon.png")) $true
    $Kept = Get-Content (Join-Path $Archive "instance.json") -Raw | ConvertFrom-Json
    Check "with the recipe inside it" $Kept.IconText "IC"
    Check "under the instance's own name" $Kept.Name $FakeName

    # 10. Two changes in one visit: the menu comes back after the first one, and
    # the second keeps what the first did - the letters AND the colours.
    $null = Invoke-Icons @("$Pick", "2", "abc", "3", "2")
    $Saved = Get-Recipe
    Check "two changes in one run: the letters are the typed ones" $Saved.IconText "ABC"
    Check "two changes in one run: and the colours are the picked ones" "$($Saved.IconTop) $($Saved.IconBottom)" "#3B82F6 #2563EB"

    # 11. The way in: the instance is asked once, the menu holds both commands,
    # and it is drawn again once the command it handed over to is done. Answers:
    # the instance, "icon", "By Default" (which changes something), Escape on
    # the icon menu, Escape here. The reload is asked on this path too - it once
    # lived only in a command run on its own - and the file Terminal watches is
    # the proof, when it is there.
    $Settings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $Before = if (Test-Path $Settings) { (Get-Item $Settings).LastWriteTime } else { $null }

    $Out = Invoke-Theme @("$Pick", "1", "1", "0", "0")

    Check "theme offers both commands" (@($Out | Where-Object { "$_".Contains("what the whole terminal is written in") }).Count -gt 0) $true
    Check "hands over to the icon command" (@($Out | Where-Object { "$_".Contains("Icon of '$FakeName'") }).Count -gt 0) $true
    # Twice: once to start with, and once more when the theme menu is left -
    # Escape goes back up to the list.
    Check "and the list comes back when the menu is left" (@($Out | Where-Object { "$_".Contains("Our Instances") }).Count) 2
    Check "and the menu comes back when it is done" (@($Out | Where-Object { "$_".Contains("Theme of '$FakeName'") }).Count) 2
    if ($Before) {
        Check "and Terminal was asked to look again, through the menu too" `
            ((Get-Item $Settings).LastWriteTime -gt $Before) $true
    }
} finally {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
