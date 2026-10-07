# The dialogs' doors, out of the command file: the exclusive gate and the
# Show-* windows. Dot-sourced at the entry's script level, where the
# handlers read them by name; the XAML paths hang off the entry's $GuiRoot
# ($PSScriptRoot would name this folder).
# Every popup goes through here: the fleet window steps aside while a dialog
# is up - visible but deaf behind a modal is a trap - and comes back when the
# dialog closes. The parent must be a plain window, never a dialog: hiding a
# dialog window runs WPF's dialog teardown (DoDialogHide unblocks the modal
# frame - the ShowDialog behind it returns).
# The step-aside is choreographed, its other half lives in the dresser: the
# popup lands OVER the fleet window, and only once it has rendered does the
# window sink away - the screen is never empty while the popup builds (the
# first cut hid the window first, and the wait for the render read as a
# stall). The modal frame makes the parent deaf from the first instant, so
# nothing can be clicked through the handoff. The depth says how many
# dialogs are up: a sink completing after the last close must not hide the
# window the gate has just brought back.
function Show-PopupExclusive {
    param(
        [System.Windows.Window]$ParentWindow,
        [scriptblock]$DialogAction
    )

    $script:DialogDepth = [int]$script:DialogDepth + 1
    try {
        & $DialogAction
    }
    finally {
        $script:DialogDepth = [int]$script:DialogDepth - 1
        # The parent comes back solid: sunk and hidden, or still sinking
        # as the dialog flash-closed - the fade-in takes the place of
        # whatever rode it, from where it stood. A window that never faded
        # (a system alert never passes the dresser) stays as it is.
        if ($ParentWindow.Opacity -lt 1) {
            $ParentWindow.Show()
            $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]::new($ParentWindow.Opacity, 1, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(130)))
            $ParentWindow.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        }
        $null = $ParentWindow.Activate()
        # Hide/Show loses the keyboard focus, and the keys need one to
        # travel from: the window takes it back, or Q and Escape would be
        # dead until the list is clicked again (measured).
        $null = $ParentWindow.Focus()
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

    [xml]$gateXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\RemoveGate.xaml"))

    $gate = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($gateXaml))
    $gate.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $gate -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
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

    Set-WindowFitToContent -Win $gate
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

    [xml]$restoreXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\RestorePrompt.xaml"))

    $prompt = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($restoreXaml))
    $prompt.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $prompt -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
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

    Set-WindowFitToContent -Win $prompt
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

    [xml]$deleteXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\ArchiveGate.xaml"))

    $gate = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($deleteXaml))
    $gate.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $gate -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
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

    Set-WindowFitToContent -Win $gate
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

    [xml]$archiveXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\ArchivePrompt.xaml"))

    $prompt = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($archiveXaml))
    $prompt.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $prompt -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
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

    Set-WindowFitToContent -Win $prompt
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
        $ApplyButton,
        [string]$NothingText
    )

    $script:ChecklistInstalled = $Installed
    $script:ChecklistCatalog = $Catalog
    $script:ChecklistTxtAdd = $TxtAdd
    $script:ChecklistTxtDel = $TxtDel
    $script:ChecklistTxtNotes = $TxtNotes
    $script:ChecklistApplyButton = $ApplyButton
    $script:ChecklistNothingText = $NothingText
    $script:ChecklistSelection = $null

    # One box per offered pack - the same surface the console's checklist
    # shows, so the two ask the same question.
    $script:ChecklistEntries = @()
    foreach ($pack in @($Catalog.AvailablePacks | Where-Object { $_.Offered })) {
        $check = New-Object System.Windows.Controls.CheckBox
        # The label folds instead of running off the window: a plain string
        # refuses to wrap, and a wide face at a big zoom runs long
        # descriptions past the edge (measured on screen).
        $label = New-Object System.Windows.Controls.TextBlock
        $label.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $label.Text = "{0,-12} {1}" -f $pack.Name, $pack.Description
        $check.Content = $label
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

        # The editor's APPLY follows the answer: greyed on nothing to do.
        # The add form passes no button - an instance with no pack is a real
        # answer there.
        if ($script:ChecklistApplyButton) {
            $script:ChecklistApplyButton.IsEnabled = ($selection.ToAdd.Count -gt 0 -or $selection.ToRemove.Count -gt 0)
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

    [xml]$editorXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\PackEditor.xaml"))

    $editor = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($editorXaml))
    $editor.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $editor -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $editor.FindName("TxtLead").Text = "$InstanceName' Packs"

    New-PackChecklist -Panel $editor.FindName("Boxes") -Installed $Installed -Catalog $Catalog `
        -TxtAdd $editor.FindName("TxtAdd") -TxtDel $editor.FindName("TxtDel") -TxtNotes $editor.FindName("TxtNotes") `
        -ApplyButton $editor.FindName("BtnEditApply") `
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

    Set-WindowFitToContent -Win $editor
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

    [xml]$addXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\AddInstance.xaml"))

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($addXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $form -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
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

    Set-WindowFitToContent -Win $form

    # Docker, asked in parallel now: the probe rides behind the form where
    # it used to hold the door for a second. Not up when it answers: a
    # message box over the form - start Docker Desktop, the form stays and
    # the filling overlaps the boot; or close the form. The ticks read this
    # function's scope, alive through the modal loop below (like every
    # handler here); the probe process carries on by itself if the form
    # closes first.
    $dockerProbe = $null
    try { $dockerProbe = Start-Process docker -ArgumentList "info" -PassThru -WindowStyle Hidden -ErrorAction Stop } catch { }
    $dockerAsk = New-Object System.Windows.Threading.DispatcherTimer
    $dockerAsk.Interval = [TimeSpan]::FromMilliseconds(300)
    $dockerAsk.Add_Tick({
        param($source, $e)
        if ($dockerProbe -and -not $dockerProbe.HasExited) { return }
        $source.Stop()
        if ($dockerProbe -and $dockerProbe.ExitCode -eq 0) { return }

        # The system's own alert: a question and two buttons, with the keys
        # every Windows alert answers to.
        $answer = [System.Windows.MessageBox]::Show($form,
            "Docker Desktop is not running.`n`nStart it now? The form stays open and you can keep filling it - the creation itself waits for Docker later on.",
            "Docker is not running",
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { $form.Close(); return }
        # Started the way its installer leaves it; the CLI as the fallback.
        try {
            Start-Process (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe") -ErrorAction Stop
        } catch {
            try {
                $null = Start-Process docker -ArgumentList "desktop", "start" -ErrorAction Stop
            } catch {
                $null = [System.Windows.MessageBox]::Show($form,
                    "Could not start Docker Desktop - start it yourself.",
                    "WSL Stack",
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        }
    })
    $form.Add_Closed({ $dockerAsk.Stop() })
    $dockerAsk.Start()

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

    [xml]$lookXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\Appearance.xaml"))

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($lookXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $form -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $form.FindName("TxtLead").Text = "$InstanceName's appearance."
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

    # The icon as it stands: an uploaded image sits at the path above (its
    # seat), so the preview shows IT and APPLY would keep it - the recipe
    # lives behind. A text or colour edit takes the seat back, see
    # DrawPreview. Without an image, the recipe draws as before.
    if (Test-Path $IconPath) {
        $script:LookImage = $IconPath
        & $LoadIconFile $IconPath
    } else {
        & $DrawPreview
    }

    # An image is a choice like the others: picked here and applied with
    # everything else on APPLY. The path under "Icon file:" is what answers -
    # it shows the file that will be used, the current one until another is
    # picked - and a note added under it while the old path stayed above read
    # as nothing. It still replaces the picture alone: the recipe behind it
    # stays, the console's own manners.
    # The file dialog's Enter lands on the owner once it closes, and the
    # default button answers it - the icon pick has closed this very window
    # on APPLY (measured): after each pick, the Enter's pair is eaten off
    # the window.
    $script:EatEnter = $false
    $form.Add_PreviewKeyDown({
        param($source, $e)
        if ($script:EatEnter -and $e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true }
    })
    $form.Add_PreviewKeyUp({
        param($source, $e)
        if ($script:EatEnter -and $e.Key -eq [System.Windows.Input.Key]::Enter) {
            $script:EatEnter = $false
            $e.Handled = $true
        }
    })

    $form.FindName("BtnImage").Add_Click({
        $Dialog = New-Object Microsoft.Win32.OpenFileDialog
        $Dialog.Title = "Icon image for '$InstanceName'"
        $Dialog.Filter = "Images (*.png;*.jpg;*.jpeg;*.ico;*.bmp)|*.png;*.jpg;*.jpeg;*.ico;*.bmp"
        $picked = $Dialog.ShowDialog($form)
        $script:EatEnter = $true
        if ($picked -eq $true) {
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

    Set-WindowFitToContent -Win $form
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

    [xml]$dupXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\Duplicate.xaml"))

    $prompt = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($dupXaml))
    $prompt.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $prompt -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
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

    Set-WindowFitToContent -Win $prompt
    Show-PopupExclusive $window { $null = $prompt.ShowDialog() }
    return $script:DupResult
}

# -----------------------------------------------------------------------------
# THE WINDOW'S OWN FACE - THE SETTINGS, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The three the gui wears: the family, its size and the colour set - all
# shown as they stand, all applied together. The family in use is marked
# in the list and its size selected. An uploaded font file lands in the
# repository's own font folder, beside VT323, and the family it carries
# joins the list, selected - the icon's own manners, one seat over.
function Show-GuiSettings {
    param([string]$AssetsDir, [string]$CurrentFamily, [int]$CurrentSize, [string]$CurrentColourSet)

    [xml]$settingsXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\GuiSettings.xaml"))

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($settingsXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $form -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $form.FindName("TxtLead").Text = "Appearance"

    # The list: the folders first, then the machine's usable fonts - the
    # console's own detection, which draws glyphs, so it is asked now and
    # never at launch. The family in use is marked and stands selected.
    # A List, not an array: the upload handler below APPENDS to it, and a
    # scriptblock's `+=` would assign a local copy - the function's array
    # would stay short, the selected index one past it, and APPLY would
    # answer an empty row (measured: "Window face: ''", the dresser then
    # skipped). Method calls mutate the shared object; assignments do not.
    $choiceRows = [System.Collections.Generic.List[object]]::new()
    foreach ($choice in @(Get-GuiFontChoices -AssetsDir $AssetsDir)) { $choiceRows.Add($choice) }
    $taken = @{}
    foreach ($choice in $choiceRows) { $taken[$choice.Name] = $true }
    # The machine's list, read once per session like the appearance form's
    # (see Get-GuiLookups): probing every family at every open made this
    # window wait.
    foreach ($font in @((Get-GuiLookups).Fonts)) {
        if ($taken.ContainsKey($font.Name)) { continue }
        $taken[$font.Name] = $true
        $choiceRows.Add([PSCustomObject]@{ Name = $font.Name; Family = [Windows.Media.FontFamily]::new($font.Name) })
    }

    # The worn face may not be in the list at all - Segoe UI, the XAML's own
    # fallback, when nothing resolves - and a select standing on a silent
    # first row lies about what the windows wear: it is prepended, marked,
    # and selected like any other.
    if (@($choiceRows | Where-Object { $_.Name -eq $CurrentFamily }).Count -eq 0) {
        $choiceRows.Insert(0, [PSCustomObject]@{ Name = $CurrentFamily; Family = [Windows.Media.FontFamily]::new($CurrentFamily) })
    }

    $lstFonts = $form.FindName("LstGuiFonts")
    $fontIndex = 0
    for ($i = 0; $i -lt $choiceRows.Count; $i++) {
        $here = if ($choiceRows[$i].Name -eq $CurrentFamily) { "  (current)" } else { "" }
        if ($choiceRows[$i].Name -eq $CurrentFamily) { $fontIndex = $i }
        $null = $lstFonts.Items.Add("$($choiceRows[$i].Name)$here")
    }
    if ($choiceRows.Count -gt 0) { $lstFonts.SelectedIndex = $fontIndex }

    # The size: a short ladder; a hand-edited settings file keeps its rung.
    $lstSizes = $form.FindName("LstGuiSizes")
    $sizes = @(11, 13, 15, 17, 19)
    if ($sizes -notcontains $CurrentSize) { $sizes = @($CurrentSize) + $sizes }
    $sizeIndex = 0
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $here = if ($sizes[$i] -eq $CurrentSize) { "  (current)" } else { "" }
        if ($sizes[$i] -eq $CurrentSize) { $sizeIndex = $i }
        $null = $lstSizes.Items.Add("$($sizes[$i])$here")
    }
    $lstSizes.SelectedIndex = $sizeIndex

    # The themes: the little files under assets\colours - each carries its
    # dark and light versions, and the header's sun/moon switches between
    # them. A name the folder no longer holds is kept at the top, marked:
    # the select never lies about what the windows wear.
    $lstColours = $form.FindName("LstGuiColours")
    $setNames = @(Get-GuiColourSets -AssetsDir $AssetsDir)
    if (-not $CurrentColourSet -or $setNames -notcontains $CurrentColourSet) { $setNames = @($CurrentColourSet) + $setNames }
    $setIndex = 0
    for ($i = 0; $i -lt $setNames.Count; $i++) {
        $label = if ($setNames[$i]) { $setNames[$i] } else { "Default" }
        $here = if ($setNames[$i] -eq $CurrentColourSet) { "  (current)" } else { "" }
        if ($setNames[$i] -eq $CurrentColourSet) { $setIndex = $i }
        $null = $lstColours.Items.Add("$label$here")
    }
    $lstColours.SelectedIndex = $setIndex

    # The file dialog's Enter lands on the owner once it closes, and the
    # default button answers it - the popup closed applying the old choice
    # (measured). After each pick, the Enter's pair is eaten off the window.
    $script:EatEnter = $false
    $form.Add_PreviewKeyDown({
        param($source, $e)
        if ($script:EatEnter -and $e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true }
    })
    $form.Add_PreviewKeyUp({
        param($source, $e)
        if ($script:EatEnter -and $e.Key -eq [System.Windows.Input.Key]::Enter) {
            $script:EatEnter = $false
            $e.Handled = $true
        }
    })

    # An uploaded face: the file lands in a folder of its own under the
    # repository's fonts, and the family it carries joins the list, selected.
    # A family travels as an OBJECT, so the row holds it, never a name to
    # resolve again. The folder of its own, because the font cache never
    # notices a file added to a folder it already knows (measured: the
    # upload never showed up) - a folder WPF has never seen is served fresh.
    $form.FindName("BtnGuiFontUpload").Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "A font file for the window"
        $dialog.Filter = "Fonts (*.ttf;*.otf)|*.ttf;*.otf"
        $picked = $dialog.ShowDialog($form)
        $script:EatEnter = $true
        if ($picked -ne $true) { return }
        # The folder's name is the file's identity - the base name and a
        # short hash of the content: the same font uploaded again lands in
        # the same folder (no pile of folders), a changed file takes a path
        # the font cache has never seen (it must not serve stale bytes).
        $fingerprint = (Get-FileHash -LiteralPath $dialog.FileName -Algorithm SHA1).Hash.Substring(0, 8).ToLower()
        $slot = Join-Path (Join-Path $AssetsDir "fonts") ("$([IO.Path]::GetFileNameWithoutExtension($dialog.FileName))-$fingerprint")
        $family = @()
        try {
            $null = New-Item -ItemType Directory -Path $slot -Force
            Copy-Item -LiteralPath $dialog.FileName -Destination (Join-Path $slot ([IO.Path]::GetFileName($dialog.FileName))) -Force
            $uri = [Uri]("file:///" + ($slot -replace '\\', '/') + "/")
            $family = @([Windows.Media.Fonts]::GetFontFamilies($uri) | Select-Object -First 1)
        } catch { }
        if ($family.Count -eq 0) { return }
        $family = $family[0]
        $name = "$($family.FamilyNames.Values | Select-Object -First 1)"
        if (-not $name) { $name = "$($family.Source)" -replace '^\./#', '' }
        $choiceRows.Add([PSCustomObject]@{ Name = $name; Family = $family; Folder = $slot })
        $null = $lstFonts.Items.Add("$name  (just uploaded)")
        $lstFonts.SelectedIndex = $lstFonts.Items.Count - 1
    })

    $script:GuiSettingsResult = $null
    $form.FindName("BtnGuiCancel").Add_Click({ $script:GuiSettingsResult = $null; $form.Close() })
    $form.FindName("BtnGuiApply").Add_Click({
        $choice = $choiceRows[[Math]::Max(0, $lstFonts.SelectedIndex)]
        $size = $sizes[[Math]::Max(0, $lstSizes.SelectedIndex)]
        $set = $setNames[[Math]::Max(0, $lstColours.SelectedIndex)]
        $script:GuiSettingsResult = [PSCustomObject]@{ Name = $choice.Name; Family = $choice.Family; Folder = $choice.Folder; Size = [int]$size; ColourSet = $set }
        $form.Close()
    })

    Set-WindowFitToContent -Win $form
    Show-PopupExclusive $window { $null = $form.ShowDialog() }
    return $script:GuiSettingsResult
}
