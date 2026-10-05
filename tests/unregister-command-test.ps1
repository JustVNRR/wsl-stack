# Drives the destructive command - unregister - the way a script would: the
# numbered prompt, answers on standard input, no console anywhere, and the
# same stand-in wsl.exe as the other suites. USERPROFILE, LOCALAPPDATA and
# APPDATA are redirected into the test's own folder: the Windows Terminal
# settings, the fragments and Docker's settings file the housekeeping touches
# are the test's own fakes, never the real ones. The instance it removes
# exists for the length of each scenario: a registry key of its own, and a
# folder carrying the marker, under the commands' root - only the suite's own
# paths are ever written there and they are all taken back out at the end.
#
# What is checked: the confirmation refuses anything but the exact name, case
# included, and a cancelled run touches nothing; a failed archive stops the
# removal before anything is destroyed; and a full run stops the instance
# then unregisters it by name, removes the install folder, prunes the ghost
# settings entry while keeping the live and the foreign ones, removes our
# appearance fragments - its own, and a stale one pointing at nothing - while
# keeping a live one, and takes the name out of Docker's integrated list -
# backups included.
#
# It needs no instance, no console and no Docker Desktop.
#
# Usage:  pwsh -NoProfile -File tests\unregister-command-test.ps1

$ErrorActionPreference = "Stop"

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("unregister-command-test-" + [Guid]::NewGuid().ToString("N"))
$FakeName = "unregister-command-test"
$Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{5d2e3f40-7b8c-4d9e-af01-2b3c4d5e6f70}"
$Log = Join-Path $Tmp "wsl-calls.log"

# The commands work under one root: D:\WSL when there is a D:, the profile
# otherwise - the rule the family follows, so the suite follows it too and its
# expectations land where the children write. The root may already exist - a
# runner's own, an earlier step's - so nothing but the suite's own paths below
# is ever touched.
$env:USERPROFILE = $Tmp
$env:LOCALAPPDATA = Join-Path $Tmp "LocalAppData"
$env:APPDATA = Join-Path $Tmp "AppData"
New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
$Root = if (Test-Path "D:\") { "D:\WSL" } else { Join-Path $Tmp "WSL" }
# The fake instance lives where a real one would - under the root - so the
# archive an unregister-with-a-copy takes lands where a real machine would
# put it.
$FakeFolder = Join-Path $Root $FakeName

# The paths this suite writes, and takes back out in the end - names no real
# machine carries. One of them already there means a run was stopped half way:
# said, not cleaned - it is nobody else's to remove.
$OurPaths = @(
    (Join-Path $Root $FakeName),
    (Join-Path $Root "archives\$FakeName")
)
$InTheWay = @($OurPaths | Where-Object { Test-Path $_ })
if ($InTheWay.Count -gt 0) {
    Write-Output "already there under ${Root}:"
    $InTheWay | ForEach-Object { Write-Output "  $_" }
    throw "a run of this suite was stopped half way - remove those paths, then run it again"
}

# The Windows-side world the housekeeping reaches for: the user's Terminal
# settings, the WSL fragments, ours, and Docker's file - all under the
# redirected folders.
$SettingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$WslFragmentDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
$OurFragmentDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack"
$DockerFile = Join-Path $env:APPDATA "Docker\settings-store.json"
$ArchiveDir = Join-Path $Root "archives\$FakeName"

# Two guids: one a live distro still carries (its fragment is on disk), one of
# a distro that is gone - the settings entry and our fragment carrying it are
# the ghosts.
$LiveGuid = "{aaaaaaaa-1111-2222-3333-444444444444}"
$DeadGuid = "{dddddddd-1111-2222-3333-444444444444}"

# For Get-Distros and the marker test: the list the commands themselves build.
. (Join-Path $PSScriptRoot "..\scripts\instance.ps1")

$UnregisterScript = Join-Path $PSScriptRoot "..\scripts\WslCommands\unregister.ps1"
# Child processes follow the engine this suite runs under, so a pass under 7
# tests the scripts under 7.
$Engine = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }

# The stand-in, ahead of any wsl.exe for every child this suite starts: a real
# binary of that name, compiled here from tests\fake-wsl\wsl.cs - the scripts
# call `wsl.exe` with its extension, so only a binary answers to it, never a
# script.
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

# The command is driven through invoke-command.ps1: a fresh pwsh has no
# classes, and the command's typed -Manager parameter is settled before the
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

# What the stand-in was asked, in order - its log, the arguments line by line.
# The raw command lines stay out: the checks below speak of arguments.
function Get-Calls {
    if (-not (Test-Path $Log)) { return @() }
    return @(Get-Content $Log | Where-Object { $_ -and $_ -notlike "raw:*" })
}

# What a step above should have written, read back - or an empty string, so a
# missing file fails its check instead of stopping the suite.
function Get-FileText {
    param([string]$Path)
    if (Test-Path $Path) { return (Get-Content $Path -Raw) }
    return ""
}

# Everything one scenario consumes: the registered instance, its folder, and
# the Windows-side files the housekeeping works on. Rebuilt before every
# scenario, since the full runs destroy what they touch.
function Reset-World {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $Key -Force | Out-Null
    Set-ItemProperty -Path $Key -Name DistributionName -Value $FakeName
    Set-ItemProperty -Path $Key -Name BasePath -Value $FakeFolder

    New-Item -ItemType Directory -Path $FakeFolder -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $FakeFolder ".wsl-stack") -Force | Out-Null
    Set-Content -Path (Join-Path $FakeFolder "ext4.vhdx") -Value "fake-disk" -NoNewline
    Set-Content -Path (Join-Path $FakeFolder "terminal-icon.png") -Value "fake-icon" -NoNewline
    @{
        Name          = $FakeName
        Font          = "MesloLGS NF"
        ColorScheme   = "One Half Dark"
        IconFrom      = (Join-Path $FakeFolder "terminal-icon.png")
        IconText      = "UR"
        IconTop       = "#111111"
        IconBottom    = "#222222"
        IconTextColor = "#FFFFFF"
    } | ConvertTo-Json | Set-Content -Path (Join-Path $FakeFolder "instance.json") -Encoding Utf8

    # The Terminal world: one live WSL fragment (its guid is the live one),
    # and in the settings list: this instance's ghost entry (dead guid), this
    # instance's live one, another distro's dead one, and a user entry.
    New-Item -ItemType Directory -Path $WslFragmentDir -Force | Out-Null
    @{ profiles = @( @{ name = "live-distro"; guid = $LiveGuid } ) } |
        ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $WslFragmentDir "live.json") -Encoding Utf8
    New-Item -ItemType Directory -Path (Split-Path $SettingsPath -Parent) -Force | Out-Null
    @{
        profiles = @{
            list = @(
                @{ name = $FakeName; source = "Microsoft.WSL"; guid = $DeadGuid },
                @{ name = $FakeName; source = "Microsoft.WSL"; guid = $LiveGuid },
                @{ name = "other-distro"; source = "Microsoft.WSL"; guid = $DeadGuid },
                @{ name = "defaults"; source = $null }
            )
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsPath -Encoding Utf8
    Remove-Item "$SettingsPath.bak" -Force -ErrorAction SilentlyContinue

    # Our fragments: the instance's own, a live one, and a stale one whose
    # target no longer exists.
    New-Item -ItemType Directory -Path $OurFragmentDir -Force | Out-Null
    @{ profiles = @( @{ updates = $LiveGuid; font = @{ face = "Consolas" } } ) } |
        ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $OurFragmentDir "keep.json") -Encoding Utf8
    @{ profiles = @( @{ updates = $DeadGuid; font = @{ face = "Consolas" } } ) } |
        ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $OurFragmentDir "stale.json") -Encoding Utf8
    @{ profiles = @( @{ updates = $LiveGuid; font = @{ face = "Consolas" } } ) } |
        ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $OurFragmentDir "$FakeName.json") -Encoding Utf8

    # Docker's list, with the instance among the integrated ones.
    New-Item -ItemType Directory -Path (Split-Path $DockerFile -Parent) -Force | Out-Null
    @{ IntegratedWslDistros = @("other-distro", $FakeName) } |
        ConvertTo-Json -Depth 5 | Set-Content -Path $DockerFile -Encoding Utf8
    Remove-Item "$DockerFile.bak" -Force -ErrorAction SilentlyContinue

    Remove-Item $Log -Force -ErrorAction SilentlyContinue
}

try {
    Reset-World

    # Which number our instance is in the list the command draws - worked out
    # with the same code, so the answer is right whatever else is installed.
    $All = @(Get-Distros | Where-Object { Test-TemplateInstance -Folder $_.Path } | Sort-Object Name)
    $Pick = [array]::IndexOf(@($All.Name), $FakeName) + 1
    Check "the test's instance is in the list" ($Pick -ge 1) $true

    # 1. The confirmation wants the exact name: a name that differs only by
    # case is not it (-cne), and a cancelled run touches nothing at all.
    Reset-World
    $Out = Invoke-Child -Script $UnregisterScript -Answers @("$Pick", "UNREGISTER-COMMAND-TEST")
    Check "a name that differs by case is refused" (@($Out | Where-Object { "$_".Contains("Operation cancelled. No data was modified.") }).Count -gt 0) $true
    Check "and nothing is terminated" (@(Get-Calls | Where-Object { $_ -like "--terminate*" }).Count) 0
    Check "and nothing is unregistered" (@(Get-Calls | Where-Object { $_ -like "--unregister*" }).Count) 0
    Check "and the folder is still there" (Test-Path $FakeFolder) $true
    Check "and the settings were not touched" (Test-Path "$SettingsPath.bak") $false
    Check "and ends on zero" $script:ChildExit 0

    # An empty answer is the same way out.
    Reset-World
    $Out = Invoke-Child -Script $UnregisterScript -Answers @("$Pick", "")
    Check "an empty answer cancels it too" (@($Out | Where-Object { "$_".Contains("Operation cancelled. No data was modified.") }).Count -gt 0) $true
    Check "and nothing is unregistered" (@(Get-Calls | Where-Object { $_ -like "--unregister*" }).Count) 0

    # 2. A failed archive stops everything: the last moment to take a copy did
    # not happen, so nothing is destroyed.
    Reset-World
    $env:FAKE_WSL_FAIL = "--export"
    $Out = Invoke-Child -Script $UnregisterScript -Answers @("$Pick", "$FakeName", "y")
    Remove-Item Env:FAKE_WSL_FAIL -ErrorAction SilentlyContinue
    Check "a failed archive stops the removal" (@($Out | Where-Object { "$_".Contains("The archive did not complete") }).Count -gt 0) $true
    Check "and nothing is unregistered" (@(Get-Calls | Where-Object { $_ -like "--unregister*" }).Count) 0
    Check "and nothing is terminated" (@(Get-Calls | Where-Object { $_ -like "--terminate*" }).Count) 0
    Check "and the folder is untouched" (Test-Path $FakeFolder) $true
    Check "and the settings were not touched" (Test-Path "$SettingsPath.bak") $false
    Check "and ends on one" $script:ChildExit 1

    # 3. A full run, archive first: the archive lands before anything is
    # destroyed, then the removal - stop, unregister, folder, Terminal and
    # Docker housekeeping.
    Reset-World
    $Out = Invoke-Child -Script $UnregisterScript -Answers @("$Pick", "$FakeName", "y")
    $Calls = Get-Calls

    $ArchiveTar = Join-Path $ArchiveDir "$FakeName.tar.gz"
    Check "the archive is written first, where the family puts them" (@($Calls | Where-Object { $_ -eq "--export $FakeName $ArchiveTar --format tar.gz" }).Count) 1
    Check "and the export comes before the unregister" ([array]::IndexOf($Calls, "--export $FakeName $ArchiveTar --format tar.gz") -lt [array]::IndexOf($Calls, "--unregister $FakeName")) $true
    Check "and the archive carries the look" (Test-Path (Join-Path $ArchiveDir "instance.json")) $true
    Check "and the icon beside it" (Test-Path (Join-Path $ArchiveDir "terminal-icon.png")) $true
    Check "the instance is stopped first" (@($Calls | Where-Object { $_ -eq "--terminate $FakeName" }).Count) 1
    Check "and unregistered by name" (@($Calls | Where-Object { $_ -eq "--unregister $FakeName" }).Count) 1
    Check "the stop comes before the unregister" ([array]::IndexOf($Calls, "--terminate $FakeName") -lt [array]::IndexOf($Calls, "--unregister $FakeName")) $true
    Check "and the install folder is gone" (Test-Path $FakeFolder) $false

    $SettingsAfter = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    $Kept = @($SettingsAfter.profiles.list)
    Check "the ghost settings entry is pruned" ($Kept.Count) 3
    Check "the live entry of the same name stays" (@($Kept | Where-Object { $_.name -eq $FakeName -and $_.guid -eq $LiveGuid }).Count) 1
    Check "a foreign distro's dead entry is not its business" (@($Kept | Where-Object { $_.name -eq "other-distro" }).Count) 1
    Check "the user's own entry stays" (@($Kept | Where-Object { $_.name -eq "defaults" }).Count) 1
    $BakRaw = Get-FileText "$SettingsPath.bak"
    Check "and a backup of the settings was taken, holding the four" "$(if ($BakRaw) { @(($BakRaw | ConvertFrom-Json).profiles.list).Count })" 4

    Check "our own fragment is removed" (Test-Path (Join-Path $OurFragmentDir "$FakeName.json")) $false
    Check "and the stale one pointing at nothing goes too" (Test-Path (Join-Path $OurFragmentDir "stale.json")) $false
    Check "but the one whose target is alive stays" (Test-Path (Join-Path $OurFragmentDir "keep.json")) $true

    $DockerAfter = Get-Content $DockerFile -Raw | ConvertFrom-Json
    Check "the name leaves Docker's integrated list" (@($DockerAfter.IntegratedWslDistros) -contains $FakeName) $false
    Check "and the rest of the list stays" (@($DockerAfter.IntegratedWslDistros) -contains "other-distro") $true
    Check "and Docker's file got a backup too" (Test-Path "$DockerFile.bak") $true

    Check "and the removal is reported" (@($Out | Where-Object { "$_".Contains("WSL Stack Instance Removed!") }).Count -gt 0) $true
    Check "with the pruned ghost said" (@($Out | Where-Object { "$_".Contains("pruned 1 ghost '$FakeName'") }).Count -gt 0) $true
    Check "and the fragment count" (@($Out | Where-Object { "$_".Contains("removed 2 appearance file(s)") }).Count -gt 0) $true
    Check "and Docker's line said" (@($Out | Where-Object { "$_".Contains("'$FakeName' removed from the integrated distros") }).Count -gt 0) $true
    Check "and ends on zero" $script:ChildExit 0

    # 4. The same without the archive: nothing is exported, everything else
    # happens the same way.
    Reset-World
    $Out = Invoke-Child -Script $UnregisterScript -Answers @("$Pick", "$FakeName", "n")
    Check "answered n: nothing is exported" (@(Get-Calls | Where-Object { $_ -like "--export*" }).Count) 0
    Check "and the instance still goes" (@(Get-Calls | Where-Object { $_ -eq "--unregister $FakeName" }).Count) 1
    Check "and the ghost is pruned just the same" (@((Get-Content $SettingsPath -Raw | ConvertFrom-Json).profiles.list).Count) 3
    Check "and ends on zero" $script:ChildExit 0

    # 5. An empty machine: said, not asked about.
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    $Out = Invoke-Child -Script $UnregisterScript -Answers @("")
    Check "an empty machine has nothing to remove" (@($Out | Where-Object { "$_".Contains("Nothing to remove") }).Count -gt 0) $true
    Check "and ends on one" $script:ChildExit 1
} finally {
    Remove-Item $Key -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($Path in $OurPaths) {
        Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    }
    # The archives folder itself only when this run left it empty - a root
    # that had one, or an entry in it, keeps it.
    $ArchivesFolder = Join-Path $Root "archives"
    if ((Test-Path $ArchivesFolder) -and (@(Get-ChildItem $ArchivesFolder -Force -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -Force $ArchivesFolder -ErrorAction SilentlyContinue
    }
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
