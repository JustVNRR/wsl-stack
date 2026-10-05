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
            $sizeStr = if (Test-Path $inst.Path) {
                $bytes = (Get-Item $inst.Path).Length
                "{0:N2} GB" -f ($bytes / 1GB)
            } else { "-" }

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

$btnRefresh.Add_Click({ & $LoadFleet })

# -----------------------------------------------------------------------------
# THE COMPACT ACTION, OFF THE UI THREAD
# -----------------------------------------------------------------------------
$btnCompact.Add_Click({
    $selected = $lstInstances.SelectedItem
    if (-not $selected) { return }

    $distroName = $selected.Name
    $distroObj  = $selected.Instance

    # 1. Lock the window, show the bar
    & $SetBusyState $true "Compacting '$distroName' in background (this may take a few minutes)..."

    # 2. The work goes to a background thread
    [System.Threading.Tasks.Task]::Run([Action]{
        $errorMessage = $null
        $result = $null

        try {
            # The engine's job: stop, compact, restart when it was running
            $result = $Manager.Shrink($distroObj)
        } catch {
            $errorMessage = $_.Exception.Message
        }

        # 3. Back to the UI thread to talk to the window
        $window.Dispatcher.Invoke([Action]{
            if ($errorMessage) {
                $txtStatus.Text = "Failed to compact '$distroName': $errorMessage"
            } else {
                $freedMb = [math]::Round($result.Freed / 1MB, 1)
                $txtStatus.Text = "Compacted '$distroName'. Reclaimed: $freedMb MB."
            }

            & $SetBusyState $false $null
            & $LoadFleet
        })
    })
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
