# Drives the lifecycle commands - start, stop, restart, shell, shrink, list -
# the way a script would: the numbered prompt, answers on standard input, no
# console anywhere, and a stand-in wsl.exe ahead on the PATH - built from
# tests\fake-wsl\wsl.cs, logging every call and answering from its own log: a
# distribution counts as running once a boot command has gone through.
#
# The instance it works on exists for the length of the test: a registry key of
# its own, a folder carrying the marker, and a name of its own. The key is
# taken back out at the end. Nothing real is started or stopped: what is
# checked is the command emitted, its order, and what is said.
#
# What is checked: for `start`, the boot names the instance picked, the news
# is said, and cancelling boots nothing; for `restart`, the stop comes before
# the boot; for `stop`, the terminate is asked only after the confirmation;
# for `shell`, the session is asked by name; for `shrink`, the compact, and
# the restart only when it was running; for `list`, what the machine says -
# stopped or running.
#
# It needs no instance, no console and no Docker Desktop.
#
# Usage:  pwsh -NoProfile -File tests\lifecycle-command-test.ps1

$ErrorActionPreference = "Stop"

# For Get-Distros and the marker test: the list the command itself builds.
. (Join-Path $PSScriptRoot "..\scripts\instance.ps1")

$StartScript = Join-Path $PSScriptRoot "..\scripts\start.ps1"
$RestartScript = Join-Path $PSScriptRoot "..\scripts\restart.ps1"
$StopScript = Join-Path $PSScriptRoot "..\scripts\stop.ps1"
$ShellScript = Join-Path $PSScriptRoot "..\scripts\shell.ps1"
$ShrinkScript = Join-Path $PSScriptRoot "..\scripts\shrink.ps1"
$ListScript = Join-Path $PSScriptRoot "..\scripts\list.ps1"
# Child processes follow the engine this suite runs under, so a pass under 7
# tests the scripts under 7.
$Engine = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("lifecycle-command-test-" + [Guid]::NewGuid().ToString("N"))
$FakeName = "lifecycle-command-test"
$FakeFolder = Join-Path $Tmp "instance"
$Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{2f9f0a4e-58b1-4a3c-9d2e-0c1b2a3d4e5f}"
$Log = Join-Path $Tmp "wsl-calls.log"

# The stand-in, ahead of any wsl.exe for every child this suite starts: a real
# binary of that name, compiled here from tests\fake-wsl\wsl.cs - the scripts
# call `wsl.exe` with its extension, so only a binary answers to it, never a
# script. Its answers come from the log it writes: an empty log is a machine
# where nothing runs, a boot line makes the instance a running one.
$FakeDir = Join-Path $Tmp "fake-wsl"
New-Item -ItemType Directory -Path $FakeDir -Force | Out-Null
$Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $Csc)) { $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
& $Csc /nologo /out:"$(Join-Path $FakeDir 'wsl.exe')" (Join-Path $PSScriptRoot "fake-wsl\wsl.cs")
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $FakeDir "wsl.exe"))) {
    throw "the stand-in wsl.exe could not be compiled"
}
$env:PATH = $FakeDir + [IO.Path]::PathSeparator + $env:PATH
$env:FAKE_WSL_LOG = $Log
$env:FAKE_WSL_INSTANCE = $FakeName

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

# The child's own exit code, beside its output: a refusal is a result too.
$script:ChildExit = 0

# The commands are driven through invoke-command.ps1: a fresh pwsh has no
# classes, and a command's typed -Manager parameter is settled before the
# command runs - the shared half must be loaded first, as wsl.ps1 does.
$Invoker = Join-Path $PSScriptRoot "invoke-command.ps1"

function Invoke-Child {
    param([string]$Script, [string[]]$Answers)

    $Preference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Lines = $Answers | & $Engine -NoProfile -File $Invoker -Script $Script 2>&1
        $script:ChildExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $Preference
    }
    return $Lines
}

# What the stand-in was asked, in order - its log, line by line.
function Get-Calls {
    if (-not (Test-Path $Log)) { return @() }
    return @(Get-Content $Log | Where-Object { $_ })
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

    # 1. start: the boot names the instance picked, and the command says so.
    # The log starts empty, so nothing runs and the instance is there to pick.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $StartScript -Answers @("$Pick")
    Check "start boots the instance picked, by name" `
        (@(Get-Calls | Where-Object { $_ -eq "-d $FakeName --exec /bin/true" }).Count) 1
    Check "and says it is running" (@($Out | Where-Object { "$_".Contains("'$FakeName' is running") }).Count -gt 0) $true
    Check "and ends on zero" $script:ChildExit 0

    # 2. Escape is not a boot: the number 0 is the way out, and nothing is
    # asked of WSL.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $StartScript -Answers @("0")
    Check "cancelling boots nothing" (@(Get-Calls | Where-Object { $_ -like "*--exec*" }).Count) 0
    Check "and says nothing was modified" (@($Out | Where-Object { "$_".Contains("Operation cancelled by user") }).Count -gt 0) $true
    Check "and ends on zero" $script:ChildExit 0

    # 3. restart: the stop comes first, the boot after it, and the news last.
    # A boot in the log is what an earlier start would have left; the instance
    # is one of the running ones, so it is there to pick.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    Add-Content -Path $Log -Value "-d $FakeName --exec /bin/true"
    $Out = Invoke-Child -Script $RestartScript -Answers @("$Pick", "")
    $Calls = Get-Calls
    Check "restart stops the instance first" (@($Calls | Where-Object { $_ -eq "--terminate $FakeName" }).Count) 1
    Check "and boots it after the stop" `
        (([array]::IndexOf($Calls, "--terminate $FakeName")) -lt ([array]::LastIndexOf($Calls, "-d $FakeName --exec /bin/true"))) $true
    Check "and says it is running again" (@($Out | Where-Object { "$_".Contains("'$FakeName' is running again") }).Count -gt 0) $true
    Check "and ends on zero" $script:ChildExit 0

    # 4. stop: the instance is one of the running ones, the confirmation is
    # taken, and the terminate names it. An empty answer is a yes - only an
    # "n" calls it off, and then nothing is asked of WSL.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    Add-Content -Path $Log -Value "-d $FakeName --exec /bin/true"
    $Out = Invoke-Child -Script $StopScript -Answers @("$Pick", "")
    Check "stop terminates the instance picked" (@(Get-Calls | Where-Object { $_ -eq "--terminate $FakeName" }).Count) 1
    Check "and says it is stopped" (@($Out | Where-Object { "$_".Contains("'$FakeName' is stopped") }).Count -gt 0) $true
    Check "and ends on zero" $script:ChildExit 0

    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    Add-Content -Path $Log -Value "-d $FakeName --exec /bin/true"
    $Out = Invoke-Child -Script $StopScript -Answers @("$Pick", "n")
    Check "answered n: nothing is terminated" (@(Get-Calls | Where-Object { $_ -like "*--terminate*" }).Count) 0
    Check "and nothing was modified" (@($Out | Where-Object { "$_".Contains("Operation cancelled by user") }).Count -gt 0) $true

    # With nothing running there is nothing to stop: said, not opened.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $StopScript -Answers @("")
    Check "nothing running -> stop says so" (@($Out | Where-Object { "$_".Contains("No instance is running") }).Count -gt 0) $true
    Check "and ends on one" $script:ChildExit 1

    # 5. shell: the session is asked of WSL by name, from the instance's home,
    # and a stopped one is noted - WSL starts it on the way in. Nothing is
    # captured from the session: its code is handed back as it came.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $ShellScript -Answers @("$Pick")
    Check "shell opens a session on the instance picked" (@(Get-Calls | Where-Object { $_ -eq "-d $FakeName --cd ~" }).Count) 1
    # wsl.exe parses its own command line and does not strip quotes: a quoted
    # name stops matching (seen on a real machine - the same name unquoted
    # works). The joined arguments above cannot show that; the raw line can.
    Check "and the raw command line is on record" (@(Get-Calls | Where-Object { $_ -like "raw:*" }).Count -gt 0) $true
    Check "and the name reaches wsl unquoted" `
        (@(Get-Calls | Where-Object { $_ -like "raw:*" -and $_ -like "*`"$FakeName`"*" }).Count) 0
    Check "and says what it is doing" (@($Out | Where-Object { "$_".Contains("Opening a shell in '$FakeName'") }).Count -gt 0) $true
    Check "and notes a stopped instance" (@($Out | Where-Object { "$_".Contains("It was stopped") }).Count -gt 0) $true
    Check "and hands the session's code over" $script:ChildExit 0

    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    Add-Content -Path $Log -Value "-d $FakeName --exec /bin/true"
    $Out = Invoke-Child -Script $ShellScript -Answers @("$Pick")
    Check "a running instance is not noted as stopped" (@($Out | Where-Object { "$_".Contains("It was stopped") }).Count) 0

    # 6. shrink: one command, in place - and the instance comes back up only
    # if it was up. The archive question is answered no: a yes takes the
    # archive path, another suite's country.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $ShrinkScript -Answers @("$Pick", "n")
    Check "shrink compacts the instance picked" (@(Get-Calls | Where-Object { $_ -eq "--manage $FakeName --compact" }).Count) 1
    Check "and says it is compacted" (@($Out | Where-Object { "$_".Contains("'$FakeName' compacted") }).Count -gt 0) $true
    Check "and a stopped one is not started" (@(Get-Calls | Where-Object { $_ -like "*--exec*" }).Count) 0
    Check "and ends on zero" $script:ChildExit 0

    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    Add-Content -Path $Log -Value "-d $FakeName --exec /bin/true"
    $Out = Invoke-Child -Script $ShrinkScript -Answers @("$Pick", "n")
    $Calls = Get-Calls
    Check "a running one is started again after the compact" `
        (([array]::IndexOf($Calls, "--manage $FakeName --compact")) -lt ([array]::LastIndexOf($Calls, "-d $FakeName --exec /bin/true"))) $true
    Check "and says it is running again" (@($Out | Where-Object { "$_".Contains("'$FakeName' is running again") }).Count -gt 0) $true

    # 7. list: the row says what the machine says, stopped or running - and an
    # empty machine is an answer with its own code, not a table over nothing.
    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $ListScript -Answers @("")
    Check "list shows the instance as stopped" `
        (@($Out | Where-Object { "$_" -match [regex]::Escape($FakeName) -and "$_" -match "stopped" }).Count -gt 0) $true
    Check "and ends on zero" $script:ChildExit 0

    Remove-Item $Log -Force -ErrorAction SilentlyContinue
    Add-Content -Path $Log -Value "-d $FakeName --exec /bin/true"
    $Out = Invoke-Child -Script $ListScript -Answers @("")
    Check "list shows a running one as running" `
        (@($Out | Where-Object { "$_" -match [regex]::Escape($FakeName) -and "$_" -match "running" }).Count -gt 0) $true

    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $ListScript -Answers @("")
    Check "an empty machine is said, not printed over" `
        (@($Out | Where-Object { "$_".Contains("No instance of this template is registered") }).Count -gt 0) $true
    Check "and ends on one" $script:ChildExit 1
} finally {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
