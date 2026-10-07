# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader - the entry's using does not cover a file dot-sourced
# beside it (measured: [WslState] came up missing).
using module ..\..\WslModel\WslModel.psd1

# The fleet's desk, out of the command file: the status line's voices, the
# busy state, the list's own reader, and the row dispatch. Dot-sourced at the
# entry's script level - the blocks read the script scope where the controls
# and the state live, and the handlers read them by name.
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

    # The two voices read the chart's own colours: a game that recolours
    # the gui recolours the status line with it.
    $txtStatus.Foreground = if ($Alert) { $window.FindResource("AppDangerBrush") } else { $window.FindResource("AppNewsBrush") }
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
            # Measured with the face the window actually wears: the columns
            # keep their promise under a custom family too. The size is the
            # base 15 - the chosen size is a zoom outside this measurement.
            $typeface = New-Object Windows.Media.Typeface($window.FontFamily,
                [Windows.FontStyles]::Normal, [Windows.FontWeights]::Normal, [Windows.FontStretches]::Normal)
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
            # The frame's own 58 pixels - its margins and its line, all
            # OUTSIDE the zoom - do not scale: multiplied like the rest, the
            # budget left them a smaller and smaller share under 15, and at
            # 11 the list wore a scrollbar (measured: ~15 pixels short).
            $base = [Math]::Min(1100, [Math]::Max(560, $total + 84))
            $window.Width = ($base - 58) * ($GuiFonts.UiSize / 15.0) + 58
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

# One reload, a beat after a shell opened: opening boots a stopped distro,
# and WSL's own listing lags the boot - read right away, the row would still
# say Stopped. The tick is made at the script level: a block built inside a
# click reads its state through a scope that is gone when the timer fires
# (measured).
$ShellReloadTick = {
    param($source, $e)
    $source.Stop()
    & $LoadFleet
}

# The row icons bubble their clicks to the list, and the OriginalSource is the
# button: its DataContext is the row it sits on, and its Name says which
# gesture was asked. Open is the one instant gesture: the shell gets a window
# of its own and nothing is waited on, so it runs right here. Every other one:
# the row goes quiet, the window locks, and a child process does the work -
# remove and restore ask their window first, and only then.
$RowAction = [System.Windows.RoutedEventHandler]{
    param($source, $e)
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
            $wasStopped = ($row.Status -eq "Stopped")
            $inst.OpenShell()
            $note = if ($wasStopped) { " It was stopped: WSL starts it on the way in." } else { "" }
            & $SetStatus "A shell for '$($inst.Name)' opened in a new window.$note"
            # The row follows the boot, a beat later - the listing lags it.
            if ($wasStopped) {
                $shellReload = New-Object System.Windows.Threading.DispatcherTimer
                $shellReload.Interval = [TimeSpan]::FromMilliseconds(2000)
                $shellReload.Add_Tick($ShellReloadTick)
                $shellReload.Start()
            }
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
        # The paths hang off the entry's $GuiRoot: in a dot-sourced file,
        # $PSScriptRoot names THIS folder (the jobs controller paid for it -
        # exit 64, nothing in the trail).
        $ModulePath = (Resolve-Path (Join-Path $GuiRoot "..\WslStack\WslStack.psd1")).Path
        $RunnerPath = (Resolve-Path (Join-Path $GuiRoot "Runners\EditRunner.ps1")).Path
        # Every argument quoted, the lists included: an empty list would
        # otherwise vanish from the command line and shift every argument
        # after it by one (measured - Import-Module received the wrong file,
        # and the error hid behind the runner's own catch).
        $null = Start-Process pwsh -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$RunnerPath`"",
            "`"$($inst.Name)`"", "`"$($selection.ToAdd -join ',')`"", "`"$($selection.ToRemove -join ',')`"", "`"$ModulePath`""
        )
        & $SetStatus "Editing $($inst.Name)'s packs in a window of its own."
        return
    }
    if ($button.Name -eq "BtnRowAppearance") {
        # Everything the form shows, read from the module and the icon script:
        # the lists the console's theme menu shows, so the two cannot drift.
        $IconScript = (Resolve-Path (Join-Path $GuiRoot "..\make-icon.ps1")).Path
        $appearance = Get-InstanceAppearance -Name $inst.Name
        $recipe = Get-IconRecipe -Name $inst.Name
        $suggested = if ($recipe -and $recipe.Text) {
            $recipe.Text
        } else {
            "$(@(& $IconScript -Letters -Name $inst.Name | Select-Object -First 1)[0])"
        }
        $pairs = @(& $IconScript -ListPairs | Where-Object { $_ })
        $ourFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$($inst.Name).json"

        # The machine's two lists come from the session's one read - warm
        # since launch, see Get-GuiLookups - where re-reading them at every
        # open was this form's slow part.
        $machine = Get-GuiLookups

        $look = Show-Appearance -InstanceName $inst.Name -HasFragment ([bool](Test-Path $ourFragment)) `
            -Fonts $machine.Fonts -CurrentFont $appearance.FontName `
            -Schemes $machine.Schemes -CurrentScheme $appearance.ColorScheme `
            -Recipe $recipe -Pairs $pairs -SuggestedText $suggested `
            -IconPath (Join-Path $inst.Path "terminal-icon.png") -IconScript $IconScript
        if ($null -eq $look) { return }

        try {
            $changed = @()
            if ($look.Image) {
                # The image took the icon's seat: it replaces the picture, the
                # recipe behind it stays - the console's own manners. The
                # current seat comes back unchanged when nothing was picked
                # (opening on an image and applying as-is): copying a file
                # onto itself is not a change.
                $seat = Join-Path $inst.Path "terminal-icon.png"
                if ("$($look.Image)" -ne $seat) {
                    $null = $Manager.SetIconImage($inst, $look.Image)
                    $changed += "icon image '$([IO.Path]::GetFileName($look.Image))'"
                }
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
        # The gate first - an idle instance, and the archive offered - and
        # only then the row goes quiet.
        $confirm = Show-ShrinkGate $inst
        if ($null -eq $confirm) { return }
        & $MarkRow $button
        & $SetBusyState $true "Compacting '$($inst.Name)'..."
        & $LaunchJob "compact" $inst.Name "$([bool]$confirm.ArchiveFirst)"
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
