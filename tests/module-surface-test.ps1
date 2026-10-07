# The module's public surface: the manifest's FunctionsToExport list, and the
# two lists it has to agree with.
#
# What is not listed there is invisible to the scripts, however nested the file
# that defines it (measured: a command and the window both answered
# "Get-InstanceFamily is not recognized" until the list learned its name).
# This suite holds the three together - what the module defines, what the
# manifest exports, what the scripts call - so the next name that forgets its
# line fails here instead of in a click.
#
#   pwsh -File tests\module-surface-test.ps1
#
$ErrorActionPreference = "Stop"

# From this file's own folder, one level up: tests\ sits at the root.
$Root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $Root "src\windows\WslStack\WslStack.psd1") -Force

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

# The manifest's own answer, asked of the loaded module: the list and what it
# resolves to cannot drift apart here.
$Exported = @((Get-Module WslStack).ExportedFunctions.Keys | Sort-Object)

# Everything the module's files define.
$Defined = @()
foreach ($File in Get-ChildItem (Join-Path $Root "src\windows\WslStack\*.psm1")) {
    $Defined += @(Select-String -Path $File.FullName -Pattern '^function ([A-Za-z0-9-]+)' |
        ForEach-Object { $_.Matches[0].Groups[1].Value })
}
$Defined = @($Defined | Sort-Object -Unique)

# Every name a script calls - the commands, the window with its controllers,
# runners and theme, and the entry itself. A function DEFINED in one of those
# files is not the manifest's business: only the names that reach into the
# module are.
$Scripts = @(Get-ChildItem (Join-Path $Root "src\windows\WslCommands\*.ps1")) +
           @(Get-ChildItem (Join-Path $Root "src\windows\gui") -Recurse -Filter *.ps1) +
           @(Get-ChildItem (Join-Path $Root "wsl.ps1"))
$Called = @()
foreach ($File in $Scripts) {
    # -AllMatches: without it Select-String answers the FIRST name of each
    # line only, and a call sitting after another one on the same line is
    # invisible - measured the hard way, it made this very check blind.
    $Called += @(Select-String -Path $File.FullName -Pattern '\b([A-Z][a-zA-Z]+-[A-Za-z0-9]+)\b' -AllMatches |
        ForEach-Object { $_.Matches | ForEach-Object { $_.Groups[1].Value } })
}
$Called = @($Called | Sort-Object -Unique)

# A function the module defines, a script calls, and the manifest does not
# list: the scripts answer "not recognized" the moment they reach it.
$Missing = @($Defined | Where-Object { $_ -notin $Exported -and $_ -in $Called })
Check "no function is called without a line in FunctionsToExport" ($Missing -join ", ") ""

# A listed name no file defines: the surface promises what does not exist.
$Ghost = @($Exported | Where-Object { $_ -notin $Defined })
Check "every exported name is defined by a module file" ($Ghost -join ", ") ""

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
