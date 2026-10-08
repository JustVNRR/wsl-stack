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
$AssetsDir = Join-Path $PSScriptRoot "..\..\..\assets"
$GuiSettings = Get-GuiSettings
$GuiFonts = Initialize-GuiFonts -AssetsDir $AssetsDir
# The saved face, resolved to its object; a name that matches nothing - a
# settings file pointing at a font since deleted - keeps the shipped one.
$chosenFont = Resolve-UiFont -AssetsDir $AssetsDir -Name $GuiSettings.FontFamily
if ($chosenFont) { $GuiFonts.UiFont = $chosenFont }
$GuiFonts.UiSize = $GuiSettings.FontSize

# How many exclusive dialogs are up right now: the gate keeps the count,
# the theme's sink reads it (a fade completing after the last close must
# not hide the window the gate has just brought back).
$DialogDepth = 0

# The machine's font list and the Terminal's schemes, read at most once
# per session: both are heavy at the read (every family probed glyph by
# glyph, every Terminal package asked) and neither moves while the window
# is open. The settings window and the appearance form share them - and
# the reading starts right here, in a thread of its own, so the first of
# the two plucks a finished answer instead of paying the probe (see
# Get-GuiLookups, which harvests it - or reads the lists itself when a
# popup opened before the thread finished).
$GuiFontList = $null
$GuiSchemeList = $null
$GuiLookupJob = Start-ThreadJob -ScriptBlock {
    param($ModulePath)
    Import-Module $ModulePath
    @{ Fonts = @(Get-UsableFonts); Schemes = Get-ColorSchemes }
} -ArgumentList (Resolve-Path (Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1")).Path

# 1. The window's markup - the header, the list, an indeterminate bar for the
# long work, and the actions: Add and Refresh up in the header, and on every
# row Open, Start or Stop, Edit, Archive, Compact and the trash, with the
# restore and the trash alone on an archived row. It lives beside the theme,
# on disk, and reads and parses exactly as the here-string did.
$XamlPath = Join-Path $PSScriptRoot "..\gui\Views\MainWindow.xaml"
$reader = [System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($XamlPath))
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.Resources.MergedDictionaries.Add((Get-ThemeDictionary))
Set-WindowPhosphorFrame -Win $window -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize

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
$btnSettings  = $window.FindName("BtnSettings")
$btnTheme     = $window.FindName("BtnTheme")
$btnQuit      = $window.FindName("BtnQuit")

$txtRoot.Text = "Root: $($Manager.InstancesRoot)"

# The sun and the moon: the theme's other version. The button has nothing
# to switch when the theme is a one-version file - it stands disabled -
# and its icon shows what a click brings: a sun while dark, a moon while
# light.
$UpdateThemeButton = {
    $btnTheme.IsEnabled = [bool](Test-GuiThemeHasLight -AssetsDir $AssetsDir -Name $GuiSettings.ColourSet)
    $light = ($GuiSettings.ColourVariant -eq "Light")
    $icon = if ($light) { 0xF186 } else { 0xF185 }
    $btnTheme.Content = [string][char]$icon
    $btnTheme.ToolTip = if ($light) { "Switch to dark" } else { "Switch to light" }
}

# The watcher first: a click here drains whatever the timer has not - if the
# tick ever fails to fire, Refresh still ends the job and reports it.
$btnRefresh.Add_Click({ & $WatchJob; & $LoadFleet })
$btnQuit.Add_Click({ $window.Close() })

# The safety net: a UI-thread exception kills the process outright - a family
# whose file is gone throws deep in the text stack (measured). Caught here,
# said on the status line, and the window lives on. The handler is kept as a
# named object: the finally below unhooks THIS one (the dispatcher belongs
# to the process, and a handler left on it pins the whole launch - the
# window, its rows - for the life of the terminal).
$safetyNet = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
    param($source, $e)
    $e.Handled = $true
    & $SetStatus "A drawing failed: $($e.Exception.Message)" -Alert
}
$window.Dispatcher.Add_UnhandledException($safetyNet)

# Settings: the gui's own face - the family, its size, the colour set.
# Applied on the spot to this window; the popups follow on their next
# open, which is where their dresser reads the face from.
$btnSettings.Add_Click({
    # The family really worn, not the saved name - which can be stale (a
    # font since deleted) - so the select stands on the truth; with nothing
    # resolved the XAML's own face stands, Segoe UI.
    $worn = "Segoe UI"
    if ($GuiFonts.UiFont) {
        $worn = "$($GuiFonts.UiFont.FamilyNames.Values | Select-Object -First 1)"
        if (-not $worn) { $worn = "$($GuiFonts.UiFont.Source)" -replace '^\./#', '' }
    }
    $look = Show-GuiSettings -AssetsDir $AssetsDir -CurrentFamily $worn -CurrentSize $GuiSettings.FontSize -CurrentColourSet $GuiSettings.ColourSet -CurrentRoot $Manager.InstancesRoot
    if ($null -eq $look) { return }
    # A folder face's file must be on disk right now - the filesystem is the
    # truth. NOT a rendered glyph: rendering resolves the family NAME through
    # the Windows font cache, which can still point it at a file that is gone
    # (measured: it refused a just-uploaded face whose file sat right there).
    if ($look.Folder) {
        $faceFile = @(Get-ChildItem $look.Folder -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in ".ttf", ".otf" })
        if ($faceFile.Count -eq 0) {
            & $SetStatus "'$($look.Name)' cannot be used: its file seems gone." -Alert
            return
        }
    }
    $GuiSettings.FontFamily = $look.Name
    $GuiSettings.FontSize = $look.Size
    $GuiSettings.ColourSet = $look.ColourSet
    Save-GuiSettings $GuiSettings
    $GuiFonts.UiFont = $look.Family
    $GuiFonts.UiSize = $look.Size
    # The colour set: the window's copy of the chart is swapped for a
    # fresh one wearing it - every reference is dynamic, so the window
    # repaints itself on the spot.
    $window.Resources.MergedDictionaries[0] = (Get-ThemeDictionary)
    & $UpdateThemeButton
    Set-WindowPhosphorFrame -Win $window -UiFont $look.Family -UiFontSize $look.Size
    # The columns re-measure under the new face, and the fitted width follows
    # the zoom - then the face speaks, after the reload's own count line.
    & $LoadFleet
    $setName = if ($look.ColourSet) { $look.ColourSet } else { "default" }
    & $SetStatus "Window face: '$($look.Name)' at $($look.Size) pt, theme '$setName'. Popups follow on their next open."

    # The working folder, when it was changed: the whole fleet follows, by the
    # migrate command in a console of its own - the console IS the log - and
    # the window closes behind it. Nothing moves on one Enter: the red CONFIRM
    # explains first. The console waits for a key and reopens this manager.
    $newRoot = "$($look.Root)".Trim().Trim('"').TrimEnd('\')
    if ($newRoot -and ($newRoot -ne $Manager.InstancesRoot.TrimEnd('\'))) {
        if (Show-GuiConfirm -Owner $window -Title "Move the fleet" -Question "All existing instances will be archived and moved to '$newRoot'. Continue?") {
            $RunnerPath = Join-Path $PSScriptRoot "..\gui\Runners\MigrateRunner.ps1"
            $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
            $Entry = Join-Path $PSScriptRoot "..\..\..\wsl.ps1"
            Start-Process pwsh -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
                "`"$newRoot`"", "`"$ModulePath`"", "`"$Entry`""
            )
            $window.Close()
        }
    }
})

# The same theme's other version, on the spot: the chart's copy is swapped
# like the settings window does, and the choice is kept (the machine's
# taste). Nothing else moves - the colours ride on no measurement.
$btnTheme.Add_Click({
    $GuiSettings.ColourVariant = if ($GuiSettings.ColourVariant -eq "Light") { "Dark" } else { "Light" }
    Save-GuiSettings $GuiSettings
    $window.Resources.MergedDictionaries[0] = (Get-ThemeDictionary)
    & $UpdateThemeButton
    $worn = if ($GuiSettings.ColourVariant -eq "Light") { "light" } else { "dark" }
    & $SetStatus "The window wears '$($GuiSettings.ColourSet)', $worn version."
})

# The build's own watcher, beside the row jobs': the form's run opens a
# console of its own - no trail to read, the console IS the log - and this
# only asks when it has ended, then rereads the fleet so the new instance
# shows up without the refresh button. Script level, for the reason the job
# watcher is: the tick reads the scope the click handler writes.
$WatchBuild = {
    if ($null -eq $script:BuildChild -or -not $script:BuildChild.HasExited) { return }
    $script:BuildWatch.Stop()
    $script:BuildChild = $null
    & $LoadFleet
    & $SetStatus "The build ended - the fleet was reread."
}

# Add: the form first, then the run in a console window of its own - the real
# entry, not a copy of it, so the console's build and this one cannot drift
# apart. It stays interactive there: the account the image already carries,
# the Docker image, Docker Desktop, and the shell at the end.
$btnAdd.Add_Click({
    # The Docker check rides behind the form now - it used to hold the door
    # for a second and told nothing the questions could not (see
    # Show-AddInstance).
    $catalog = Get-PackCatalog
    $form = Show-AddInstance -Catalog $catalog -ProposedUser (Get-WindowsUserProposal) -InstancesRoot $Manager.InstancesRoot -Manager $Manager
    if ($null -eq $form) { return }

    $ModulePath = Join-Path $PSScriptRoot "..\WslStack\WslStack.psd1"
    $BuildScript = Join-Path $PSScriptRoot "build.ps1"
    $RunnerPath = Join-Path $PSScriptRoot "..\gui\Runners\BuildRunner.ps1"
    $script:BuildChild = Start-Process pwsh -PassThru -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
        "`"$($form.Name)`"", "`"$($form.User)`"", "`"$($form.Packs -join ',')`"",
        "`"$($form.Dockerfile)`"", "`"$($form.FirstBoot)`"", "`"$($form.Image)`"",
        "`"$ModulePath`"", "`"$BuildScript`""
    )
    $script:BuildWatch = New-Object System.Windows.Threading.DispatcherTimer
    $script:BuildWatch.Interval = [TimeSpan]::FromMilliseconds(1000)
    $script:BuildWatch.Add_Tick($WatchBuild)
    $script:BuildWatch.Start()
    & $SetStatus "Creating '$($form.Name)' in a window of its own."
})
$lstInstances.AddHandler([System.Windows.Controls.Button]::ClickEvent, $RowAction)

# No title bar any more: the window is dragged by its background. A press
# that lands on a button, a box or a scrollbar belongs to them - the walk up
# the tree decides, or every button press would start a drag.
$window.Add_MouseLeftButtonDown({
    param($source, $e)
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
    param($source, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Q -or $e.Key -eq [System.Windows.Input.Key]::Escape) {
        if ([System.Windows.Input.Keyboard]::FocusedElement -is [System.Windows.Controls.TextBox]) { return }
        $window.Close()
    }
})

# The theme button stands tuned before the window opens.
& $UpdateThemeButton

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
try {
    $window.Show()
    # The keys need a focus to travel from - a window with no focused
    # element listens to nothing (measured: Q and Escape were dead until
    # the list was clicked). The list takes it at launch, so the window
    # starts in the state a click would give it.
    $null = $lstInstances.Focus()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
} finally {
    # Whichever way the pump came back - not only the window's own close
    # (the finally is the certain one): nothing of this launch stays hooked
    # to the process. The safety net goes back off the dispatcher, and a
    # running job's poller stops - left ticking, it would hold this launch
    # until the child ends (a build: minutes), the dispatcher living as long
    # as the terminal does.
    $window.Dispatcher.Remove_UnhandledException($safetyNet)
    if ($Poller) { $Poller.Stop() }
}
