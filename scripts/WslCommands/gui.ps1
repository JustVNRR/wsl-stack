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

# The window's furniture, out of this file: the theme's manager and the
# controllers live under scripts/gui, dot sourced into the entry's scope -
# the faces and the dresser, the jobs, the dialogs' doors, the fleet's desk.
$GuiRoot = Join-Path $PSScriptRoot "..\gui"
. (Join-Path $GuiRoot "Theme\ThemeManager.ps1")
. (Join-Path $GuiRoot "Controllers\Jobs.ps1")
. (Join-Path $GuiRoot "Controllers\Popups.ps1")
. (Join-Path $GuiRoot "Controllers\Fleet.ps1")
$GuiFonts = Initialize-GuiFonts -AssetsDir (Join-Path $PSScriptRoot "..\..\assets")

# 1. The window's markup - the header, the list, an indeterminate bar for the
# long work, and the actions: Add and Refresh up in the header, and on every
# row Open, Start or Stop, Edit, Archive, Compact and the trash, with the
# restore and the trash alone on an archived row. It lives beside the theme,
# on disk, and reads and parses exactly as the here-string did.
$XamlPath = Join-Path $PSScriptRoot "..\gui\Views\MainWindow.xaml"
$reader = [System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($XamlPath))
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.Resources.MergedDictionaries.Add((Get-ThemeDictionary))
Set-WindowPhosphorFrame -Win $window -UiFont $GuiFonts.UiFont

# The face every icon button asks for - rows and header alike, templates
# included: a DynamicResource reaches them wherever they are built.
if ($GuiFonts.IconFont) { $window.Resources["IconFace"] = $GuiFonts.IconFont }

# The controls, by name
$lstInstances = $window.FindName("LstInstances")
$txtRoot      = $window.FindName("TxtRoot")
$txtStatus    = $window.FindName("TxtStatus")
$prgWork      = $window.FindName("PrgWork")
$btnRefresh   = $window.FindName("BtnRefresh")
$btnAdd       = $window.FindName("BtnAdd")
$btnQuit      = $window.FindName("BtnQuit")

$txtRoot.Text = "Root: $($Manager.InstancesRoot)"

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
    $RunnerPath = Join-Path $PSScriptRoot "..\gui\Runners\BuildRunner.ps1"
    $null = Start-Process pwsh -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
        "`"$($form.Name)`"", "`"$($form.User)`"", "`"$($form.Packs -join ',')`"", "`"$ModulePath`"", "`"$BuildScript`""
    )
    & $SetStatus "Creating '$($form.Name)' in a window of its own."
})
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
