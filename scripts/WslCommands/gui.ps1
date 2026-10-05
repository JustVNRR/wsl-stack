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

# 1. The XAML: the header, the list, an indeterminate bar for the long work,
# and the four actions - Refresh, Compact, Start, Stop.
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WSL Stack Manager" Height="450" Width="620"
        WindowStartupLocation="CenterScreen"
        Background="#1E1E1E" Foreground="#CCCCCC"
        FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="WSL Fleet" FontSize="20" FontWeight="SemiBold" Foreground="#4EC9B0"/>
            <TextBlock Name="TxtRoot" FontSize="11" Foreground="#808080" Margin="0,2,0,0"/>
        </StackPanel>

        <!-- The instances -->
        <ListView Name="LstInstances" Grid.Row="1" Background="#252526" BorderBrush="#3F3F46" Foreground="#E0E0E0">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Name" Width="200" DisplayMemberBinding="{Binding Name}"/>
                    <GridViewColumn Header="Status" Width="100" DisplayMemberBinding="{Binding Status}"/>
                    <GridViewColumn Header="Size" Width="110" DisplayMemberBinding="{Binding Size}"/>
                    <GridViewColumn Header="" Width="36">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Grid Width="30" Height="22">
                                    <Button Content="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                            Width="26" Height="22" Background="Transparent"
                                            Foreground="#C05050" BorderBrush="Transparent"
                                            HorizontalAlignment="Center"
                                            ToolTip="Remove this instance"/>
                                    <ProgressBar Name="RowSpinner" IsIndeterminate="True" Height="4" Width="24"
                                                 Visibility="Collapsed" VerticalAlignment="Center" HorizontalAlignment="Center"
                                                 Foreground="#4EC9B0" Background="#2D2D30" BorderThickness="0"/>
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
                     Foreground="#4EC9B0" Background="#2D2D30" BorderThickness="0"/>

        <!-- Actions -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="BtnRefresh" Content="Refresh" Width="80" Height="28" Margin="0,0,8,0"
                    Background="#333337" Foreground="#F1F1F1" BorderBrush="#555555"/>
            <Button Name="BtnCompact" Content="Compact" Width="85" Height="28" Margin="0,0,8,0"
                    Background="#2D5A27" Foreground="#FFFFFF" BorderBrush="#3E7B35" IsEnabled="False"/>
            <Button Name="BtnStart" Content="Start" Width="80" Height="28" Margin="0,0,8,0"
                    Background="#0E639C" Foreground="#FFFFFF" BorderBrush="#1177BB" IsEnabled="False"/>
            <Button Name="BtnStop" Content="Stop" Width="80" Height="28"
                    Background="#A1260D" Foreground="#FFFFFF" BorderBrush="#BB2D0F" IsEnabled="False"/>
        </StackPanel>

        <!-- Status line -->
        <TextBlock Name="TxtStatus" Grid.Row="4" Margin="0,8,0,0" FontSize="11" Foreground="#858585" Text="Ready."/>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# The controls, by name
$lstInstances = $window.FindName("LstInstances")
$txtRoot      = $window.FindName("TxtRoot")
$txtStatus    = $window.FindName("TxtStatus")
$prgWork      = $window.FindName("PrgWork")
$btnRefresh   = $window.FindName("BtnRefresh")
$btnCompact   = $window.FindName("BtnCompact")
$btnStart     = $window.FindName("BtnStart")
$btnStop      = $window.FindName("BtnStop")

$txtRoot.Text = "Root: $($Manager.InstancesRoot)"

# Busy and idle, for the whole window
$SetBusyState = {
    param([bool]$busy, [string]$statusMessage)

    $prgWork.Visibility = if ($busy) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $btnRefresh.IsEnabled = -not $busy
    $lstInstances.IsEnabled = -not $busy

    if ($busy) {
        $btnCompact.IsEnabled = $false
        $btnStart.IsEnabled   = $false
        $btnStop.IsEnabled    = $false
    } else {
        # The buttons follow the selection
        $selected = $lstInstances.SelectedItem
        if ($selected) {
            $isRunning = ($selected.Status -eq "Running")
            $btnStart.IsEnabled   = -not $isRunning
            $btnStop.IsEnabled    = $isRunning
            $btnCompact.IsEnabled = $true
        }
    }

    if ($statusMessage) { $txtStatus.Text = $statusMessage }
}

$LoadFleet = {
    $lstInstances.Items.Clear()
    $btnStart.IsEnabled   = $false
    $btnStop.IsEnabled    = $false
    $btnCompact.IsEnabled = $false

    try {
        # The manager's own list - the same the console doors show.
        $instances = @($Manager.OursHere())
        if ($instances.Count -eq 0) {
            $txtStatus.Text = "No WSL Stack instances found."
            return
        }

        foreach ($inst in $instances) {
            $isRunning = ($inst.State -eq [WslState]::Running)
            # The disk's size, the way the console's lists read it: the folder
            # holds ext4.vhdx, and Format-Size spells the bytes.
            $sizeStr = Format-Size (Get-VhdxSize $inst.Path)

            $item = [PSCustomObject]@{
                Name     = $inst.Name
                Status   = if ($isRunning) { "Running" } else { "Stopped" }
                Size     = $sizeStr
                Instance = $inst
            }
            $null = $lstInstances.Items.Add($item)
        }
        $txtStatus.Text = "$($instances.Count) instance(s) loaded."
    } catch {
        $txtStatus.Text = "Error reading instances: $($_.Exception.Message)"
    }
}

# The watcher every job the window starts shares - created HERE, at the script
# level, where the scope every handler reads from stays alive: a block made
# inside a click handler reads its state through a scope that is gone when the
# timer fires (measured: the band scrolled, and nothing else ever happened).
# Whatever happened to the job, this reports: EndInvoke shows return values and
# never the errors - a job can come back empty and silent - so the stream is
# read too, and the ending (status, re-enable, refresh) sits in a finally that
# nothing can skip.
$WatchJob = {
    # The early way out stays outside the try: a return under a finally runs
    # the finally - it would lower the busy state on every tick.
    if ($null -eq $script:Job -or -not $script:JobHandle.IsCompleted) { return }

    try {
        $script:Poller.Stop()

        $failure = $null
        $result = $null
        try {
            $result = @($script:Job.EndInvoke($script:JobHandle))[-1]
        } catch {
            $failure = $_.Exception.Message
        }
        if ($script:Job.Streams.Error.Count -gt 0) {
            $failure = (@($script:Job.Streams.Error | ForEach-Object { $_.Exception.Message }) -join " / ")
        }
        $script:Job.Dispose()
        $script:Job = $null

        if ($failure) {
            $txtStatus.Text = "Failed to $($script:JobVerb) '$($script:JobName)': $failure"
        } elseif ($null -eq $result) {
            $txtStatus.Text = "The $($script:JobVerb) of '$($script:JobName)' finished, but nothing came back to report."
        } elseif ($script:JobVerb -eq "compact") {
            $txtStatus.Text = "Compacted '$($script:JobName)'. Reclaimed: $([math]::Round($result.Freed / 1MB, 1)) MB."
        } else {
            $txtStatus.Text = "Removed '$($script:JobName)'. Folder: $($result.Removed.FolderState)."
        }
    } catch {
        # The watcher itself failed: say it here - a dead watcher must not look
        # like a job that never ends.
        $txtStatus.Text = "The watcher failed: $($_.Exception.Message)"
    } finally {
        & $SetBusyState $false $null
        & $LoadFleet
    }
}

# Selection
$lstInstances.Add_SelectionChanged({
    $selected = $lstInstances.SelectedItem
    if ($null -eq $selected) {
        $btnStart.IsEnabled   = $false
        $btnStop.IsEnabled    = $false
        $btnCompact.IsEnabled = $false
        return
    }

    $isRunning = ($selected.Status -eq "Running")
    $btnStart.IsEnabled   = -not $isRunning
    $btnStop.IsEnabled    = $isRunning
    $btnCompact.IsEnabled = $true
})

# The watcher first: a click here drains whatever the timer has not - if the
# tick ever fails to fire, Refresh still ends the job and reports it.
$btnRefresh.Add_Click({ & $WatchJob; & $LoadFleet })

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
        Title="Remove instance" Height="380" Width="540"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E1E" Foreground="#CCCCCC"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Text="WARNING: PERMANENT DESTRUCTION" FontSize="16" FontWeight="Bold" Foreground="#E04040"/>
        <TextBlock Name="TxtLead" Margin="0,10,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Margin="0,10,0,0" TextWrapping="Wrap" Foreground="#C0C0C0">Proceeding will PERMANENTLY DESTROY this distribution, erasing its install folder, its virtual disk (VHDX), and everything in /home - projects, SSH keys, all of it. This operation CANNOT be undone.</TextBlock>
        <CheckBox Name="ChkArchive" Margin="0,12,0,0" Foreground="#CCCCCC" Content="Archive it first (a copy the restore command can bring back)"/>
        <TextBlock Margin="0,14,0,0" Text="To confirm DESTRUCTION, type the exact name of the instance:"/>
        <TextBox Name="TxtName" Margin="0,6,0,0" Background="#2D2D30" Foreground="#F1F1F1" BorderBrush="#555555" Padding="4"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnGateCancel" Content="Cancel" Width="80" Height="28" Margin="0,0,8,0"
                    Background="#333337" Foreground="#F1F1F1" BorderBrush="#555555"/>
            <Button Name="BtnGateRemove" Content="REMOVE" Width="90" Height="28" IsEnabled="False"
                    Background="#A1260D" Foreground="#FFFFFF" BorderBrush="#BB2D0F"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $gate = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($gateXaml))
    $gate.FindName("TxtLead").Text = "The WSL distribution '$($Instance.Name)' and ALL its data will be deleted."
    $txtName = $gate.FindName("TxtName")
    $btnRemove = $gate.FindName("BtnGateRemove")
    $chkArchive = $gate.FindName("ChkArchive")

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

    $null = $gate.ShowDialog()
    return $script:GateResult
}

# The trash buttons live in the rows: the click bubbles to the list, and the
# OriginalSource is the button - its DataContext is the row it sits on.
$RemoveRow = [System.Windows.RoutedEventHandler]{
    param($sender, $e)
    $row = $e.OriginalSource.DataContext
    if ($null -eq $row) { return }

    $inst = $row.Instance
    $confirm = Show-RemoveGate $inst
    if ($null -eq $confirm) { return }

    # The row says it is working: its trash gives way to the little scrolling
    # band. Cosmetic - the deletion must not hinge on it.
    try {
        $cell = $e.OriginalSource.Parent
        $cell.Children[1].Visibility = [System.Windows.Visibility]::Visible
        $e.OriginalSource.Visibility = [System.Windows.Visibility]::Collapsed
    } catch { }

    & $SetBusyState $true "Removing '$($inst.Name)'..."

    # The same shape as Compact's: a runspace of its own, no class named - the
    # manager comes from the module's own factory, and everything else is
    # method calls. The handle lives in the script scope: the click handler is
    # gone by the time the timer fires.
    $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
    $script:Job = [powershell]::Create().
        AddScript({
            param($Module, $Name, $ArchiveFirst)
            Import-Module $Module -Force
            $mgr = New-InstanceManager
            $inst = @($mgr.OursHere()) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
            if (-not $inst) { throw "'$Name' is not in our list any more." }
            $mgr.Unregister($inst, [bool]$ArchiveFirst)
        }).
        AddArgument($ModulePath).
        AddArgument($inst.Name).
        AddArgument([bool]$confirm.ArchiveFirst)
    $script:JobVerb = "remove"
    $script:JobName = $inst.Name
    $script:JobHandle = $script:Job.BeginInvoke()

    # 3. The window's shared watcher polls, on its own thread, where painting
    # happens. If watching cannot even start, that speaks too - the console is
    # held by the window, and silence is a band that scrolls forever.
    try {
        $script:Poller = New-Object System.Windows.Threading.DispatcherTimer
        $script:Poller.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:Poller.Add_Tick($WatchJob)
        $script:Poller.Start()
    } catch {
        $txtStatus.Text = "Could not start watching the job: $($_.Exception.Message)"
        & $SetBusyState $false $null
    }
}
$lstInstances.AddHandler([System.Windows.Controls.Button]::ClickEvent, $RemoveRow)

# -----------------------------------------------------------------------------
# THE COMPACT ACTION, OFF THE UI THREAD
# -----------------------------------------------------------------------------
$btnCompact.Add_Click({
    $selected = $lstInstances.SelectedItem
    if (-not $selected) { return }

    # 1. Lock the window, show the bar
    & $SetBusyState $true "Compacting '$($selected.Name)' (this may take a few minutes)..."

    # 2. The work goes to a runspace of its own, and names no class at all: a
    # fresh runspace resolves no type literal - "Unable to find type
    # [WslInstanceManager]", and silently, it sleeps in the error stream
    # (measured) - so the manager comes from the module's own factory, and
    # everything else is method calls. The handle lives in the script scope:
    # the click handler is gone by the time the timer below fires.
    $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
    $script:Job = [powershell]::Create().
        AddScript({
            param($Module, $Name)
            Import-Module $Module -Force
            $mgr = New-InstanceManager
            $inst = @($mgr.OursHere()) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
            if (-not $inst) { throw "'$Name' is not in our list any more." }
            $mgr.Shrink($inst)
        }).
        AddArgument($ModulePath).
        AddArgument($selected.Name)
    $script:JobVerb = "compact"
    $script:JobName = $selected.Name
    $script:JobHandle = $script:Job.BeginInvoke()

    # 3. The window's shared watcher polls, on its own thread, where painting
    # happens. If watching cannot even start, that speaks too - the console is
    # held by the window, and silence is a band that scrolls forever.
    try {
        $script:Poller = New-Object System.Windows.Threading.DispatcherTimer
        $script:Poller.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:Poller.Add_Tick($WatchJob)
        $script:Poller.Start()
    } catch {
        $txtStatus.Text = "Could not start watching the job: $($_.Exception.Message)"
        & $SetBusyState $false $null
    }
})

# Start the selected one
$btnStart.Add_Click({
    $selected = $lstInstances.SelectedItem
    if (-not $selected) { return }

    $selected.Instance.Start()
    & $LoadFleet
})

# Stop the selected one
$btnStop.Add_Click({
    $selected = $lstInstances.SelectedItem
    if (-not $selected) { return }

    $selected.Instance.Stop()
    & $LoadFleet
})

$window.Add_ContentRendered({ & $LoadFleet })
$null = $window.ShowDialog()
