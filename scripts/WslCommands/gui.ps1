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
# the faces and the dresser, the jobs, the dialogs' doors.
$GuiRoot = Join-Path $PSScriptRoot "..\gui"
. (Join-Path $GuiRoot "Theme\ThemeManager.ps1")
. (Join-Path $GuiRoot "Controllers\Jobs.ps1")
. (Join-Path $GuiRoot "Controllers\Popups.ps1")
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
        $RunnerPath = Join-Path $PSScriptRoot "..\gui\Runners\EditRunner.ps1"
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
