using module ..\WslModel\WslModel.psd1

[CmdletBinding()]
param (
    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# The window's faces, shipped in the repository: assets\fonts\VT323 (the
# retro terminal face) and Font Awesome 6 Free Solid (every button's icon).
# WPF reads them straight from the folder - no install, no dependency on a
# Windows font - and the families are asked of WPF itself rather than spelled
# out: the two files carry different family names under different name-table
# entries, and a guessed name would fail to a silent tofu. Missing files:
# the XAML's own face stands.
$script:UiFont = $null
$script:IconFont = $null
$FontDir = Join-Path $PSScriptRoot "..\..\assets\fonts"
if (Test-Path $FontDir) {
    try {
        # The Uri overload, NOT the string one: handed a plain path, WPF
        # answers an EMPTY collection without a word (measured), and the
        # whole retro face fell back silently. And a folder-loaded family's
        # Source comes back as "./#Family Name" - a relative reference - so
        # the family travels as an OBJECT, never as a string for XAML.
        $FontUri = [Uri]("file:///" + ($FontDir -replace '\\', '/') + "/")
        foreach ($family in [Windows.Media.Fonts]::GetFontFamilies($FontUri)) {
            if ("$($family.Source)" -like "*VT323*") { $script:UiFont = $family }
            if ("$($family.Source)" -like "*Font Awesome*") { $script:IconFont = $family }
        }
    } catch { }
}

# The chart of every window: loaded on its own and merged in code - a
# Source= reference needs a base URI the loose parser never hands the inner
# dictionary (its setter dies on a null one: "baseUri cannot be null"), and
# every window gets its own copy.
function Get-ThemeDictionary {
    $ThemePath = Join-Path $PSScriptRoot "..\gui\Theme\theme.xaml"
    [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($ThemePath)))
}

# The icon buttons ask for the face through a DynamicResource, and the
# FAMILY OBJECT is handed to the window below: a folder-loaded family's
# Source is a code-side reference - turned back into a string for XAML it
# fails to resolve, and WPF falls back silently (the icons came out as empty
# boxes). An object needs no resolution.
$DressWindow = {
    param($Win)
    if ($script:UiFont) {
        $Win.FontFamily = $script:UiFont
        $Win.FontSize = 15
    }

    # The frame treatment, once per window: no chrome, a transparent window,
    # and the phosphor border + glow drawn in code - the eight popups get it
    # without carrying XAML for it, and drag by their background like the
    # main window does. The main window wears its own and is tagged
    # 'framed', so it passes through here untouched.
    if ($Win.Tag -ne 'framed') {
        $Win.Tag = 'framed'
        $Win.WindowStyle = [System.Windows.WindowStyle]::None
        $Win.AllowsTransparency = $true
        $Win.Background = [System.Windows.Media.Brushes]::Transparent

        $content = $Win.Content
        $Win.Content = $null
        $border = New-Object System.Windows.Controls.Border
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1F9E4C")
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
        $border.Margin = [System.Windows.Thickness]::new(14)
        $effect = New-Object System.Windows.Media.Effects.DropShadowEffect
        $effect.Color = [System.Windows.Media.Color]::FromRgb(0x33, 0xFF, 0x66)
        $effect.BlurRadius = 10
        $effect.ShadowDepth = 0
        $effect.Opacity = 0.30
        $border.Effect = $effect
        $border.Child = $content
        $Win.Content = $border

        $Win.Add_MouseLeftButtonDown({
            param($sender, $e)
            $node = $e.OriginalSource
            try {
                while ($node -and $node -ne $sender) {
                    if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or
                        $node -is [System.Windows.Controls.TextBox] -or
                        $node -is [System.Windows.Controls.Primitives.ScrollBar] -or
                        $node -is [System.Windows.Controls.ComboBox]) { return }
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                }
                $sender.DragMove()
            } catch { }
        })
    }
}

# 1. The XAML: the header, the list, an indeterminate bar for the long work,
# and the actions - Add and Refresh up in the header, and on every row Open,
# Start or Stop, Edit, Archive, Compact and the trash, with the restore and
# the trash alone on an archived row.
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WSL Stack Manager" Width="700" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Foreground="#33FF66" Tag="framed"
        FontFamily="Segoe UI" FontSize="13">
    <!-- The phosphor frame: a thin green line and its glow. The margin is
         the halo's room - both live inside the transparent window, and the
         fully transparent corners let clicks through, as this mode does. -->
    <Border BorderBrush="#1F9E4C" BorderThickness="1" CornerRadius="6" Background="#1E1E1E" Margin="14" SnapsToDevicePixels="True">
        <Border.Effect>
            <DropShadowEffect Color="#33FF66" BlurRadius="10" ShadowDepth="0" Opacity="0.30"/>
        </Border.Effect>
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header: the title on the left, the add and the refresh on the
             other side. -->
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
                <TextBlock Text="WSL Fleet" FontSize="20" FontWeight="SemiBold" Foreground="#33FF66"/>
                <TextBlock Name="TxtRoot" FontSize="11" Foreground="#2F9E55" Margin="0,2,0,0"/>
            </StackPanel>
            <Button Name="BtnAdd" Grid.Column="1" Content="&#xF067;" FontFamily="{DynamicResource IconFace}" FontSize="14"
                    Width="28" Height="28" Padding="0" Margin="0,0,8,0" VerticalAlignment="Top"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"
                    ToolTip="Add"/>
            <Button Name="BtnRefresh" Grid.Column="2" Content="&#xF021;" FontFamily="{DynamicResource IconFace}" FontSize="14"
                    Width="28" Height="28" Padding="0" VerticalAlignment="Top"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"
                    ToolTip="Refresh"/>
            <Button Name="BtnQuit" Grid.Column="3" Content="&#xF00D;" FontFamily="{DynamicResource IconFace}" FontSize="14"
                    Width="28" Height="28" Padding="0" Margin="8,0,0,0" VerticalAlignment="Top"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"
                    ToolTip="Close"/>
        </Grid>

        <!-- The instances -->
        <ListView Name="LstInstances" Grid.Row="1" Background="#252526" BorderBrush="#3F3F46" Foreground="#33FF66"
                  AlternationCount="2" KeyboardNavigation.TabNavigation="Continue">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Name" Width="200" DisplayMemberBinding="{Binding Name}"/>
                    <GridViewColumn Header="Status" Width="100" DisplayMemberBinding="{Binding Status}"/>
                    <GridViewColumn Header="Size" Width="110" DisplayMemberBinding="{Binding Size}"/>
                    <GridViewColumn Header="Action" Width="264">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Grid Width="236" Height="22">
                                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                                        <!-- An archived row carries its own two - restore
                                             and the trash; a live row the rest: a shell
                                             in a terminal of its own, then Start or Stop -
                                             whichever the state allows - the pack editor,
                                             the appearance, the copy, the archive, the
                                             Compact and the trash. The styles arrive by
                                             DynamicResource: this template loads after the
                                             window is parsed, and a StaticResource from
                                             here cannot see the dictionary merged in code
                                             (measured, cell template beside a local key). -->
                                        <Button Name="BtnRowRestore" Content="&#xF2EA;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource ArchivedRowButton}"
                                                ToolTip="Restore"/>
                                        <Button Name="BtnRowDeleteArchive" Content="&#xF1F8;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource ArchivedRowButton}"
                                                ToolTip="Delete"/>
                                        <Button Name="BtnRowOpen" Content="&#xF120;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Shell"/>
                                        <Button Name="BtnRowStart" Content="&#xF04B;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource BtnRowStart}"
                                                ToolTip="Start"/>
                                        <Button Name="BtnRowStop" Content="&#xF04D;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource BtnRowStop}"
                                                ToolTip="Stop"/>
                                        <Button Name="BtnRowEdit" Content="&#xF304;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Edit"/>
                                        <Button Name="BtnRowAppearance" Content="&#xF53F;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Appearance"/>
                                        <Button Name="BtnRowDuplicate" Content="&#xF0C5;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Duplicate"/>
                                        <Button Name="BtnRowArchive" Content="&#xF187;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Archive"/>
                                        <Button Name="BtnRowCompact" Content="&#xF066;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Margin="0,0,4,0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Compact"/>
                                        <Button Name="BtnRowRemove" Content="&#xF1F8;" FontFamily="{DynamicResource IconFace}" FontSize="13"
                                                Width="26" Height="22" Padding="0" Background="Transparent"
                                                Foreground="#33FF66" BorderBrush="Transparent"
                                                Style="{DynamicResource LiveRowButton}"
                                                ToolTip="Remove"/>
                                    </StackPanel>
                                    <ProgressBar Name="RowSpinner" IsIndeterminate="True" Height="4" Width="24"
                                                 Visibility="Collapsed" VerticalAlignment="Center" HorizontalAlignment="Center"
                                                 Foreground="#33FF66" Background="#2D2D30" BorderThickness="0"/>
                                </Grid>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                </GridView>
            </ListView.View>
        </ListView>

        <!-- The progress bar (hidden until something runs) -->
        <ProgressBar Name="PrgWork" Grid.Row="2" Height="4" Margin="0,10,0,0"
                     IsIndeterminate="True" Visibility="Collapsed"
                     Foreground="#33FF66" Background="#2D2D30" BorderThickness="0"/>

        <!-- Status line: a read-only box, not a label - same look, but the
             text can be selected and copied (TextBlock never offers that). -->
        <TextBox Name="TxtStatus" Grid.Row="3" Margin="0,8,0,0" FontSize="11" Foreground="#3FAE5F" Text="Ready."
                 IsReadOnly="True" Background="Transparent" BorderThickness="0" Padding="2,0"
                 SelectionBrush="#14532D"/>
    </Grid>
    </Border>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.Resources.MergedDictionaries.Add((Get-ThemeDictionary))
& $DressWindow $window

# The face every icon button asks for - rows and header alike, templates
# included: a DynamicResource reaches them wherever they are built.
if ($script:IconFont) { $window.Resources["IconFace"] = $script:IconFont }

# The controls, by name
$lstInstances = $window.FindName("LstInstances")
$txtRoot      = $window.FindName("TxtRoot")
$txtStatus    = $window.FindName("TxtStatus")
$prgWork      = $window.FindName("PrgWork")
$btnRefresh   = $window.FindName("BtnRefresh")
$btnAdd       = $window.FindName("BtnAdd")
$btnQuit      = $window.FindName("BtnQuit")

$txtRoot.Text = "Root: $($Manager.InstancesRoot)"

# Busy and idle, for the whole window
$SetBusyState = {
    param([bool]$busy, [string]$statusMessage)

    $prgWork.Visibility = if ($busy) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $btnRefresh.IsEnabled = -not $busy
    $lstInstances.IsEnabled = -not $busy

    if ($statusMessage) { & $SetStatus $statusMessage }
}

# The status line's two voices: news, and a failure - a failure wears red.
# Every write goes through here, so the voice follows the last message; where
# the kind of a message is not known, it stays in the news voice.
$SetStatus = {
    param([string]$Message, [switch]$Alert)

    $txtStatus.Foreground = if ($Alert) { "#E04040" } else { "#3FAE5F" }
    $txtStatus.Text = $Message
}

$LoadFleet = {
    $lstInstances.Items.Clear()

    try {
        $rows = @()

        # The manager's own list - the same the console doors show.
        $instances = @($Manager.OursHere())
        foreach ($inst in $instances) {
            $isRunning = ($inst.State -eq [WslState]::Running)
            # The disk's size, the way the console's lists read it: the folder
            # holds ext4.vhdx, and Format-Size spells the bytes.
            $sizeStr = Format-Size (Get-VhdxSize $inst.Path)

            $rows += [PSCustomObject]@{
                Name     = $inst.Name
                Status   = if ($isRunning) { "Running" } else { "Stopped" }
                Size     = $sizeStr
                Instance = $inst
            }
        }

        # Then every archive on disk - the manager's live read, the way the
        # console's list shows them. A same-named archive and instance sit in
        # the list together, so the pair reads at a glance. The size shown is
        # the tar's where an instance shows its vhdx; the instance built here
        # is the archive's own shape: the folder it would take back, the tar
        # it holds.
        $archives = @($Manager.List().Archives)
        foreach ($archive in $archives) {
            $tar = Get-ChildItem -Path $archive.FullName -Filter "*.tar*" -File |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1

            $archivedInst = [WslInstance]::new()
            $archivedInst.Name = $archive.Name
            $archivedInst.Path = Join-Path $Manager.InstancesRoot $archive.Name
            $archivedInst.HasArchive = $true
            $archivedInst.ArchivePath = $archive.FullName
            $archivedInst.State = [WslState]::Archived

            $rows += [PSCustomObject]@{
                Name     = $archive.Name
                Status   = "Archived"
                Size     = Format-Size $tar.Length
                Instance = $archivedInst
            }
        }

        # One alphabetical walk over both kinds; -Stable keeps the instance
        # above the archive of the same name (the order they were built in).
        $sorted = @($rows | Sort-Object -Property Name -Stable)
        foreach ($row in $sorted) {
            $null = $lstInstances.Items.Add($row)
        }

        # The first three columns measured to their content: a GridView never
        # sizes itself, and Name sat three times wider than the longest name.
        # The header is measured too, its text must fit; the action column
        # keeps its width - icons do not vary.
        if ($sorted.Count -gt 0) {
            $typeface = New-Object Windows.Media.Typeface("Segoe UI")
            $measures = @(
                @{ Column = 0; Header = "Name";   Values = @($sorted | ForEach-Object { "$($_.Name)" }) },
                @{ Column = 1; Header = "Status"; Values = @($sorted | ForEach-Object { "$($_.Status)" }) },
                @{ Column = 2; Header = "Size";   Values = @($sorted | ForEach-Object { "$($_.Size)" }) }
            )
            foreach ($m in $measures) {
                $widest = 0.0
                foreach ($text in @($m.Header) + @($m.Values)) {
                    if (-not $text) { continue }
                    $ft = New-Object Windows.Media.FormattedText($text,
                        [Globalization.CultureInfo]::CurrentCulture, [Windows.FlowDirection]::LeftToRight,
                        $typeface, [double]$window.FontSize, [Windows.Media.Brushes]::Black, [double]1)
                    if ($ft.Width -gt $widest) { $widest = $ft.Width }
                }
                $lstInstances.View.Columns[$m.Column].Width = [Math]::Min(420, [Math]::Max(90, [Math]::Ceiling($widest) + 28))
            }

            # The window fits the columns, not the other way around: the LAST
            # column of a GridView swallows whatever room is left, and the
            # Action column grew while the others shrank. The budget is every
            # pixel the frame eats: border margin 28, the border's line 2,
            # the grid's margin 28, the list's own line 2, the vertical
            # scrollbar 17, and a breath.
            $total = 0.0
            foreach ($column in $lstInstances.View.Columns) { $total += $column.Width }
            $window.Width = [Math]::Min(1100, [Math]::Max(560, $total + 84))
        }

        $total = $instances.Count + $archives.Count
        if ($total -eq 0) {
            & $SetStatus "No WSL Stack instances found."
            return
        }
        & $SetStatus "$total row(s) loaded."
    } catch {
        & $SetStatus "Error reading instances: $($_.Exception.Message)" -Alert
    }
}

# The job the window's buttons run, for real: a CHILD PROCESS. A runspace of
# one's own was tried first, and it hangs - the engine's very first move reads
# wsl.exe, and a native program invoked in a runspace with no host never comes
# back on Windows (measured: the trail stopped at "imported", before "manager
# made"). A child pwsh HAS a host and runs wsl.exe like every other console;
# the trail file is how it reports. This source goes to the temp folder at
# each launch, its arguments on the command line: verb, name, archive, module.
$JobRunnerSource = @'
param([string]$Verb, [string]$Name, [string]$ArchiveFirst, [string]$Module)

$Log = Join-Path $env:TEMP "wsl-stack-gui-job.log"
function Write-Stamp($Message) {
    $null = Add-Content -LiteralPath $Log -Value "$(Get-Date -Format HH:mm:ss) $Message"
}

try {
    Write-Stamp "importing"
    Import-Module $Module -Force
    Write-Stamp "imported"
    $mgr = New-InstanceManager
    Write-Stamp "manager made"

    if ($Verb -eq "restore") {
        # No instance to find: the row was an archive. -ArchiveFirst carries
        # the archive folder here, and -Name the name the new instance takes.
        Write-Stamp "restoring"
        $r = $mgr.RestoreFromArchive($ArchiveFirst, $Name)
        Write-Stamp ("RESULT OK " + $Name + ": restored from '" + (Split-Path $ArchiveFirst -Leaf) + "'")
    } elseif ($Verb -eq "delete") {
        # No instance to find here either: the archive's own folder goes.
        Write-Stamp "deleting the archive"
        $r = $mgr.DeleteArchive($Name)
        Write-Stamp ("RESULT OK " + $Name + ": archive deleted - " + [math]::Round($r.Freed / 1MB, 1) + " MB freed")
    } else {
        $inst = @($mgr.OursHere()) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        Write-Stamp "list read: $([bool]$inst)"
        if (-not $inst) { throw "'$Name' is not in our list any more." }

        if ($Verb -eq "archive") {
            # The export reads a still disk: a running instance is stopped for
            # it and started again after - the console's own manners. The
            # state is compared by name: no class literal resolves here (the
            # module came in through Import-Module).
            Write-Stamp "archiving"
            $wasRunning = ("$($inst.State)" -eq "Running")
            if ($wasRunning) {
                $inst.Stop()
                Write-Stamp "stopped for a consistent export"
            }
            $r = $mgr.Archive($inst, $ArchiveFirst, "tar.gz")
            if ($wasRunning) {
                $inst.Start()
                Write-Stamp "started again"
            }
            Write-Stamp ("RESULT OK " + $Name + ": archived as '" + $ArchiveFirst + "' (" + [math]::Round($r.Archive.Length / 1MB, 1) + " MB)")
        } elseif ($Verb -eq "duplicate") {
            # -ArchiveFirst carries the copy's name here. The source is
            # stopped for a consistent read - and started again whatever the
            # outcome, where the console would leave it down on a refusal.
            Write-Stamp "duplicating"
            $wasRunning = ("$($inst.State)" -eq "Running")
            if ($wasRunning) {
                $inst.Stop()
                Write-Stamp "stopped for a consistent read"
            }
            $cost = $mgr.DuplicationCost($inst, $ArchiveFirst)
            if ($cost.FreeBytes -lt $cost.NeededBytes) {
                if ($wasRunning) { $inst.Start() }
                throw ("Not enough room on {0}: needed {1}, free {2}." -f $cost.DriveLetter, (Format-Size $cost.NeededBytes), (Format-Size $cost.FreeBytes))
            }
            Write-Stamp "copying"
            $r = $mgr.Duplicate($inst, $ArchiveFirst)
            if ($wasRunning) {
                $inst.Start()
                Write-Stamp "started again"
            }
            Write-Stamp ("RESULT OK " + $ArchiveFirst + ": duplicated from '" + $Name + "'")
        } elseif ($Verb -eq "compact") {
            Write-Stamp "compacting"
            $r = $mgr.Shrink($inst)
            Write-Stamp ("RESULT OK " + $Name + ": compacted - reclaimed " + [math]::Round($r.Freed / 1MB, 1) + " MB")
        } elseif ($Verb -eq "start") {
            Write-Stamp "starting"
            $inst.Start()
            Write-Stamp ("RESULT OK " + $Name + ": started")
        } elseif ($Verb -eq "stop") {
            Write-Stamp "stopping"
            $inst.Stop()
            Write-Stamp ("RESULT OK " + $Name + ": stopped")
        } else {
            Write-Stamp "removing"
            $r = $mgr.Unregister($inst, [bool]::Parse($ArchiveFirst))
            Write-Stamp ("RESULT OK " + $Name + ": removed - folder " + $r.Removed.FolderState)
        }
    }
    exit 0
} catch {
    Write-Stamp ("RESULT FAIL " + ($_.Exception.Message -replace "`r?`n", " "))
    exit 1
}
'@

# The pack run's own window, for real: VISIBLE, this one - the installs can
# take minutes, and what they are doing is the point. It prints the same lines
# the console's manage_packs prints, because it is the same engine doing the
# work; the window then waits for Enter, so a failure can be read before it
# closes. Nothing watches it: the window IS the progress.
$EditRunnerSource = @'
param([string]$Name, [string]$Add, [string]$Remove, [string]$Module)

try {
    Import-Module $Module -Force
    $mgr = New-InstanceManager

    $inst = @($mgr.OursHere()) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $inst) { throw "'$Name' is not in our list any more." }

    # The distro must be up to carry packs - the console's own first move.
    Invoke-External { wsl.exe -d $Name --exec /bin/true } "Could not start '$Name'."

    $catalog = Get-PackCatalog
    $toAdd = @()
    foreach ($n in @($Add -split ',' | Where-Object { $_ })) {
        $pack = $catalog.GetPack($n)
        if ($null -ne $pack) { $toAdd += $pack }
    }
    $toRemove = @($Remove -split ',' | Where-Object { $_ })

    Write-Host ""
    Write-Host "==> Packs of '$Name'" -ForegroundColor (Get-MessageColour info)
    $report = $mgr.ManagePacks($inst, $toAdd, $toRemove, "")

    if ($null -eq $report.Failure) {
        Write-Host ""
        $now = @($report.Now)
        Write-Host "==> '$Name' now carries: $(if ($now.Count -gt 0) { $now -join ', ' } else { 'no pack' })" -ForegroundColor (Get-MessageColour success)
    }
} catch {
    # No colour helper here: this very catch exists for the case where the
    # module did not load - and the helper lives in the module.
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
'@

# The build's own window, for real: VISIBLE, like the packs run - the build is
# long, loud, and still has questions only it can ask (the account the image
# already carries, the Docker image, Docker Desktop, the first shell). It is
# called in PowerShell with its arguments NAMED - wsl.ps1's road hands extra
# arguments over positionally, which is how they used to land nowhere - and
# the window waits for Enter at the end: an abort must not vanish with the
# process.
$BuildRunnerSource = @'
param([string]$Name, [string]$User, [string]$Packs, [string]$Module, [string]$BuildScript)

try {
    Import-Module $Module -Force
    $mgr = New-InstanceManager
    & $BuildScript -Name $Name -User $User -Packs $Packs -Manager $mgr
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
}

Write-Host ""
$null = Read-Host "Press Enter to close this window"
'@

# The watcher every job the window starts shares - created HERE, at the script
# level, where the scope every handler reads from stays alive: a block made
# inside a click handler reads its state through a scope that is gone when the
# timer fires (measured). It watches the child; the trail carries the ending;
# the ending itself (status, re-enable, refresh) sits in a finally that
# nothing can skip.
$WatchJob = {
    # The early way out stays outside the try: a return under a finally runs
    # the finally - it would lower the busy state on every tick. While waiting,
    # it shows it is alive: the tick count proves the timer beats.
    if ($null -eq $script:Child) { return }
    if (-not $script:Child.HasExited) {
        $script:Ticks++
        & $SetStatus "The $($script:JobVerb) of '$($script:JobName)' - running - tick $($script:Ticks)"
        return
    }

    try {
        $script:Poller.Stop()
        $script:Ticks = 0
        $script:KeepTrail = $false

        # The trail's last word: the child wrote its own ending there.
        $TrailPath = Join-Path $env:TEMP "wsl-stack-gui-job.log"
        $trail = @(Get-Content -LiteralPath $TrailPath -ErrorAction SilentlyContinue)
        $ok = @($trail | Where-Object { $_ -like "*RESULT OK *" } | Select-Object -Last 1)
        $bad = @($trail | Where-Object { $_ -like "*RESULT FAIL *" } | Select-Object -Last 1)

        if ($bad.Count -gt 0) {
            $script:EndingText = "Failed to $($script:JobVerb) '$($script:JobName)': " + ($bad[0] -replace "^.*?RESULT FAIL ", "")
            $script:EndingAlert = $true
        } elseif ($ok.Count -gt 0) {
            $script:EndingText = ($ok[0] -replace "^.*?RESULT OK ", "")
            $script:EndingAlert = $false
        } else {
            # The trail could not tell the ending: it stays, it is the evidence.
            $script:EndingText = "The $($script:JobVerb) of '$($script:JobName)' ended (exit $($script:Child.ExitCode)) with no result in the trail ($TrailPath)."
            $script:EndingAlert = $true
            $script:KeepTrail = $true
        }
    } catch {
        # The watcher itself failed: say it here - a dead watcher must not look
        # like a job that never ends.
        $script:EndingText = "The watcher failed: $($_.Exception.Message)"
        $script:EndingAlert = $true
    } finally {
        $script:Child = $null
        & $SetBusyState $false $null
        & $LoadFleet
        # After the reload: its own count line would otherwise bury the ending.
        if ($script:EndingText) { & $SetStatus $script:EndingText -Alert:$script:EndingAlert }
        # The menage: the runner served its launch, and the trail is done once
        # it has told the ending - kept only when it could not.
        Remove-Item -LiteralPath (Join-Path $env:TEMP "wsl-stack-gui-job.ps1") -ErrorAction SilentlyContinue
        if (-not $script:KeepTrail) {
            Remove-Item -LiteralPath (Join-Path $env:TEMP "wsl-stack-gui-job.log") -ErrorAction SilentlyContinue
        }
    }
}

# The row says it is working - its icons give way to the little scrolling band.
# Cosmetic, and guarded: the job must never hinge on it.
$MarkRow = {
    param($Button)
    try {
        $Button.Parent.Visibility = [System.Windows.Visibility]::Collapsed
        $Button.Parent.Parent.Children[1].Visibility = [System.Windows.Visibility]::Visible
    } catch { }
}

# The watcher first: a click here drains whatever the timer has not - if the
# tick ever fails to fire, Refresh still ends the job and reports it.
$btnRefresh.Add_Click({ & $WatchJob; & $LoadFleet })
$btnQuit.Add_Click({ $window.Close() })

# Add: the form first, then the run in a console window of its own - the real
# entry, not a copy of it, so the console's build and this one cannot drift
# apart. It stays interactive there: the account the image already carries,
# the Docker image, Docker Desktop, and the shell at the end.
$btnAdd.Add_Click({
    # Docker first: a build cannot move without it, and the form is long
    # enough that finding out at the end would be a waste.
    if (-not (Test-NativeCommand { docker info })) {
        # The system's own alert, not a window of ours: a sentence and one
        # button, with the keys every Windows alert answers to.
        Show-PopupExclusive $window {
            $null = [System.Windows.MessageBox]::Show($window,
                "Please start Docker Desktop and try again.",
                "Docker is not running",
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
        return
    }

    $catalog = Get-PackCatalog
    $form = Show-AddInstance -Catalog $catalog -ProposedUser (Get-WindowsUserProposal) -InstancesRoot $Manager.InstancesRoot -Manager $Manager
    if ($null -eq $form) { return }

    $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
    $BuildScript = Join-Path $PSScriptRoot "build.ps1"
    $RunnerPath = Join-Path $env:TEMP "wsl-stack-gui-build.ps1"
    Set-Content -LiteralPath $RunnerPath -Value $BuildRunnerSource -Encoding utf8NoBOM
    $null = Start-Process pwsh -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
        "`"$($form.Name)`"", "`"$($form.User)`"", "`"$($form.Packs -join ',')`"", "`"$ModulePath`"", "`"$BuildScript`""
    )
    & $SetStatus "Creating '$($form.Name)' in a window of its own."
})

# Every popup goes through here: the fleet window steps aside while a dialog
# is up - visible but deaf behind a modal is a trap - and comes back when the
# dialog closes. The parent must be a plain window, never a dialog: hiding a
# dialog window runs WPF's dialog teardown (DoDialogHide unblocks the modal
# frame - the ShowDialog behind it returns).
function Show-PopupExclusive {
    param(
        [System.Windows.Window]$ParentWindow,
        [scriptblock]$DialogAction
    )
    $ParentWindow.Hide()
    try {
        & $DialogAction
    }
    finally {
        $ParentWindow.Show()
        $null = $ParentWindow.Activate()
    }
}

# -----------------------------------------------------------------------------
# THE TRASH, ONE ROW AT A TIME - THE REMOVAL GATE, WINDOW-SIDE
# -----------------------------------------------------------------------------
# A row's trash opens the same gate the console's unregister puts up: what is
# lost, spelled out, and the exact name typed back (-ceq, case and all). The
# removal itself is the engine's - the same call the console makes.
function Show-RemoveGate {
    param($Instance)

    [xml]$gateXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Remove instance" Width="540" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <!-- Exceptions de couleur explicites -->
        <TextBlock Text="WARNING: PERMANENT DESTRUCTION" FontSize="16" FontWeight="Bold" Foreground="#E04040"/>
        <TextBlock Name="TxtLead" Margin="0,10,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Margin="0,10,0,0" TextWrapping="Wrap">Proceeding will PERMANENTLY DESTROY this distribution, erasing its install folder, its virtual disk (VHDX), and its content. This operation CANNOT be undone.</TextBlock>
        <CheckBox Name="ChkArchive" TabIndex="0" Margin="0,12,0,0" Content="Archive it first"/>
        <TextBlock Margin="0,14,0,0" Text="To confirm DESTRUCTION, type the exact name of the instance:"/>
        <TextBox Name="TxtName" TabIndex="1" Margin="0,6,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnGateCancel" TabIndex="2" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"/>
            <Button Name="BtnGateRemove" TabIndex="3" Content="REMOVE" Width="90" Height="28" IsEnabled="False" IsDefault="True"
                    Background="#A1260D" Foreground="#FFFFFF" BorderBrush="#BB2D0F"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $gate = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($gateXaml))
    $gate.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $gate
    $gate.FindName("TxtLead").Text = "The WSL distribution '$($Instance.Name)' and ALL its data will be deleted."
    $txtName = $gate.FindName("TxtName")
    $btnRemove = $gate.FindName("BtnGateRemove")
    $chkArchive = $gate.FindName("ChkArchive")

    # The keyboard starts at the top of the gate and walks down the screen:
    # the archive box, the name, Cancel, REMOVE. Enter is REMOVE (IsDefault)
    # and Escape is Cancel (IsCancel), wherever the walk stands.
    $null = $chkArchive.Focus()

    $script:GateResult = $null

    # The button wakes only on the exact name, case and all - the console's -ceq.
    $txtName.Add_TextChanged({
        $btnRemove.IsEnabled = ($txtName.Text -ceq $Instance.Name)
    })
    $gate.FindName("BtnGateCancel").Add_Click({ $script:GateResult = $null; $gate.Close() })
    $btnRemove.Add_Click({
        $script:GateResult = @{ ArchiveFirst = [bool]$chkArchive.IsChecked }
        $gate.Close()
    })

    Show-PopupExclusive $window { $null = $gate.ShowDialog() }
    return $script:GateResult
}

# -----------------------------------------------------------------------------
# AN ARCHIVE, ONE ROW AT A TIME - THE RESTORE PROMPT, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The console's one question for a restore: the name the new instance takes -
# the archive's own name prefilled, because bringing it back under its name is
# the usual answer. Same window manners as the gate: Enter restores, Escape
# cancels, an empty name is a cancel.
function Show-RestorePrompt {
    param([string]$ArchiveName)

    [xml]$restoreXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Restore archive" Width="540" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="TxtLead" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Margin="0,14,0,0" Text="Name of the restored instance:"/>
        <TextBox Name="TxtName" TabIndex="0" Margin="0,6,0,0" Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnRestoreCancel" TabIndex="1" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnRestoreGo" TabIndex="2" Content="RESTORE" Width="90" Height="28" IsDefault="True"
                    Background="#33FF66" Foreground="#1E1E1E" BorderBrush="#33FF66"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $prompt = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($restoreXaml))
    $prompt.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $prompt
    $prompt.FindName("TxtLead").Text = "The archive '$ArchiveName' comes back as a new instance."
    $txtName = $prompt.FindName("TxtName")
    $txtName.Text = $ArchiveName

    # The box holds the focus once the window is up, its text selected: typed
    # straight away, it answers with the name wanted (set before the show, the
    # focus and the selection do not always stick).
    $prompt.Add_ContentRendered({ $null = $txtName.Focus(); $txtName.SelectAll() })

    $script:RestoreResult = $null
    $prompt.FindName("BtnRestoreCancel").Add_Click({ $script:RestoreResult = $null; $prompt.Close() })
    $prompt.FindName("BtnRestoreGo").Add_Click({
        $script:RestoreResult = $txtName.Text.Trim()
        $prompt.Close()
    })

    Show-PopupExclusive $window { $null = $prompt.ShowDialog() }
    if ([string]::IsNullOrWhiteSpace($script:RestoreResult)) { return $null }
    return $script:RestoreResult
}

# -----------------------------------------------------------------------------
# AN ARCHIVE'S TRASH - THE DELETION GATE, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The same manners as the remove gate, because the loss is of the same order:
# what goes is a folder on disk, no copy kept - the tar and the look beside it
# - and the exact name typed back is what opens the button (-ceq, case and
# all). Enter then deletes, Escape cancels, wherever the walk stands; the box
# holds the focus when the window is up.
function Show-ArchiveGate {
    param([string]$ArchiveName, [string]$Size)

    [xml]$deleteXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Delete archive" Width="540" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Text="WARNING: PERMANENT DELETION" FontSize="16" FontWeight="Bold" Foreground="#E04040"/>
        <TextBlock Name="TxtLead" Margin="0,10,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Margin="0,14,0,0" Text="To confirm DELETION, type the exact name of the archive:"/>
        <TextBox Name="TxtName" TabIndex="0" Margin="0,6,0,0" Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnArchiveCancel" TabIndex="1" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnArchiveDelete" TabIndex="2" Content="DELETE" Width="90" Height="28" IsEnabled="False" IsDefault="True"
                    Background="#A1260D" Foreground="#FFFFFF" BorderBrush="#BB2D0F"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $gate = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($deleteXaml))
    $gate.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $gate
    $gate.FindName("TxtLead").Text = "The archive '$ArchiveName' will be deleted and will not be restorable again."
    $txtName = $gate.FindName("TxtName")
    $btnDelete = $gate.FindName("BtnArchiveDelete")

    $gate.Add_ContentRendered({ $null = $txtName.Focus() })

    $script:ArchiveGateResult = $false

    # The button wakes only on the exact name, case and all - the console's -ceq.
    $txtName.Add_TextChanged({
        $btnDelete.IsEnabled = ($txtName.Text -ceq $ArchiveName)
    })
    $gate.FindName("BtnArchiveCancel").Add_Click({ $script:ArchiveGateResult = $false; $gate.Close() })
    $btnDelete.Add_Click({ $script:ArchiveGateResult = $true; $gate.Close() })

    Show-PopupExclusive $window { $null = $gate.ShowDialog() }
    return $script:ArchiveGateResult
}

# -----------------------------------------------------------------------------
# A LIVE INSTANCE'S ARCHIVE - THE NAME PROMPT, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The console's questions, folded into one window: the name the archive takes
# (the instance's own, prefilled), a note when that name is already taken -
# typing an existing name is how an archive is replaced, said and not done
# quietly - and the running warning, because the export needs a still disk.
# Enter archives, Escape cancels, an empty name is a cancel.
function Show-ArchivePrompt {
    param([string]$InstanceName, [bool]$IsRunning, [string]$ArchivesRoot)

    [xml]$archiveXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Archive instance" Width="540" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="TxtLead" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Name="TxtRunning" Margin="0,10,0,0" TextWrapping="Wrap" Foreground="#D7BA7D"
                   Text="It is running: it will be stopped for a consistent disk - anything unsaved in there is lost - then started again once the export is done."/>
        <TextBlock Margin="0,14,0,0" Text="Name of the archive:"/>
        <TextBox Name="TxtName" TabIndex="0" Margin="0,6,0,0" Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <TextBlock Name="TxtTaken" Margin="0,6,0,0" TextWrapping="Wrap" Foreground="#E04040" Visibility="Collapsed"
                   Text="An archive with this name exists: it will be replaced."/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnArchivePromptCancel" TabIndex="1" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnArchivePromptGo" TabIndex="2" Content="ARCHIVE" Width="90" Height="28" IsDefault="True"
                    Background="#33FF66" Foreground="#1E1E1E" BorderBrush="#33FF66"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $prompt = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($archiveXaml))
    $prompt.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $prompt
    $prompt.FindName("TxtLead").Text = "Write '$InstanceName' to an archive."
    if (-not $IsRunning) { $prompt.FindName("TxtRunning").Visibility = [System.Windows.Visibility]::Collapsed }

    $txtName = $prompt.FindName("TxtName")
    $txtTaken = $prompt.FindName("TxtTaken")
    $txtName.Text = $InstanceName

    $prompt.Add_ContentRendered({ $null = $txtName.Focus(); $txtName.SelectAll() })

    # The taken-name note follows the typing: the console says it too, once
    # the name is in.
    $txtName.Add_TextChanged({
        $taken = -not [string]::IsNullOrWhiteSpace($txtName.Text) -and
            (Test-Path (Join-Path $ArchivesRoot $txtName.Text.Trim()))
        $txtTaken.Visibility = if ($taken) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    })

    $script:ArchivePromptResult = $null
    $prompt.FindName("BtnArchivePromptCancel").Add_Click({ $script:ArchivePromptResult = $null; $prompt.Close() })
    $prompt.FindName("BtnArchivePromptGo").Add_Click({
        $script:ArchivePromptResult = $txtName.Text.Trim()
        $prompt.Close()
    })

    Show-PopupExclusive $window { $null = $prompt.ShowDialog() }
    if ([string]::IsNullOrWhiteSpace($script:ArchivePromptResult)) { return $null }
    return $script:ArchivePromptResult
}

# The tickboxes of a pack list, built into a panel, with their meaning kept on
# screen: the shared resolver reads them and the lines below speak the
# console's own sentences - the reasons included - so a pack that comes or
# goes without its why never happens. Everything the blocks read lives on
# $script:: a scriptblock writes its own scope, and one built here would look
# into a frame that is gone by the time a box is clicked. The last answer
# waits on $script:ChecklistSelection for whichever window asked.
function New-PackChecklist {
    param(
        $Panel,
        [string[]]$Installed,
        $Catalog,
        $TxtAdd,
        $TxtDel,
        $TxtNotes,
        [string]$NothingText
    )

    $script:ChecklistInstalled = $Installed
    $script:ChecklistCatalog = $Catalog
    $script:ChecklistTxtAdd = $TxtAdd
    $script:ChecklistTxtDel = $TxtDel
    $script:ChecklistTxtNotes = $TxtNotes
    $script:ChecklistNothingText = $NothingText
    $script:ChecklistSelection = $null

    # One box per offered pack - the same surface the console's checklist
    # shows, so the two ask the same question.
    $script:ChecklistEntries = @()
    foreach ($pack in @($Catalog.AvailablePacks | Where-Object { $_.Offered })) {
        $check = New-Object System.Windows.Controls.CheckBox
        $check.Content = "{0,-12} {1}" -f $pack.Name, $pack.Description
        $check.Margin = "0,3,0,3"
        $check.IsChecked = ($Installed -contains $pack.Name)
        $script:ChecklistEntries += [PSCustomObject]@{ Pack = $pack; Check = $check }
        $null = $Panel.Children.Add($check)
    }

    $RefreshAnswer = {
        $kept = @($script:ChecklistEntries | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Pack.Name })
        $selection = Resolve-PackSelection -Catalog $script:ChecklistCatalog -Installed $script:ChecklistInstalled -Kept $kept
        $script:ChecklistSelection = $selection

        if ($selection.ToAdd.Count -gt 0) {
            $line = "Will install : " + (@($selection.ToAdd | ForEach-Object { $_.Name }) -join ", ")
            $because = @()
            foreach ($pack in $selection.ToAdd) {
                if ($kept -notcontains $pack.Name) {
                    $who = @($selection.ToAdd | Where-Object { $_.Requires -contains $pack.Name } | ForEach-Object { $_.Name })
                    $because += ("{0}: required by {1}" -f $pack.Name, ($who -join " and "))
                }
            }
            if ($because.Count -gt 0) { $line += "`n(" + ($because -join "; ") + ")" }
            $script:ChecklistTxtAdd.Text = $line
            $script:ChecklistTxtAdd.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $script:ChecklistTxtAdd.Visibility = [System.Windows.Visibility]::Collapsed
        }

        if ($selection.ToRemove.Count -gt 0) {
            $line = "Will remove  : " + ($selection.ToRemove -join ", ")
            $because = @()
            foreach ($name in $selection.ToRemove) {
                if ($selection.Unticked -notcontains $name) { $because += ("{0}: nothing installed requires it any more" -f $name) }
            }
            if ($because.Count -gt 0) { $line += "`n(" + ($because -join "; ") + ")" }
            $line += "`nTheir tools leave, and the dependencies nothing needs any more."
            $script:ChecklistTxtDel.Text = $line
            $script:ChecklistTxtDel.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $script:ChecklistTxtDel.Visibility = [System.Windows.Visibility]::Collapsed
        }

        if ($selection.ToAdd.Count -eq 0 -and $selection.ToRemove.Count -eq 0) {
            $script:ChecklistTxtNotes.Text = $script:ChecklistNothingText
        } elseif ($selection.NotCarried.Count -gt 0) {
            $script:ChecklistTxtNotes.Text = "Installed here, not from this repository - left alone: " + ($selection.NotCarried -join ", ")
        } else {
            $script:ChecklistTxtNotes.Text = ""
        }
    }

    foreach ($entry in $script:ChecklistEntries) {
        $entry.Check.Add_Checked($RefreshAnswer)
        $entry.Check.Add_Unchecked($RefreshAnswer)
    }
    & $RefreshAnswer
}

# -----------------------------------------------------------------------------
# A LIVE INSTANCE'S PACKS - THE EDITOR, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The console's checklist question, in a window: one tickbox per pack this
# checkout offers, ticked for the ones installed, and the answer read live
# underneath - the same rules as the console, from the same resolver, so the
# two cannot drift. Returns the two lists to apply, or $null when cancelled;
# both empty is a real answer (nothing to do).
function Show-PackEditor {
    param([string]$InstanceName, [string[]]$Installed, $Catalog)

    [xml]$editorXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Packs" Width="560" SizeToContent="Height" MaxHeight="720"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="TxtLead" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <ScrollViewer MaxHeight="380" Margin="0,12,0,0" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="Boxes"/>
        </ScrollViewer>
        <TextBlock Name="TxtAdd" Margin="0,12,0,0" TextWrapping="Wrap" Foreground="#33FF66" Visibility="Collapsed"/>
        <TextBlock Name="TxtDel" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#C05050" Visibility="Collapsed"/>
        <TextBlock Name="TxtNotes" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#2F9E55"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnEditCancel" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnEditApply" Content="APPLY" Width="90" Height="28" IsDefault="True"
                    Background="#33FF66" Foreground="#1E1E1E" BorderBrush="#33FF66"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $editor = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($editorXaml))
    $editor.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $editor
    $editor.FindName("TxtLead").Text = "The packs of '$InstanceName'."

    New-PackChecklist -Panel $editor.FindName("Boxes") -Installed $Installed -Catalog $Catalog `
        -TxtAdd $editor.FindName("TxtAdd") -TxtDel $editor.FindName("TxtDel") -TxtNotes $editor.FindName("TxtNotes") `
        -NothingText "Nothing to do: '$InstanceName' already has exactly that."

    $script:PackEditResult = $null
    $editor.FindName("BtnEditCancel").Add_Click({ $script:PackEditResult = $null; $editor.Close() })
    $editor.FindName("BtnEditApply").Add_Click({
        $selection = $script:ChecklistSelection
        $script:PackEditResult = [PSCustomObject]@{
            ToAdd    = @($selection.ToAdd | ForEach-Object { $_.Name })
            ToRemove = @($selection.ToRemove)
        }
        $editor.Close()
    })

    Show-PopupExclusive $window { $null = $editor.ShowDialog() }
    return $script:PackEditResult
}

# -----------------------------------------------------------------------------
# A NEW INSTANCE - THE ADD FORM, WINDOW-SIDE
# -----------------------------------------------------------------------------
# build's first questions, answered in one window: the name - a name that
# exists is refused here, this road offers no destruction - and the user name,
# the Windows account's cleaned form prefilled. Both checked live, the red
# line under the box saying what is wrong. The packs are the same checklist as
# the editor's. Returns { Name; User; Packs }, or $null when cancelled; the
# run itself then gets a console window of its own, because it is long, it is
# loud, and it still has questions only it can ask.
function Show-AddInstance {
    param($Catalog, [string]$ProposedUser, [string]$InstancesRoot, $Manager)

    [xml]$addXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Add instance" Width="560" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Margin="0,10,0,0" Text="Instance name:"/>
        <TextBox Name="TxtName" Margin="0,6,0,0" Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <TextBlock Name="TxtNameError" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#E04040" Visibility="Collapsed"/>
        <TextBlock Margin="0,12,0,0" Text="User name:"/>
        <TextBox Name="TxtUser" Margin="0,6,0,0" Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <TextBlock Name="TxtUserError" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#E04040" Visibility="Collapsed"/>
        <TextBlock Margin="0,12,0,0" Text="Packs:"/>
        <ScrollViewer MaxHeight="260" Margin="0,6,0,0" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="Boxes"/>
        </ScrollViewer>
        <TextBlock Name="TxtAdd" Margin="0,12,0,0" TextWrapping="Wrap" Foreground="#33FF66" Visibility="Collapsed"/>
        <TextBlock Name="TxtDel" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#C05050" Visibility="Collapsed"/>
        <TextBlock Name="TxtNotes" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#2F9E55"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnAddCancel" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnAddCreate" Content="CREATE" Width="90" Height="28" IsDefault="True"
                    Background="#33FF66" Foreground="#1E1E1E" BorderBrush="#33FF66"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($addXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $form
    $txtName = $form.FindName("TxtName")
    $txtNameError = $form.FindName("TxtNameError")
    $txtUser = $form.FindName("TxtUser")
    $txtUserError = $form.FindName("TxtUserError")
    $txtUser.Text = $ProposedUser

    $form.Add_ContentRendered({ $null = $txtName.Focus() })

    # Live checks, the red line under the box saying what is wrong - on the
    # window's road a name that exists is refused here, never destroyed. The
    # verdicts live on $script:; the boxes are wired below.
    $CheckName = {
        $name = $txtName.Text.Trim()
        $problem = ""
        if (-not $name) {
            $problem = "Give a name."
        } elseif (-not $Manager.IsNameUsable($name)) {
            $problem = "Letters, digits, '.', '_' and '-' only."
        } elseif ((Get-DistroNames) -contains $name) {
            $problem = "An instance named '$name' already exists."
        } elseif ($Manager.IsPathOccupied((Join-Path $InstancesRoot $name))) {
            $problem = "A folder for '$name' already exists."
        }
        $txtNameError.Text = $problem
        $txtNameError.Visibility = if ($problem) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $script:AddNameOk = (-not $problem)
    }
    $CheckUser = {
        $user = $txtUser.Text.Trim()
        $problem = ""
        if ("$user" -cnotmatch '^[a-z][a-z0-9_-]*$') {
            $problem = "Lowercase letters, digits, '_' and '-' only, starting with a letter."
        }
        $txtUserError.Text = $problem
        $txtUserError.Visibility = if ($problem) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $script:AddUserOk = (-not $problem)
    }

    New-PackChecklist -Panel $form.FindName("Boxes") -Installed @() -Catalog $Catalog `
        -TxtAdd $form.FindName("TxtAdd") -TxtDel $form.FindName("TxtDel") -TxtNotes $form.FindName("TxtNotes") `
        -NothingText "No pack selected - it will start bare."

    $txtName.Add_TextChanged($CheckName)
    $txtUser.Add_TextChanged($CheckUser)
    & $CheckName
    & $CheckUser

    $script:AddResult = $null
    $form.FindName("BtnAddCancel").Add_Click({ $script:AddResult = $null; $form.Close() })
    $form.FindName("BtnAddCreate").Add_Click({
        # The red lines are the refusal: say them and stay open.
        & $CheckName
        & $CheckUser
        if ($script:AddNameOk -and $script:AddUserOk) {
            $script:AddResult = [PSCustomObject]@{
                Name  = $txtName.Text.Trim()
                User  = $txtUser.Text.Trim()
                Packs = @($script:ChecklistSelection.ToAdd | ForEach-Object { $_.Name })
            }
            $form.Close()
        }
    })

    Show-PopupExclusive $window { $null = $form.ShowDialog() }
    return $script:AddResult
}

# A scheme's colour as a brush: Windows Terminal writes them as "#rrggbb" or
# as "rgb(r, g, b)", and the preview paints both. Anything else - or nothing -
# answers $null, and the caller keeps its own fallback.
function ConvertTo-PreviewBrush {
    param([string]$Value)

    if ($Value -match '^#([0-9a-fA-F]{3})$') {
        $v = $Matches[1]
        $hex = "$($v[0])$($v[0])$($v[1])$($v[1])$($v[2])$($v[2])"
        return [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(
            [Convert]::ToInt32($hex.Substring(0, 2), 16),
            [Convert]::ToInt32($hex.Substring(2, 2), 16),
            [Convert]::ToInt32($hex.Substring(4, 2), 16)))
    }
    if ($Value -match '^#([0-9a-fA-F]{6})$') {
        $hex = $Matches[1]
        return [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(
            [Convert]::ToInt32($hex.Substring(0, 2), 16),
            [Convert]::ToInt32($hex.Substring(2, 2), 16),
            [Convert]::ToInt32($hex.Substring(4, 2), 16)))
    }
    if ($Value -match '^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)') {
        return [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(
            [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]))
    }
    return $null
}

# -----------------------------------------------------------------------------
# A LIVE INSTANCE'S LOOK - THE APPEARANCE FORM, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The console's theme menu in one window: the icon (letters and the colour
# pairs make-icon offers, or an image of your own), the font (the same filtered
# list the console shows, note included) and the colour scheme - each read from
# the module, so the two entrances keep the same lists. Nothing is applied
# here: the form answers, and the caller calls the engine. Returns the answer,
# or $null when cancelled; an image answers alone - it replaces the picture,
# not the recipe behind it.
function Show-Appearance {
    param(
        [string]$InstanceName,
        [bool]$HasFragment,
        $Fonts,
        [string]$CurrentFont,
        $Schemes,
        [string]$CurrentScheme,
        $Recipe,
        $Pairs,
        [string]$SuggestedText,
        [string]$IconPath,
        [string]$IconScript
    )

    [xml]$lookXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Appearance" Width="600" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="18">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Column="0">
        <TextBlock Name="TxtLead" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Name="TxtNoFragment" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#D7BA7D" Visibility="Collapsed"
                   Text="This instance has no Terminal profile of ours - nothing changed here would show."/>
        <TextBlock Margin="0,12,0,0" Text="Icon text:"/>
        <TextBox Name="TxtIconText" Margin="0,6,0,0" Width="120" HorizontalAlignment="Left"
                 Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <TextBlock Name="TxtIconError" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#E04040" Visibility="Collapsed"/>
        </StackPanel>
        <Image Name="ImgIconPreview" Grid.Column="1" Width="64" Height="64" VerticalAlignment="Top" Margin="14,0,0,0"
               RenderOptions.BitmapScalingMode="HighQuality"/>
        <StackPanel Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2">
        <TextBlock Margin="0,10,0,0" Text="Icon color:"/>
        <ComboBox Name="LstPairs" Margin="0,6,0,0"/>
        <TextBlock Margin="0,10,0,0" Text="Icon file:"/>
        <Grid Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Name="TxtIconPath" Grid.Column="0" FontSize="11" Foreground="#2F9E55"
                       TextTrimming="CharacterEllipsis" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <Button Name="BtnImage" Grid.Column="1" Content="Upload" Width="90" Height="28"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
        </Grid>
        <TextBlock Margin="0,14,0,0" Text="Font:"/>
        <ComboBox Name="LstFonts" Margin="0,6,0,0"/>
        <TextBlock Margin="0,4,0,0" Foreground="#2F9E55" Text="Get more Nerd Fonts at https://www.nerdfonts.com"/>
        <TextBlock Margin="0,14,0,0" Text="Colour scheme:"/>
        <ComboBox Name="LstSchemes" Margin="0,6,0,0"/>
        <TextBlock Margin="0,14,0,0" Text="Preview:"/>
        <Border Name="BrdPreview" Margin="0,6,0,0" Padding="8,6" CornerRadius="3"
                Background="#0C0C0C" BorderBrush="#3F3F46" BorderThickness="1">
            <StackPanel>
                <!-- A real session, colours and all: the prompt this house's
                     zsh draws (zsh/prompts/starship.toml) - directory in bold
                     yellow, branch in bold purple behind its glyph, character
                     in bold green - over two eza lines, the listing these
                     instances really show (permissions green for folders,
                     user yellow, dates magenta, folders blue with their
                     icons). Each run is tagged with the palette slot it takes
                     its colour from - the named colours the tools use ARE the
                     terminal palette - and the form repaints them with the
                     chosen scheme's own. -->
                <TextBlock Name="TxtPreview1" FontFamily="Consolas" FontSize="13" Foreground="#33FF66">
                    <Run Tag="c3" Text="[~/projects]" FontWeight="Bold"/>
                </TextBlock>
                <TextBlock Name="TxtPreview2" FontFamily="Consolas" FontSize="13" Foreground="#33FF66">
                    <Run Tag="c5" Text="&#xF126; main " FontWeight="Bold"/>
                    <Run Tag="c2" Text="&#x276F; " FontWeight="Bold"/>
                    <Run Tag="fg" Text="ls"/>
                </TextBlock>
                <TextBlock Name="TxtPreview3" FontFamily="Consolas" FontSize="13" Foreground="#33FF66">
                    <Run Tag="c2" Text="drwxr-xr-x"/>
                    <Run Tag="fg" Text="  -  "/>
                    <Run Tag="c3" Text="underfit"/>
                    <Run Tag="fg" Text="  "/>
                    <Run Tag="c4" Text="2 Oct 18:52"/>
                    <Run Tag="fg" Text="  "/>
                    <Run Tag="c4" Text="&#xF07B; .config"/>
                </TextBlock>
                <TextBlock Name="TxtPreview4" FontFamily="Consolas" FontSize="13" Foreground="#33FF66">
                    <Run Tag="fg" Text="-rw-r--r-- "/>
                    <Run Tag="c2" Text="165 "/>
                    <Run Tag="c3" Text="underfit"/>
                    <Run Tag="fg" Text="  "/>
                    <Run Tag="c4" Text="2 Oct 18:52"/>
                    <Run Tag="fg" Text="  &#xF15B; .wget-hsts"/>
                </TextBlock>
                <TextBlock Name="TxtPreview5" FontFamily="Consolas" FontSize="13" Foreground="#33FF66">
                    <Run Tag="c3" Text="[~/projects]" FontWeight="Bold"/>
                </TextBlock>
                <TextBlock Name="TxtPreview6" FontFamily="Consolas" FontSize="13" Foreground="#33FF66">
                    <Run Tag="c5" Text="&#xF126; main " FontWeight="Bold"/>
                    <Run Tag="c2" Text="&#x276F; " FontWeight="Bold"/>
                    <Run Tag="fg" Text="_"/>
                </TextBlock>
                <StackPanel Name="PnlPalette" Orientation="Horizontal" Margin="0,8,0,0"/>
            </StackPanel>
        </Border>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnLookCancel" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnLookApply" Content="APPLY" Width="90" Height="28" IsDefault="True"
                    Background="#33FF66" Foreground="#1E1E1E" BorderBrush="#33FF66"/>
        </StackPanel>
        </StackPanel>
    </Grid>
</Window>
"@

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($lookXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $form
    $txtIconPath = $form.FindName("TxtIconPath")
    $txtIconPath.Text = "$IconPath"
    $txtIconPath.ToolTip = "$IconPath"
    if (-not $HasFragment) { $form.FindName("TxtNoFragment").Visibility = [System.Windows.Visibility]::Visible }

    # The icon: the letters, and the colour pairs make-icon offers - each pair
    # named for the eye, the one in use marked.
    $txtIcon = $form.FindName("TxtIconText")
    $txtIcon.Text = $SuggestedText
    $txtIconError = $form.FindName("TxtIconError")
    $lstPairs = $form.FindName("LstPairs")
    $pairRows = @()
    foreach ($row in @($Pairs)) {
        $field = "$row" -split "`t"
        $here = if ($Recipe -and $Recipe.Top -eq $field[1] -and $Recipe.Bottom -eq $field[2]) { "  (current)" } else { "" }
        $pairRows += [PSCustomObject]@{ Name = $field[0]; Top = $field[1]; Bottom = $field[2]; TextColor = $field[3] }
        $null = $lstPairs.Items.Add("$($field[0])$here")
    }
    $pairIndex = 0
    if ($Recipe) {
        for ($i = 0; $i -lt $pairRows.Count; $i++) {
            if ($pairRows[$i].Top -eq $Recipe.Top -and $pairRows[$i].Bottom -eq $Recipe.Bottom) { $pairIndex = $i; break }
        }
    }
    if ($pairRows.Count -gt 0) { $lstPairs.SelectedIndex = $pairIndex }

    # The letters rule, spoken under the box as the form's other fields do: up
    # to three, letters or digits, a tab is sixteen pixels tall.
    $txtIcon.Add_TextChanged({
        $ok = ("$($txtIcon.Text)" -match '^[A-Za-z0-9]{1,3}$')
        $txtIconError.Text = if ($ok) { "" } else { "One to three letters or digits." }
        $txtIconError.Visibility = if ($ok) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    })

    $lstFonts = $form.FindName("LstFonts")
    $fontIndex = 0
    for ($i = 0; $i -lt $Fonts.Count; $i++) {
        $here = if ($Fonts[$i].Name -eq $CurrentFont) { "  (current)" } else { "" }
        if ($Fonts[$i].Name -eq $CurrentFont) { $fontIndex = $i }
        $null = $lstFonts.Items.Add("$($Fonts[$i].Name)$here")
    }
    if ($Fonts.Count -gt 0) { $lstFonts.SelectedIndex = $fontIndex }

    $lstSchemes = $form.FindName("LstSchemes")
    $schemeNames = @($Schemes.Keys | Sort-Object)
    $schemeIndex = 0
    for ($i = 0; $i -lt $schemeNames.Count; $i++) {
        $here = if ($schemeNames[$i] -eq $CurrentScheme) { "  (current)" } else { "" }
        if ($schemeNames[$i] -eq $CurrentScheme) { $schemeIndex = $i }
        $null = $lstSchemes.Items.Add("$($schemeNames[$i])$here")
    }
    if ($schemeNames.Count -gt 0) { $lstSchemes.SelectedIndex = $schemeIndex }

    # The preview: the sample lines in the chosen font, on the chosen scheme's
    # colours, with the sixteen palette colours under them - choosing blind was
    # the first complaint this window got.
    $brdPreview = $form.FindName("BrdPreview")
    $previewLines = @($form.FindName("TxtPreview1"), $form.FindName("TxtPreview2"), $form.FindName("TxtPreview3"),
        $form.FindName("TxtPreview4"), $form.FindName("TxtPreview5"), $form.FindName("TxtPreview6"))
    $pnlPalette = $form.FindName("PnlPalette")

    $UpdatePreview = {
        $fontName = if ($Fonts.Count -gt 0) { $Fonts[[Math]::Max(0, $lstFonts.SelectedIndex)].Name } else { $CurrentFont }
        if ($fontName) {
            # The constructor, not a string: a string that does not resolve
            # converts to something the eye cannot tell from "nothing
            # happened", and the preview was reported blind once already.
            $family = [Windows.Media.FontFamily]::new("$fontName")
            foreach ($line in $previewLines) { $line.FontFamily = $family }
        }

        $scheme = $null
        if ($schemeNames.Count -gt 0) { $scheme = $Schemes[$schemeNames[[Math]::Max(0, $lstSchemes.SelectedIndex)]] }
        $bg = ConvertTo-PreviewBrush "$($scheme.background)"
        $fg = ConvertTo-PreviewBrush "$($scheme.foreground)"
        $brdPreview.Background = if ($bg) { $bg } else { ConvertTo-PreviewBrush "#0C0C0C" }
        # The colours a run takes, by slot: Get-SchemeColour reads BOTH scheme
        # syntaxes - the named keys Terminal writes today (black, red, ...
        # brightWhite - measured: his One Half Dark had no palette list at
        # all) and the older sixteen-entry palette - so everything paints.
        $slotByIndex = @("Black", "DarkRed", "DarkGreen", "DarkYellow", "DarkBlue", "DarkMagenta", "DarkCyan", "Gray",
            "DarkGray", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White")
        foreach ($line in $previewLines) {
            $line.Foreground = if ($fg) { $fg } else { ConvertTo-PreviewBrush "#33FF66" }
            foreach ($run in @($line.Inlines)) {
                $brush = $null
                if ("$($run.Tag)" -eq 'fg') {
                    $brush = if ($fg) { $fg } else { ConvertTo-PreviewBrush "#33FF66" }
                } elseif ("$($run.Tag)" -match '^c(\d+)$') {
                    $idx = [int]$Matches[1]
                    if ($idx -lt $slotByIndex.Count) {
                        $brush = ConvertTo-PreviewBrush "$(Get-SchemeColour -Scheme $scheme -Name $slotByIndex[$idx])"
                    }
                }
                if ($brush) { $run.Foreground = $brush }
            }
        }

        $pnlPalette.Children.Clear()
        foreach ($slotName in $slotByIndex) {
            $entry = Get-SchemeColour -Scheme $scheme -Name $slotName
            $brush = ConvertTo-PreviewBrush "$entry"
            if (-not $brush) { continue }
            $swatch = New-Object System.Windows.Controls.Border
            $swatch.Width = 18
            $swatch.Height = 12
            $swatch.Margin = "0,0,2,0"
            $swatch.Background = $brush
            $null = $pnlPalette.Children.Add($swatch)
        }
    }
    $lstFonts.Add_SelectionChanged($UpdatePreview)
    $lstSchemes.Add_SelectionChanged($UpdatePreview)
    & $UpdatePreview

    $script:LookResult = $null
    $script:LookImage = $null

    # The icon's preview, top right: the drawing script renders the fields as
    # they stand - the same script every icon in the house goes through, so
    # the picture cannot lie - and a chosen image takes its place the moment
    # it is picked (it will take the icon's seat on APPLY too). Loading goes
    # through OnLoad: the file is read whole and let go, so the next draw can
    # overwrite it.
    $imgPreview = $form.FindName("ImgIconPreview")
    $tempIcon = Join-Path $env:TEMP "wsl-stack-icon-preview.png"

    $LoadIconFile = {
        param([string]$Path)
        try {
            $bmp = New-Object Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            # IgnoreImageCache, not just OnLoad: WPF caches decoded images by
            # URI, and the redraw writes the SAME temp path every time - the
            # upload only showed because its path is new at every pick. With
            # OnLoad the file is read whole and let go, so the next draw can
            # overwrite it.
            $bmp.CreateOptions = [Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
            $bmp.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.UriSource = [Uri]"$Path"
            $bmp.EndInit()
            $imgPreview.Source = $bmp
        } catch { }
    }

    $DrawPreview = {
        # The last action answers: editing the letters or the colours takes
        # the icon back from a chosen image - the path follows - and the
        # drawing redraws with what the fields say now. What the preview
        # shows is always what APPLY will do.
        $script:LookImage = $null
        $txtIconPath.Text = "$IconPath"
        $txtIconPath.ToolTip = "$IconPath"
        $text = "$($txtIcon.Text)"
        if ($text -notmatch '^[A-Za-z0-9]{1,3}$') { return }
        $pair = $null
        if ($pairRows.Count -gt 0) { $pair = $pairRows[[Math]::Max(0, $lstPairs.SelectedIndex)] }
        if (-not $pair -and -not $Recipe) { return }
        $top = if ($pair) { $pair.Top } else { $Recipe.Top }
        $bottom = if ($pair) { $pair.Bottom } else { $Recipe.Bottom }
        $ink = if ($pair) { $pair.TextColor } else { $Recipe.TextColor }
        try {
            $null = & $IconScript -Text $text.ToUpper() -Top $top -Bottom $bottom -TextColor $ink -Out $tempIcon -Quiet
            & $LoadIconFile $tempIcon
        } catch { }
    }
    $txtIcon.Add_TextChanged($DrawPreview)
    $lstPairs.Add_SelectionChanged($DrawPreview)
    & $DrawPreview

    # An image is a choice like the others: picked here and applied with
    # everything else on APPLY. The path under "Icon file:" is what answers -
    # it shows the file that will be used, the current one until another is
    # picked - and a note added under it while the old path stayed above read
    # as nothing. It still replaces the picture alone: the recipe behind it
    # stays, the console's own manners.
    $form.FindName("BtnImage").Add_Click({
        $Dialog = New-Object Microsoft.Win32.OpenFileDialog
        $Dialog.Title = "Icon image for '$InstanceName'"
        $Dialog.Filter = "Images (*.png;*.jpg;*.jpeg;*.ico;*.bmp)|*.png;*.jpg;*.jpeg;*.ico;*.bmp"
        if ($Dialog.ShowDialog($form) -eq $true) {
            $script:LookImage = $Dialog.FileName
            $txtIconPath.Text = $Dialog.FileName
            $txtIconPath.ToolTip = $Dialog.FileName
            & $LoadIconFile $Dialog.FileName
        }
    })

    $form.FindName("BtnLookCancel").Add_Click({ $script:LookResult = $null; $form.Close() })
    $form.FindName("BtnLookApply").Add_Click({
        # The letters are the icon's only rule; the lists answer for themselves.
        if ("$($txtIcon.Text)" -notmatch '^[A-Za-z0-9]{1,3}$') {
            return
        }
        $pair = $null
        if ($pairRows.Count -gt 0) { $pair = $pairRows[[Math]::Max(0, $lstPairs.SelectedIndex)] }
        $script:LookResult = [PSCustomObject]@{
            Image    = $script:LookImage
            Text     = "$($txtIcon.Text)".ToUpper()
            Top      = if ($pair) { $pair.Top } elseif ($Recipe) { $Recipe.Top } else { $null }
            Bottom   = if ($pair) { $pair.Bottom } elseif ($Recipe) { $Recipe.Bottom } else { $null }
            TextColor = if ($pair) { $pair.TextColor } elseif ($Recipe) { $Recipe.TextColor } else { $null }
            Font     = if ($Fonts.Count -gt 0) { $Fonts[[Math]::Max(0, $lstFonts.SelectedIndex)].Name } else { $CurrentFont }
            Scheme   = if ($schemeNames.Count -gt 0) { $schemeNames[[Math]::Max(0, $lstSchemes.SelectedIndex)] } else { $CurrentScheme }
        }
        $form.Close()
    })

    Show-PopupExclusive $window { $null = $form.ShowDialog() }
    return $script:LookResult
}

# -----------------------------------------------------------------------------
# A LIVE INSTANCE'S COPY - THE DUPLICATE PROMPT, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The console's one question for a copy: its name - nothing is proposed there,
# so the form offers the source's own with "-copy" behind it - and the guard
# is the engine's own answer (the inventory counts archived names too, and a
# copy onto any taken name is refused). The running warning rides along when
# it applies: the export stops the source, the console's own sentence. Enter
# duplicates, Escape cancels, an empty name is a cancel.
function Show-DuplicatePrompt {
    param([string]$InstanceName, [bool]$IsRunning, [string]$ProposedName, $Manager)

    [xml]$dupXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Duplicate" Width="540" SizeToContent="Height" MaxHeight="760"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#33FF66"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="TxtLead" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Name="TxtRunning" Margin="0,10,0,0" TextWrapping="Wrap" Foreground="#D7BA7D"
                   Text="It is running: it will be stopped for a consistent read - anything unsaved in there is lost - then started again once the copy is done."/>
        <TextBlock Margin="0,14,0,0" Text="Name of the copy:"/>
        <TextBox Name="TxtName" Margin="0,6,0,0" Background="#2D2D30" Foreground="#33FF66" BorderBrush="#555555" Padding="4"/>
        <TextBlock Name="TxtNameError" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="#E04040" Visibility="Collapsed"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnDupCancel" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0" IsCancel="True"
                    Background="#333337" Foreground="#33FF66" BorderBrush="#555555"/>
            <Button Name="BtnDupGo" Content="DUPLICATE" Width="110" Height="28" IsDefault="True"
                    Background="#33FF66" Foreground="#1E1E1E" BorderBrush="#33FF66"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $prompt = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($dupXaml))
    $prompt.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    & $DressWindow $prompt
    $prompt.FindName("TxtLead").Text = "Copy '$InstanceName'."
    if (-not $IsRunning) { $prompt.FindName("TxtRunning").Visibility = [System.Windows.Visibility]::Collapsed }

    $txtName = $prompt.FindName("TxtName")
    $txtNameError = $prompt.FindName("TxtNameError")
    $txtName.Text = $ProposedName

    $prompt.Add_ContentRendered({ $null = $txtName.Focus(); $txtName.SelectAll() })

    # The live check, the engine's own guard: usable, and free in the whole
    # inventory - the source itself included, so a copy onto it is refused
    # here as it would be there.
    $CheckName = {
        $name = $txtName.Text.Trim()
        $problem = ""
        if (-not $name) {
            $problem = "Give a name."
        } elseif (-not $Manager.IsNameUsable($name)) {
            $problem = "Letters, digits, '.', '_' and '-' only."
        } elseif (-not $Manager.IsNameAvailable($name)) {
            $problem = "An instance named '$name' already exists."
        }
        $txtNameError.Text = $problem
        $txtNameError.Visibility = if ($problem) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $script:DupNameOk = (-not $problem)
    }
    $txtName.Add_TextChanged($CheckName)
    & $CheckName

    $script:DupResult = $null
    $prompt.FindName("BtnDupCancel").Add_Click({ $script:DupResult = $null; $prompt.Close() })
    $prompt.FindName("BtnDupGo").Add_Click({
        & $CheckName
        if ($script:DupNameOk) {
            $script:DupResult = $txtName.Text.Trim()
            $prompt.Close()
        }
    })

    Show-PopupExclusive $window { $null = $prompt.ShowDialog() }
    return $script:DupResult
}

# The launch every row gesture shares: the runner to the temp folder, the
# trail cleared, the child out, the watcher on - the verb says what it does.
$LaunchJob = {
    param([string]$Verb, [string]$Name, [string]$ArchiveFirst)

    $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
    $RunnerPath = Join-Path $env:TEMP "wsl-stack-gui-job.ps1"
    Remove-Item -LiteralPath (Join-Path $env:TEMP "wsl-stack-gui-job.log") -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $RunnerPath -Value $JobRunnerSource -Encoding utf8NoBOM

    # The paths travel quoted - an array of arguments is joined blindly, and a
    # folder with a space would split it.
    $script:Child = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
        $Verb, $Name, $ArchiveFirst, "`"$ModulePath`""
    )
    $script:JobVerb = $Verb
    $script:JobName = $Name

    try {
        $script:Poller = New-Object System.Windows.Threading.DispatcherTimer
        $script:Poller.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:Poller.Add_Tick($WatchJob)
        $script:Poller.Start()
    } catch {
        & $SetStatus "Could not start watching the job: $($_.Exception.Message)" -Alert
        & $SetBusyState $false $null
    }
}

# The row icons bubble their clicks to the list, and the OriginalSource is the
# button: its DataContext is the row it sits on, and its Name says which
# gesture was asked. Open is the one instant gesture: the shell gets a window
# of its own and nothing is waited on, so it runs right here. Every other one:
# the row goes quiet, the window locks, and a child process does the work -
# remove and restore ask their window first, and only then.
$RowAction = [System.Windows.RoutedEventHandler]{
    param($sender, $e)
    $button = $e.OriginalSource
    $row = $button.DataContext
    if ($null -eq $row) { return }

    $inst = $row.Instance

    if ($button.Name -eq "BtnRowRestore") {
        # The name first - the archive's own, prefilled - then the console's
        # guards, said here instead of coming back through the trail as a
        # failed import.
        $name = Show-RestorePrompt $inst.Name
        if (-not $name) { return }
        if (-not $Manager.IsNameUsable($name)) {
            & $SetStatus "'$name' is not usable as an instance name (letters, digits, '.', '_' and '-' only)." -Alert
            return
        }
        if ((Get-DistroNames) -contains $name) {
            & $SetStatus "An instance named '$name' is already registered." -Alert
            return
        }
        if (Test-Path (Join-Path $Manager.InstancesRoot $name)) {
            & $SetStatus "An install folder named '$name' already exists." -Alert
            return
        }
        & $MarkRow $button
        & $SetBusyState $true "Restoring '$($inst.Name)' as '$name'..."
        & $LaunchJob "restore" $name "$($inst.ArchivePath)"
        return
    }
    if ($button.Name -eq "BtnRowDeleteArchive") {
        # The gate first - what is lost, the exact name typed back - and only
        # then the row goes quiet.
        if (-not (Show-ArchiveGate $inst.Name $row.Size)) { return }
        & $MarkRow $button
        & $SetBusyState $true "Deleting the archive '$($inst.Name)'..."
        & $LaunchJob "delete" $inst.Name "False"
        return
    }
    if ($button.Name -eq "BtnRowOpen") {
        try {
            $inst.OpenShell()
            $note = if ($row.Status -eq "Stopped") { " It was stopped: WSL starts it on the way in." } else { "" }
            & $SetStatus "A shell for '$($inst.Name)' opened in a new window.$note"
        } catch {
            & $SetStatus "Could not open a shell for '$($inst.Name)': $($_.Exception.Message)" -Alert
        }
        return
    }
    if ($button.Name -eq "BtnRowStart") {
        & $MarkRow $button
        & $SetBusyState $true "Starting '$($inst.Name)'..."
        & $LaunchJob "start" $inst.Name "False"
        return
    }
    if ($button.Name -eq "BtnRowStop") {
        & $MarkRow $button
        & $SetBusyState $true "Stopping '$($inst.Name)'..."
        & $LaunchJob "stop" $inst.Name "False"
        return
    }
    if ($button.Name -eq "BtnRowEdit") {
        # The catalogue and what the instance carries first: without them
        # there is no question to ask.
        $installed = $Manager.InstalledPacks($inst)
        if ($null -eq $installed) {
            & $SetStatus "'$($inst.Name)' did not say where its user's home is - its packs cannot be read." -Alert
            return
        }
        $catalog = Get-PackCatalog
        if ($catalog.AvailablePacks.Count -eq 0) {
            & $SetStatus "No pack found in the repository's packs folder." -Alert
            return
        }

        $selection = Show-PackEditor $inst.Name @($installed) $catalog
        if ($null -eq $selection) { return }
        if ($selection.ToAdd.Count -eq 0 -and $selection.ToRemove.Count -eq 0) {
            & $SetStatus "Nothing to do: '$($inst.Name)' already has exactly that."
            return
        }

        # The run gets a window of its own - visible, and the whole point:
        # installs can take minutes, and the déroulé is what there is to see.
        # No lock, no bandeau: the window is the progress.
        $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
        $RunnerPath = Join-Path $env:TEMP "wsl-stack-gui-packs.ps1"
        Set-Content -LiteralPath $RunnerPath -Value $EditRunnerSource -Encoding utf8NoBOM
        # Every argument quoted, the lists included: an empty list would
        # otherwise vanish from the command line and shift every argument
        # after it by one (measured - Import-Module received the wrong file,
        # and the error hid behind the runner's own catch).
        $null = Start-Process pwsh -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
            "`"$($inst.Name)`"", "`"$($selection.ToAdd -join ',')`"", "`"$($selection.ToRemove -join ',')`"", "`"$ModulePath`""
        )
        & $SetStatus "Editing the packs of '$($inst.Name)' in a window of its own."
        return
    }
    if ($button.Name -eq "BtnRowAppearance") {
        # Everything the form shows, read from the module and the icon script:
        # the lists the console's theme menu shows, so the two cannot drift.
        $IconScript = Join-Path $PSScriptRoot "..\..\assets\make-icon.ps1"
        $appearance = Get-InstanceAppearance -Name $inst.Name
        $recipe = Get-IconRecipe -Name $inst.Name
        $suggested = if ($recipe -and $recipe.Text) {
            $recipe.Text
        } else {
            "$(@(& $IconScript -Letters -Name $inst.Name | Select-Object -First 1)[0])"
        }
        $pairs = @(& $IconScript -ListPairs | Where-Object { $_ })
        $ourFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$($inst.Name).json"

        $look = Show-Appearance -InstanceName $inst.Name -HasFragment ([bool](Test-Path $ourFragment)) `
            -Fonts (@(Get-UsableFonts)) -CurrentFont $appearance.FontName `
            -Schemes (Get-ColorSchemes) -CurrentScheme $appearance.ColorScheme `
            -Recipe $recipe -Pairs $pairs -SuggestedText $suggested `
            -IconPath (Join-Path $inst.Path "terminal-icon.png") -IconScript $IconScript
        if ($null -eq $look) { return }

        try {
            $changed = @()
            if ($look.Image) {
                # The image took the icon's seat: it replaces the picture, the
                # recipe behind it stays - the console's own manners.
                $null = $Manager.SetIconImage($inst, $look.Image)
                $changed += "icon image '$([IO.Path]::GetFileName($look.Image))'"
            } else {
                $recipeChanged = $true
                if ($recipe -and $look.Text -eq $recipe.Text -and $look.Top -eq $recipe.Top -and
                    $look.Bottom -eq $recipe.Bottom -and $look.TextColor -eq $recipe.TextColor) {
                    $recipeChanged = $false
                }
                if ($recipeChanged -and $look.Top) {
                    $null = $Manager.SetIcon($inst, @{ Name = $inst.Name; Text = $look.Text; Top = $look.Top; Bottom = $look.Bottom; TextColor = $look.TextColor })
                    $changed += "icon '$($look.Text)'"
                }
            }
            if ($look.Font -and $look.Font -ne $appearance.FontName) {
                $null = $Manager.SetFont($inst, $look.Font)
                $changed += "font '$($look.Font)'"
            }
            if ($look.Scheme -and $look.Scheme -ne $appearance.ColorScheme) {
                $null = $Manager.SetColourScheme($inst, $look.Scheme)
                $changed += "colours '$($look.Scheme)'"
            }

            if ($changed.Count -eq 0) {
                & $SetStatus "Nothing changed on '$($inst.Name)'."
                return
            }
            Update-TerminalSettings
            & $SetStatus "Look of '$($inst.Name)' updated: $($changed -join ', ')."
        } catch {
            & $SetStatus "Could not change the look of '$($inst.Name)': $($_.Exception.Message)" -Alert
        }
        return
    }
    if ($button.Name -eq "BtnRowDuplicate") {
        # The name first - "-copy" behind the source's own - then the row goes
        # quiet: the copy is long, and the runner stops the source, checks the
        # room and starts it again when it is over.
        $name = Show-DuplicatePrompt $inst.Name ($row.Status -eq "Running") "$($inst.Name)-copy" $Manager
        if (-not $name) { return }
        & $MarkRow $button
        & $SetBusyState $true "Duplicating '$($inst.Name)' as '$name'..."
        & $LaunchJob "duplicate" $inst.Name $name
        return
    }
    if ($button.Name -eq "BtnRowArchive") {
        # The name first - the instance's own, prefilled - then the console's
        # rail: a name that is a path would land outside the archives folder.
        $name = Show-ArchivePrompt $inst.Name ($row.Status -eq "Running") $Manager.ArchivesRoot
        if (-not $name) { return }
        if (-not $Manager.IsNameUsable($name)) {
            & $SetStatus "'$name' is not usable as an archive name (letters, digits, '.', '_' and '-' only)." -Alert
            return
        }
        & $MarkRow $button
        & $SetBusyState $true "Archiving '$($inst.Name)' as '$name'..."
        & $LaunchJob "archive" $inst.Name $name
        return
    }
    if ($button.Name -eq "BtnRowCompact") {
        & $MarkRow $button
        & $SetBusyState $true "Compacting '$($inst.Name)'..."
        & $LaunchJob "compact" $inst.Name "False"
        return
    }

    # Remove: the gate first - what is lost, the exact name typed back - and
    # only then the row goes quiet.
    $confirm = Show-RemoveGate $inst
    if ($null -eq $confirm) { return }

    & $MarkRow $button
    & $SetBusyState $true "Removing '$($inst.Name)'..."
    & $LaunchJob "remove" $inst.Name "$([bool]$confirm.ArchiveFirst)"
}
$lstInstances.AddHandler([System.Windows.Controls.Button]::ClickEvent, $RowAction)

# No title bar any more: the window is dragged by its background. A press
# that lands on a button, a box or a scrollbar belongs to them - the walk up
# the tree decides, or every button press would start a drag.
$window.Add_MouseLeftButtonDown({
    param($sender, $e)
    $node = $e.OriginalSource
    try {
        while ($node -and $node -ne $window) {
            if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or
                $node -is [System.Windows.Controls.TextBox] -or
                $node -is [System.Windows.Controls.Primitives.ScrollBar] -or
                $node -is [System.Windows.Controls.ComboBox]) { return }
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        }
        $window.DragMove()
    } catch { }
})

# Q and Escape close it - unless the hand is typing in a field: the status
# line is the only box here, and a q inside it must stay a letter.
$window.Add_PreviewKeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Q -or $e.Key -eq [System.Windows.Input.Key]::Escape) {
        if ([System.Windows.Input.Keyboard]::FocusedElement -is [System.Windows.Controls.TextBox]) { return }
        $window.Close()
    }
})

# The fleet is read BEFORE the window opens - not on ContentRendered any
# more: the window now measures itself to its content, and rows arriving
# after the show would resize it in front of the user.
& $LoadFleet

# The height follows the content, with a floor and a ceiling: four rows'
# worth under it - an empty fleet must not leave a sliver - and the screen's
# working area over it: past that, the list scrolls inside the window.
$window.MinHeight = 240
$window.MaxHeight = [Math]::Max(360, [System.Windows.SystemParameters]::WorkArea.Height - 40)

# A plain window, never ShowDialog: Show-PopupExclusive hides it while a
# dialog is up, and hiding a dialog window ends it (DoDialogHide unblocks the
# modal frame - the script would run off its end). The wait is a frame of our
# own, not Dispatcher.Run: Run only comes back through a dispatcher shutdown
# - a one-way door - and the menu reopens this window in the same process.
$frame = [System.Windows.Threading.DispatcherFrame]::new()
$window.Add_Closed({ $frame.Continue = $false })
$window.Show()
[System.Windows.Threading.Dispatcher]::PushFrame($frame)
