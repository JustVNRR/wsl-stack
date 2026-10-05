# ==============================================================================
# WHICH INSTANCES ARE OURS, AND WHAT WINDOWS KNOWS ABOUT THEM
# ==============================================================================
# The machine holds distributions that are not ours - Docker Desktop's own, or
# a colleague's. So every instance we create carries a marker in its own folder,
# next to ext4.vhdx:
#
#   <install folder>\.wsl-stack
#
# It is written by the three commands that create an instance - build, restore,
# duplicate - and looked for by every command that lists instances; nothing
# else writes it.
#
# Two more things live on the Windows side, and both are lost silently:
#   the look   icon, font, colour scheme - a Windows Terminal fragment that
#              targets the guid of the WSL profile; a re-import gives a NEW
#              guid, and the fragment stops matching.
#   Docker     whether Docker Desktop knows the instance (its own settings
#              file, by name).
#
# Neither is inside the tar, so an archive captures them beside it
# (instance.json, terminal-icon.png) and re-applies them after an import.
#
# This file defines functions; it is not a command.
# ==============================================================================

# ---------------------------------------------------------------------------
# THE MODEL
# ---------------------------------------------------------------------------
# The classes, in the order they must be read - the same walk scripts\instance.ps1
# takes for the scripts: a class settles the types it names the moment its file
# is parsed, and the families here build instances of them. Dot-sourcing class
# files lands them in the runspace's type table, so the session's own classes
# are these very types, not copies.
$ClassLibs = @("WslState.ps1", "WslTheme.ps1", "WslPack.ps1", "WslInstance.ps1", "WslPackCatalog.ps1", "WslInstanceManager.ps1")
$ClassesDir = Join-Path $PSScriptRoot "..\WslModel"
foreach ($ClassLib in $ClassLibs) {
    $ClassPath = Join-Path $ClassesDir $ClassLib
    if (-not (Test-Path $ClassPath)) {
        throw "scripts\WslModel\$ClassLib is missing - the scripts\ folder is incomplete."
    }
    . $ClassPath
}


# The marker's name, kept here so that one file knows it and the others ask.
# It is the repository's own name, like the Windows Terminal fragments folder,
# so there is one string to remember in the whole project.
$MarkerName = ".wsl-stack"

# Is this folder an instance of ours? A folder name proves nothing - it is the
# marker file, and only it, that answers.
function Test-TemplateInstance {
    param([string]$Folder)

    if (-not $Folder) { return $false }
    return (Test-Path (Join-Path $Folder $MarkerName))
}

# Mark an instance as ours. Called right after an import, while the folder is
# fresh - the point is that the mark is there before anything else can go
# wrong, so the other commands see the instance even if a later step fails.
function New-InstanceMarker {
    param([string]$Folder, [string]$By)

    if (-not (Test-Path $Folder)) { return }

    # [ordered]: a hashtable would print its keys in a different order on every
    # run, and a file whose lines move is a file nobody diffs twice.
    $Marker = [ordered]@{
        template = "wsl-stack"
        created  = (Get-Date).ToString("yyyy-MM-dd")
        by       = $By
    }

    $Json = ($Marker | ConvertTo-Json) -replace "`r`n", "`n"
    # Written byte-order-mark-free, like Docker Desktop's settings file:
    # PowerShell's -Encoding Utf8 prepends one that the next reader is not
    # expecting.
    [System.IO.File]::WriteAllText((Join-Path $Folder $MarkerName), $Json,
        (New-Object System.Text.UTF8Encoding($false)))
}

# Is a font face installed for this user or for the machine? Windows stores
# them as registry values whose names carry the face ("MesloLGS NF (TrueType)").
function Test-FontInstalled {
    param([string]$Face)

    if (-not $Face) { return $true }
    foreach ($Root in @("HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
                        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")) {
        $Key = Get-ItemProperty -Path $Root -ErrorAction SilentlyContinue
        if (-not $Key) { continue }
        foreach ($Property in $Key.psobject.properties) {
            if ($Property.Name -like "*$Face*") { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# THE LOOK OF AN INSTANCE
# ---------------------------------------------------------------------------
# One file per instance, in its own folder: instance.json - the name, the font,
# the colour scheme, where the icon is and what it is made of, whether Docker
# Desktop knows it. An archive carries that very file, so its shape is decided
# once here.
#
#   {
#       "Name":  "distro",
#       "Font":  "MesloLGS NF",
#       "ColorScheme":  "One Half Dark",
#       "IconFrom":  "D:\\WSL\\distro\\terminal-icon.png",
#       "IconText":  "DI",
#       "IconTop":  "#148F8A",
#       "IconBottom":  "#0E6B67",
#       "IconTextColor":  "#FFFFFF",
#       "Docker":  "yes"
#   }
#
# The four Icon* fields are the recipe: they let one change keep the others -
# other letters, same colours. An image of your own has no recipe, so they are
# absent.

# Where an instance lives, asked of the registry rather than guessed: the folder
# holding its disk. $null when nothing registered here carries that name.
function Get-InstanceFolder {
    param([string]$Name)

    $Props = Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DistributionName -eq $Name } |
        Select-Object -First 1
    if (-not $Props) { return $null }
    return ($Props.BasePath -replace '^\\\\\?\\', '').TrimEnd('\')
}

# Windows' own list of what is registered, where every decision to erase comes
# from. Its failure is kept apart from its answer: a list that cannot be read
# is not an empty machine. A missing key is not a failure - it is WSL never
# having registered anything here.
function Get-RegisteredDistros {
    $Lxss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (-not (Test-Path $Lxss)) { return @() }

    $Found = @()
    foreach ($Key in Get-ChildItem $Lxss -ErrorAction Stop) {
        $Props = Get-ItemProperty $Key.PSPath -ErrorAction Stop
        if ($Props.DistributionName) {
            $Found += [PSCustomObject]@{
                Name = $Props.DistributionName
                Path = ($Props.BasePath -replace '^\\\\\?\\', '').TrimEnd('\')
            }
        }
    }
    return @($Found)
}

# The file as the instance has it, or $null when it has none yet. A file that
# cannot be read is not a reason to stop: it is treated as absent, and the next
# write replaces it.
function Get-InstanceLook {
    param([string]$Name)

    $Folder = Get-InstanceFolder -Name $Name
    if (-not $Folder) { return $null }
    $File = Join-Path $Folder "instance.json"
    if (-not (Test-Path $File)) { return $null }
    try { return (Get-Content $File -Raw | ConvertFrom-Json) } catch { return $null }
}

# What an icon is made of, read off a look: a table of parameters, ready for the
# drawing script. Empty when the look carries no recipe - an image of your own is
# not a drawing, and an instance built before any of this existed has none.
function Get-IconRecipe {
    param([PSCustomObject]$Look, [string]$Name)

    if (-not $Look -and $Name) { $Look = Get-InstanceLook -Name $Name }
    if (-not $Look) { return @{} }
    if (-not ($Look.PSObject.Properties.Name -contains "IconText")) { return @{} }
    return @{
        Text      = $Look.IconText
        Top       = $Look.IconTop
        Bottom    = $Look.IconBottom
        TextColor = $Look.IconTextColor
    }
}

# The look, the icon's recipe beside it, in the order the file is written. The
# theme says what it looks like - this machine now, unless a restore or a copy
# hands over the theme an archive held - and Docker is answered the same way.
# The icon path is always the instance's own: the picture is copied into its
# folder either way.
function New-InstanceLook {
    param(
        [string]$Name,
        [WslTheme]$Theme,
        [hashtable]$Icon = @{},
        [string]$Docker
    )

    if (-not $Theme) { $Theme = Get-InstanceAppearance -Name $Name }
    if (-not $Docker) { $Docker = Get-DockerState -Name $Name }

    $Look = [ordered]@{
        Name        = $Name
        Font        = $Theme.FontName
        ColorScheme = $Theme.ColorScheme
        IconFrom    = $Theme.IconPath
    }
    if ($Icon.Text) {
        $Look.IconText      = $Icon.Text
        $Look.IconTop       = $Icon.Top
        $Look.IconBottom    = $Icon.Bottom
        $Look.IconTextColor = $Icon.TextColor
    }
    if ($Docker) { $Look.Docker = $Docker }
    return [PSCustomObject]$Look
}

# Write it where it belongs: in the instance's own folder.
function Set-InstanceLook {
    param([string]$InstallPath, [PSCustomObject]$Look)

    $Look | ConvertTo-Json | Set-Content -Path (Join-Path $InstallPath "instance.json") -Encoding Utf8
}

# Ask Windows Terminal to re-read its profiles without closing anything, by
# touching its settings file - nothing is written in it, only its date, which is
# all the watcher looks at.
#
# WHEN matters, and only one moment works: touched from inside a command,
# nothing happens; the same touch once the command has returned to the prompt
# works at once. The reload lands while the pane is idle - hence the theme menu
# calls this when the visit is over.
function Update-TerminalSettings {
    foreach ($Path in @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )) {
        if (-not (Test-Path $Path)) { continue }
        try { (Get-Item $Path).LastWriteTime = Get-Date } catch { }
    }
}

# The profile Windows Terminal knows an instance by: the guid WSL wrote in its
# own fragment when the instance was imported. Asked with a few tries, because a
# fresh import and this question cross - the fragment lands a moment later.
function Get-WslProfileGuid {
    param([string]$Name)

    $Folder = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        if (Test-Path $Folder) {
            foreach ($File in (Get-ChildItem $Folder -Filter *.json | Sort-Object LastWriteTime -Descending)) {
                try {
                    foreach ($Entry in (Get-Content $File.FullName -Raw | ConvertFrom-Json).profiles) {
                        if ($Entry.name -eq $Name -and $Entry.guid) { return $Entry.guid }
                    }
                } catch { }
            }
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

# The Terminal profile as this repository writes it: layered over WSL's own via
# "updates", so the user's settings.json is never touched. The icon line is left
# out when there is no icon - Terminal shows its own.
#
# Byte-order-mark-free: Set-Content -Encoding Utf8 writes one, and a mark is not
# part of JSON. Whether Terminal refuses such a file was never seen alone - the
# mark and the reload changed the same day - so this is a rule, not a
# diagnosis.
function Set-InstanceFragment {
    param([string]$Name, [string]$Guid, [WslTheme]$Theme)

    $FragmentDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack"
    New-Item -ItemType Directory -Force $FragmentDir | Out-Null
    $IconJson = if ($Theme.IconPath -and (Test-Path $Theme.IconPath)) {
        '            "icon": "' + ($Theme.IconPath -replace '\\', '\\') + '",'
    } else {
        ''
    }
    $FragmentJson = @"
{
    "profiles": [
        {
            "updates": "$Guid",
$IconJson
            "font": { "face": "$($Theme.FontName)" },
            "colorScheme": "$($Theme.ColorScheme)",
            "suppressApplicationTitle": true
        }
    ]
}
"@
    $Target = Join-Path $FragmentDir "$Name.json"
    $Utf8NoMark = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Target, $FragmentJson, $Utf8NoMark)
}

# What an instance looks like right now: the fragment this repository wrote
# when it built the instance, what Windows Terminal's own settings say the user
# changed since, or the template's defaults - in that order. A settings file
# Windows Terminal owns may carry // comments, which ConvertFrom-Json refuses:
# that is what the try/catch is for.
function Get-InstanceAppearance {
    param([string]$Name)

    $Theme = [WslTheme]::Default($Name)

    $OurFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$Name.json"
    if (Test-Path $OurFragment) {
        try {
            $Parsed = (Get-Content $OurFragment -Raw | ConvertFrom-Json).profiles[0]
            if ($Parsed.font.face) { $Theme.FontName = $Parsed.font.face }
            if ($Parsed.colorScheme) { $Theme.ColorScheme = $Parsed.colorScheme }
        } catch { }
    }

    foreach ($SettingsPath in @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )) {
        if (-not (Test-Path $SettingsPath)) { continue }
        try {
            foreach ($Profile in (Get-Content $SettingsPath -Raw | ConvertFrom-Json).profiles.list) {
                if ($Profile.name -eq $Name -and $Profile.source -eq "Microsoft.WSL") {
                    if ($Profile.font.face) { $Theme.FontName = $Profile.font.face }
                    if ($Profile.colorScheme) { $Theme.ColorScheme = $Profile.colorScheme }
                }
            }
        } catch { }
    }

    # The icon lives next to the disk, where build.ps1 put it
    $Folder = Get-InstanceFolder -Name $Name
    if ($Folder) {
        $Icon = Join-Path $Folder "terminal-icon.png"
        if (Test-Path $Icon) { $Theme.IconPath = $Icon }
    }

    return $Theme
}

# A look as a file keeps it - the instance's own, or an archive's - seen as the
# theme it holds. The recipe comes along, so a redraw after a restore starts
# from the letters it was drawn with.
function ConvertTo-WslTheme {
    param([PSCustomObject]$Look)

    if (-not $Look) { return $null }
    $Theme = [WslTheme]::new($Look.IconFrom, $Look.ColorScheme, $Look.Font, $Look.Name)
    $Theme.IconText      = $Look.IconText
    $Theme.IconTop       = $Look.IconTop
    $Theme.IconBottom    = $Look.IconBottom
    $Theme.IconTextColor = $Look.IconTextColor
    return $Theme
}

# Give an instance back the look it had. Either from an archive folder, or from
# an appearance object captured a moment ago (duplicate.ps1, shrink.ps1).
function Set-InstanceState {
    param([string]$Name, [string]$InstallPath, [string]$Folder, [PSCustomObject]$Appearance)

    if ($Folder) {
        $File = Join-Path $Folder "instance.json"
        if (-not (Test-Path $File)) {
            # An archive taken before this existed carries nothing to re-apply.
            # Said out loud, because the reports downstream promise a look.
            Write-Host "  * Look             : the archive carries no instance.json - not re-applied" -ForegroundColor (Get-MessageColour warning)
            return
        }
        try { $Appearance = Get-Content $File -Raw | ConvertFrom-Json } catch { return }
        $IconInArchive = Join-Path $Folder "terminal-icon.png"
    }

    # The guid WSL just gave the instance: its own fragment, written on import
    $Guid = Get-WslProfileGuid -Name $Name

    if (-not $Guid) {
        Write-Host "  * Look             : no WSL fragment for '$Name' yet - not re-applied" -ForegroundColor (Get-MessageColour warning)
        return
    }

    $IconPath = Join-Path $InstallPath "terminal-icon.png"
    if ($IconInArchive -and (Test-Path $IconInArchive)) {
        Copy-Item -Path $IconInArchive -Destination $IconPath -Force
    } elseif ($Appearance.IconFrom -and (Test-Path $Appearance.IconFrom)) {
        Copy-Item -Path $Appearance.IconFrom -Destination $IconPath -Force
    }

    # The instance keeps its own copy of the file - the same shape, under its own
    # name, the icon pointing at its own folder. The recipe comes with it, or a
    # later change of letters or colours would start again from the name.
    $Theme = ConvertTo-WslTheme $Appearance
    $Theme.IconPath = $IconPath

    Set-InstanceLook -InstallPath $InstallPath -Look (New-InstanceLook -Name $Name `
        -Theme $Theme -Docker $Appearance.Docker -Icon (Get-IconRecipe -Look $Appearance))

    Set-InstanceFragment -Name $Name -Guid $Guid -Theme $Theme
    Write-Host "  * Look             : font '$($Appearance.Font)', colours '$($Appearance.ColorScheme)', icon re-applied" -ForegroundColor (Get-MessageColour success)

    if (-not (Test-FontInstalled $Appearance.Font)) {
        Write-Host "                       Not installed on Windows: '$($Appearance.Font)'." -ForegroundColor (Get-MessageColour warning)
        Write-Host "                       The prompt will show boxes until it is installed." -ForegroundColor (Get-MessageColour warning)
    }

    # Docker Desktop records the distros it knows by name, and reads that file
    # only when it starts: if the archive says it knew the original, the new one
    # is put back - the restart is the price, hence the [y/N] question.
    if ($Appearance.Docker -eq "yes" -and (Get-DockerState -Name $Name) -eq "no") {
        Write-Host ""
        # [y/N], not [Y/n]: this lands in the middle of a restore or a copy,
        # where the restart stops containers for a reason the user may not care
        # about.
        if (Confirm-YesNo "Add '$Name' to Docker Desktop? (it restarts Docker)" -DefaultNo) {
            try {
                Set-DockerState -Name $Name
                $PreviousEAP = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                $null = docker desktop restart *> $null
                $RestartCode = $LASTEXITCODE
                $ErrorActionPreference = $PreviousEAP
                if ($RestartCode -eq 0) {
                    Write-Host "  * Docker Desktop   : added, and restarted to pick it up" -ForegroundColor (Get-MessageColour success)
                } else {
                    Write-Host "  * Docker Desktop   : added - restart it for it to notice" -ForegroundColor (Get-MessageColour hint)
                }
            } catch {
                Write-Host "  * Docker Desktop   : could not be updated ($($_.Exception.Message))" -ForegroundColor (Get-MessageColour warning)
            }
        } else {
            Write-Host "  * Docker Desktop   : not added - its settings can take it later" -ForegroundColor (Get-MessageColour muted)
        }
    }
}

# ---------------------------------------------------------------------------
# DOCKER DESKTOP
# ---------------------------------------------------------------------------
# Docker Desktop injects its CLI into the distros its settings list, and reads
# that list only when it starts. "yes", "no", or "unknown" when Docker Desktop
# is not installed - which is not the same answer as "no" and must be reported
# as what it is.

function Get-DockerState {
    param([string]$Name)

    $Settings = Join-Path $env:APPDATA "Docker\settings-store.json"
    if (-not (Test-Path $Settings)) { return "unknown" }
    try {
        $Config = Get-Content $Settings -Raw | ConvertFrom-Json
        if (@($Config.IntegratedWslDistros) -contains $Name) { return "yes" }
        return "no"
    } catch {
        return "unknown"
    }
}

function Set-DockerState {
    param([string]$Name)

    # The recipe: a backup beside the file, the name rebuilt rather than
    # appended twice, and a byte-order-mark-free write because this file,
    # written by Docker Desktop, does not carry one.
    $Settings = Join-Path $env:APPDATA "Docker\settings-store.json"
    $Config = Get-Content $Settings -Raw | ConvertFrom-Json
    Copy-Item $Settings "$Settings.bak" -Force
    $Config.IntegratedWslDistros = @($Config.IntegratedWslDistros | Where-Object { $_ -and $_ -ne $Name }) + $Name
    $Json = ($Config | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText("$Settings.tmp", $Json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item "$Settings.tmp" $Settings -Force
}

# ---------------------------------------------------------------------------
# WINDOWS-SIDE CLEANUP
# ---------------------------------------------------------------------------
# The Windows Terminal and Docker traces an instance leaves: the build prunes
# the same ghosts the same way, so the mechanics live here, once.

# What Windows Terminal can still match: WSL writes one fragment per import
# under Fragments\Microsoft.WSL, and every guid those fragments carry is a
# live profile - anything else in the user's files is a ghost. Newest first,
# and the guid of the name asked for comes from the newest fragment naming it.
function Get-WslFragmentGuids {
    param([string]$Name)

    $WslFragmentsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\Microsoft.WSL"
    $LiveGuids = @()
    $Match = $null
    if (Test-Path $WslFragmentsDir) {
        foreach ($File in (Get-ChildItem $WslFragmentsDir -Filter *.json | Sort-Object LastWriteTime -Descending)) {
            try {
                $Fragment = Get-Content $File.FullName -Raw | ConvertFrom-Json
                foreach ($Entry in $Fragment.profiles) {
                    if ($Entry.guid) { $LiveGuids += $Entry.guid }
                    if (-not $Match -and $Name -and $Entry.name -eq $Name -and $Entry.guid) { $Match = $Entry.guid }
                }
            } catch { }
        }
    }
    return [PSCustomObject]@{ Guids = @($LiveGuids); Guid = $Match }
}

# The user's settings.json keeps a profile entry for every distro Terminal has
# seen; a rebuild or a removal orphans the old guid, and the entry points at
# nothing. This distro's entries whose guid no fragment carries are pruned -
# the file is backed up first. Answers what was pruned, per file, and the
# files it could not read.
function Remove-TerminalGhostEntries {
    param([string]$Name, [string[]]$LiveGuids)

    $Files = @()
    $Unreadable = @()
    foreach ($SettingsPath in @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )) {
        if (-not (Test-Path $SettingsPath)) { continue }
        try {
            $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
            $All = @($Settings.profiles.list)
            $Kept = @($All | Where-Object { -not ($_.source -eq "Microsoft.WSL" -and $_.name -eq $Name -and $LiveGuids -notcontains $_.guid) })
            if ($Kept.Count -ne $All.Count) {
                Copy-Item $SettingsPath "$SettingsPath.bak" -Force
                $Settings.profiles.list = $Kept
                $Settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsPath -Encoding Utf8
                $Files += [PSCustomObject]@{ Path = $SettingsPath; Pruned = $All.Count - $Kept.Count }
            }
        } catch {
            $Unreadable += $SettingsPath
        }
    }
    return [PSCustomObject]@{ Files = @($Files); Unreadable = @($Unreadable) }
}

# Our appearance fragments - one file per distro under Fragments\wsl-stack -
# whose target guid no fragment carries: the distro is gone and the file
# points at nothing. Answers the file names removed.
function Remove-StaleAppearanceFragments {
    param([string[]]$LiveGuids)

    $Removed = @()
    if ($LiveGuids.Count -eq 0) { return @() }
    $OurFragmentDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack"
    if (-not (Test-Path $OurFragmentDir)) { return @() }
    foreach ($File in (Get-ChildItem $OurFragmentDir -Filter *.json)) {
        try {
            $Fragment = Get-Content $File.FullName -Raw | ConvertFrom-Json
            $Target = ($Fragment.profiles | Where-Object { $_.updates } | Select-Object -First 1).updates
            if ($Target -and ($LiveGuids -notcontains $Target)) {
                Remove-Item $File.FullName -Force
                $Removed += $File.Name
            }
        } catch { }
    }
    return @($Removed)
}

# Docker Desktop reads its integrated-distros list only when it starts: a name
# pointing at nothing goes back out, the file backed up first and rewritten
# byte-order-mark-free, like Set-DockerState does. Answers whether the name was
# there, or why the file could not be updated.
function Remove-DockerIntegration {
    param([string]$Name)

    $DockerSettings = Join-Path $env:APPDATA "Docker\settings-store.json"
    if (-not (Test-Path $DockerSettings)) { return [PSCustomObject]@{ Removed = $false; Error = "" } }
    try {
        $DockerConfig = Get-Content $DockerSettings -Raw | ConvertFrom-Json
        if ($DockerConfig.IntegratedWslDistros -contains $Name) {
            Copy-Item $DockerSettings "$DockerSettings.bak" -Force
            $DockerConfig.IntegratedWslDistros = @($DockerConfig.IntegratedWslDistros | Where-Object { $_ -and $_ -ne $Name })
            $DockerJson = ($DockerConfig | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
            [System.IO.File]::WriteAllText("$DockerSettings.tmp", $DockerJson, (New-Object System.Text.UTF8Encoding($false)))
            Move-Item "$DockerSettings.tmp" $DockerSettings -Force
            return [PSCustomObject]@{ Removed = $true; Error = "" }
        }
        return [PSCustomObject]@{ Removed = $false; Error = "" }
    } catch {
        return [PSCustomObject]@{ Removed = $false; Error = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# THE INSTANCES, AND WHAT EVERY COMMAND ASKS ABOUT THEM
# ---------------------------------------------------------------------------
# These five used to live in twelve identical copies across scripts\; they are
# here now, where the commands already come for the marker and for Docker's
# answer.
function Invoke-External {
    param([scriptblock]$Command, [string]$ErrorMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage (Exit code: $LASTEXITCODE)"
    }
}

# The wrapper the strictest commands run their natives through: under EAP=Stop
# a program's stderr raises before its exit code can be read, and a code nobody
# reads is a failure that looks like a success. The answer is the code, and a
# code that is not zero stops the command.
function Invoke-NativeCommand {
    param([scriptblock]$Command, [string]$ErrorMessage, [switch]$SuppressOutput)

    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($SuppressOutput) { $null = & $Command *> $null } else { & $Command }
        $ExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $PreviousEAP
    }
    if ($ExitCode -ne 0) {
        throw "$ErrorMessage (Exit code: $ExitCode)"
    }
}

# And the same call when the failure IS the answer - a question asked of
# docker, where "no" must come back as $false and not as an exception.
function Test-NativeCommand {
    param([scriptblock]$Command)

    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $null = & $Command *> $null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $PreviousEAP
    }
}

# Every registered instance, as a WslInstance: its name, its folder and its WSL
# version (1 or 2). The registry says what Windows knows; it does not say which
# of them are ours - Test-TemplateInstance answers that, on the folder's marker.
# The scan itself lives on the class; this is the name the commands know.
function Get-Distros {
    return @([WslInstance]::GetAll())
}

# What WSL answers about the instances it knows, which is the only source that
# says whether one is RUNNING - the registry does not. Wrapped in @() for the
# reason every caller wraps it: PowerShell unrolls a one-element list into its
# element, and a string is not a list of one.
function Get-DistroNames {
    param([switch]$Running)
    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $WslArgs = @("--list", "--quiet")
    if ($Running) { $WslArgs += "--running" }
    $Names = (wsl.exe @WslArgs 2>$null) |
        ForEach-Object { ($_ -replace "`0", "").Trim() } |
        Where-Object { $_ }
    $ErrorActionPreference = $PreviousEAP
    return @($Names)
}

# How much room an instance takes on Windows - the .vhdx file's size on disk,
# not what its filesystem holds.
function Get-VhdxSize {
    param([string]$Folder)
    $Vhdx = Join-Path $Folder "ext4.vhdx"
    if (Test-Path $Vhdx) { return (Get-Item $Vhdx).Length }
    return 0
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N1} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N0} KB" -f ($Bytes / 1KB))
}

# ---------------------------------------------------------------------------
# RUNNING THINGS IN AN INSTANCE
# ---------------------------------------------------------------------------
# Commands are passed one argument at a time and run without a shell: the only
# string that ever travels through wsl.exe is a plain path - a bash script
# handed over as text breaks quietly, the quotes not surviving the round trip.
#
# stderr is non-terminating for these calls: under EAP=Stop a redirection turns
# it terminating, and WSL itself writes there (the proxy warning, for instance).
# The exit code is what says whether the command worked.

# Run a command in the instance. Its output is streamed - a pack's install.sh
# may ask for a password - so the exit code cannot be the return value: a
# `return $code` would put the output in the caller's variable and the code in
# the console. It comes back through a [ref] instead.
function Invoke-InInstance {
    param(
        [string]$DistroName,
        [string[]]$Command,
        [string]$WorkingDirectory,
        [ref]$ExitCode,
        [switch]$Quiet,
        # "root" runs the command as the root user - WSL's own door, no
        # password: the pack removal's way in, where sudo's question never
        # crossed the pipe.
        [string]$RunAs
    )

    $WslArgs = @("-d", $DistroName)
    if ($RunAs) { $WslArgs += @("-u", $RunAs) }
    if ($WorkingDirectory) { $WslArgs += @("--cd", $WorkingDirectory) }
    $WslArgs += @("--") + $Command

    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    if ($Quiet) {
        & wsl.exe @WslArgs *> $null
    } else {
        & wsl.exe @WslArgs
    }
    $ExitCode.Value = $LASTEXITCODE
    $ErrorActionPreference = $PreviousEAP
}

# Run a command in the instance and read what it printed, one line per entry.
function Get-InInstanceOutput {
    param([string]$DistroName, [string[]]$Command)

    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $Output = & wsl.exe -d $DistroName -- @Command 2>$null
    $ErrorActionPreference = $PreviousEAP

    return @($Output | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
}

# The instance's own home, asked rather than guessed: `~` only expands in a
# shell, and the calls above avoid shells on purpose.
function Get-InstanceHome {
    param([string]$DistroName)
    return (Get-InInstanceOutput -DistroName $DistroName -Command @("printenv", "HOME") | Select-Object -First 1)
}
