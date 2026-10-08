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
# ONE QUESTION, TWO ANSWERS - THE CONFIRM POPUP, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The smallest gate: a title, a question, Cancel and the red CONFIRM - the
# theme worn like the rest, which a system MessageBox cannot. It opens as a
# plain dialog of its OWNER, never through Show-PopupExclusive: its callers
# are popups themselves, and sinking a dialog window ends it (see the gate's
# own warning above). Answers $true for CONFIRM, $false for everything else -
# Cancel, Escape, the close crosses.
function Show-GuiConfirm {
    param([string]$Title, [string]$Question, [System.Windows.Window]$Owner, [string]$Danger = "")

    [xml]$confirmXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\Confirm.xaml"))

    $confirm = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($confirmXaml))
    $confirm.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $confirm -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $confirm.FindName("TxtLead").Text = $Title
    # The question, one block with two colours: the plain text, then - when
    # there is one - the red line under it (a Run of its own in the same
    # TextBlock: no new element, no new name to find).
    $txtQuestion = $confirm.FindName("TxtQuestion")
    $txtQuestion.Inlines.Clear()
    $txtQuestion.Inlines.Add([System.Windows.Documents.Run]::new($Question))
    if ($Danger) {
        $txtQuestion.Inlines.Add([System.Windows.Documents.LineBreak]::new())
        $txtQuestion.Inlines.Add([System.Windows.Documents.LineBreak]::new())
        $dangerRun = [System.Windows.Documents.Run]::new($Danger)
        $dangerRun.Foreground = $confirm.FindResource("AppDangerBrush")
        $txtQuestion.Inlines.Add($dangerRun)
    }

    $script:ConfirmResult = $false
    $confirm.FindName("BtnConfirmCancel").Add_Click({ $script:ConfirmResult = $false; $confirm.Close() })
    $confirm.FindName("BtnConfirmOk").Add_Click({ $script:ConfirmResult = $true; $confirm.Close() })

    Set-WindowFitToContent -Win $confirm
    # The owner goes in by property, then the window opens bare: PowerShell's
    # binder refuses Window.ShowDialog(owner) - "no overload with 1 argument"
    # (measured) - while the bare ShowDialog is the one every window in this
    # file already uses.
    if ($Owner) { $confirm.Owner = $Owner }
    $null = $confirm.ShowDialog()
    return $script:ConfirmResult
}

# The working folder's move, asked on its own: the warning first - every
# instance stops and is archived on the way - the folder in a box, a Cancel
# and a red CONFIRM. Answers the new folder, or $null when cancelled or left
# empty.
function Show-GuiRootMove {
    param([string]$Current, [System.Windows.Window]$Owner)

    [xml]$moveXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\RootMove.xaml"))

    $move = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($moveXaml))
    $move.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $move -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $move.FindName("TxtLead").Text = "Move the working folder"
    $move.FindName("TxtWarning").Text = "Every instance will be stopped and archived first.`nMake sure you saved your work before proceeding."
    $move.FindName("TxtNewRoot").Text = $Current

    $script:RootMoveResult = $null
    $move.FindName("BtnRootCancel").Add_Click({ $move.Close() })
    $move.FindName("BtnRootOk").Add_Click({
        $chosen = $move.FindName("TxtNewRoot").Text.Trim().Trim('"').TrimEnd('\')
        if ($chosen) { $script:RootMoveResult = $chosen }
        $move.Close()
    })

    Set-WindowFitToContent -Win $move
    if ($Owner) { $move.Owner = $Owner }
    $null = $move.ShowDialog()
    return $script:RootMoveResult
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
# A DISK MADE LEAN - THE COMPACT GATE, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The row's Compact asks first, on the removal gate's model: an idle instance
# is the condition, and the archive it offers is the same checkbox the trash
# wears - the copy, under the instance's own name, before the disk is
# rewritten. The compaction itself is the engine's.
function Show-ShrinkGate {
    param($Instance)

    [xml]$gateXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\ShrinkGate.xaml"))

    $gate = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($gateXaml))
    $gate.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $gate -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $gate.FindName("TxtLead").Text = "Compacting '$($Instance.Name)'."

    # The keyboard lands on the archive box once the window is up: Enter is
    # COMPACT, Escape is Cancel, wherever the walk stands.
    $chkArchive = $gate.FindName("ChkArchive")
    $gate.Add_ContentRendered({ $null = $chkArchive.Focus() })

    $script:GateResult = $null
    $gate.FindName("BtnGateCancel").Add_Click({ $script:GateResult = $null; $gate.Close() })
    $gate.FindName("BtnGateCompact").Add_Click({
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
        [string[]]$Checked = $null,
        $Catalog,
        $TxtAdd,
        $TxtDel,
        $TxtNotes,
        $TxtWarn,
        $ApplyButton,
        [string]$NothingText,
        [string]$Family = "debian"
    )

    # What arrives ticked is not what is installed: at build time the instance
    # carries nothing yet, while the boxes expected ticked are the shell pack's
    # - the console's checklist draws the same two apart.
    if ($null -eq $Checked) { $Checked = $Installed }

    $script:ChecklistInstalled = $Installed
    $script:ChecklistCatalog = $Catalog
    $script:ChecklistTxtAdd = $TxtAdd
    $script:ChecklistTxtDel = $TxtDel
    $script:ChecklistTxtNotes = $TxtNotes
    $script:ChecklistTxtWarn = $TxtWarn
    $script:ChecklistApplyButton = $ApplyButton
    $script:ChecklistNothingText = $NothingText
    $script:ChecklistFamily = $Family
    $script:ChecklistSelection = $null

    # One box per offered pack, the machine's family's - the same surface the
    # console's checklist shows, so the two ask the same question.
    $script:ChecklistEntries = @()
    foreach ($pack in @($Catalog.OfferedFor($Family))) {
        $check = New-Object System.Windows.Controls.CheckBox
        # The label folds instead of running off the window: a plain string
        # refuses to wrap, and a wide face at a big zoom runs long
        # descriptions past the edge (measured on screen).
        $label = New-Object System.Windows.Controls.TextBlock
        $label.TextWrapping = [System.Windows.TextWrapping]::Wrap
        # The family rides on the row, in brackets - the console's checklist
        # shows the same, so a pack made for another system is spotted
        # before it is ticked.
        $label.Text = "{0,-12} [{1}] {2}" -f $pack.Name, $pack.Family, $pack.Description
        $check.Content = $label
        $check.Margin = "0,3,0,3"
        $check.IsChecked = ($Checked -contains $pack.Name)
        $script:ChecklistEntries += [PSCustomObject]@{ Pack = $pack; Check = $check }
        $null = $Panel.Children.Add($check)
    }

    $RefreshAnswer = {
        $kept = @($script:ChecklistEntries | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Pack.Name })
        $selection = Resolve-PackSelection -Catalog $script:ChecklistCatalog -Installed $script:ChecklistInstalled -Kept $kept -Family $script:ChecklistFamily
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

        # The refusal, said under the lists: a pack a standing pack requires
        # cannot leave - the same guard as the console's, from the same
        # answer. The add form passes no block: nothing is installed there,
        # so nothing can be held.
        if ($script:ChecklistTxtWarn) {
            if ($selection.Conflicts.Count -gt 0) {
                $script:ChecklistTxtWarn.Text = (@($selection.Conflicts | ForEach-Object {
                    "'{0}' cannot be removed: required by {1}.`nUntick {1} as well, or leave '{0}' ticked." -f $_.Name, ($_.Blockers -join " and ")
                }) -join "`n")
                $script:ChecklistTxtWarn.Visibility = [System.Windows.Visibility]::Visible
            } else {
                $script:ChecklistTxtWarn.Visibility = [System.Windows.Visibility]::Collapsed
            }
        }

        # The editor's APPLY follows the answer: greyed on nothing to do, and
        # greyed while the answer is refused.
        # The add form passes no button - an instance with no pack is a real
        # answer there.
        if ($script:ChecklistApplyButton) {
            $script:ChecklistApplyButton.IsEnabled = (($selection.ToAdd.Count -gt 0 -or $selection.ToRemove.Count -gt 0) -and $selection.Conflicts.Count -eq 0)
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
    param([string]$InstanceName, [string[]]$Installed, $Catalog, [string]$Family = "debian")

    [xml]$editorXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\PackEditor.xaml"))

    $editor = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($editorXaml))
    $editor.Resources.MergedDictionaries.Add((Get-ThemeDictionary))

    Set-WindowPhosphorFrame -Win $editor -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $editor.FindName("TxtLead").Text = "$InstanceName' Packs"

    New-PackChecklist -Panel $editor.FindName("Boxes") -Installed $Installed -Catalog $Catalog `
        -TxtAdd $editor.FindName("TxtAdd") -TxtDel $editor.FindName("TxtDel") -TxtNotes $editor.FindName("TxtNotes") `
        -TxtWarn $editor.FindName("TxtWarn") `
        -ApplyButton $editor.FindName("BtnEditApply") `
        -NothingText "Nothing to do: '$InstanceName' already has exactly that." `
        -Family $Family

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
# THE BUILD'S RECIPE - THE FORM'S LISTS AND UPLOADS, WINDOW-SIDE
# -----------------------------------------------------------------------------
# The lists themselves - what the repository offers and what was uploaded -
# come from the module's Get-BuildRecipes: the build's console road offers
# the same ones, one scan for both. An upload lands in a slot of its own
# under the assets, named <file>-<sha1-8> and holding the file under its
# plain name (Dockerfile, first_boot.sh) - or under the name it arrived
# with, for an image - the fonts' own convention (the upload button in
# Show-GuiSettings): the same file uploaded again lands in the same slot,
# and a changed file takes a path no reader has seen.

# One uploaded file's slot, folder and all, gone: the trash beside each list
# deletes the row it stands on. The guard is the row's own mark - the
# repository's own files are never slots of their own. The dropdown goes
# back to the first row - the default one, for the lists that have one - and
# an empty image list leaves it with nothing selected.
function Remove-GuiBuildRecipe {
    param($Row, $Choices, $Combo)

    if (-not $Row.Uploaded) { return }
    $slot = Split-Path -Path $Row.Path -Parent
    if (Test-Path -LiteralPath $slot) { Remove-Item -LiteralPath $slot -Recurse -Force }
    $index = $Choices.IndexOf($Row)
    if ($index -ge 0) {
        $Choices.RemoveAt($index)
        $Combo.Items.RemoveAt($index)
    }
    $Combo.SelectedIndex = 0
}

# One uploaded recipe file into its slot, answering where it landed. A
# Dockerfile brings its .dockerignore sibling along when there is one, under
# the very name a builder reads beside a `-f` Dockerfile
# (Dockerfile.dockerignore) - without one, the whole checkout is sent to the
# Docker daemon.
function Copy-GuiBuildRecipe {
    param([string]$AssetsDir, [string]$Kind, [string]$Source, [string]$FileName)

    $fingerprint = (Get-FileHash -LiteralPath $Source -Algorithm SHA1).Hash.Substring(0, 8).ToLower()
    $slot = Join-Path (Join-Path $AssetsDir $Kind) ("$([IO.Path]::GetFileNameWithoutExtension($Source))-$fingerprint")
    $null = New-Item -ItemType Directory -Path $slot -Force
    $target = Join-Path $slot $FileName
    Copy-Item -LiteralPath $Source -Destination $target -Force
    if ($FileName -eq "Dockerfile") {
        $sibling = Join-Path ([IO.Path]::GetDirectoryName($Source)) ".dockerignore"
        if (Test-Path $sibling) {
            Copy-Item -LiteralPath $sibling -Destination (Join-Path $slot "Dockerfile.dockerignore") -Force
        }
    }
    return $target
}

# The download beside the upload hands the selected file out: copied wherever
# the user points. A slot's file is offered back under the name it was
# uploaded as, the slot's hash dropped; any other row under its own file
# name. Every row's business, the repository's own included, unlike the
# trash's. The Enter that closed the dialog is eaten like after an upload's:
# it would land on the form and press the default button.
function Save-GuiFile {
    param($Row, $Owner)

    # An uploaded row's file sits in a slot named after the file it arrived
    # as (<base>-<hash>; the file inside is canonical): the slot says the
    # name to offer back, its own file's extension kept. The repository's
    # own rows offer their own name.
    $proposed = [IO.Path]::GetFileName($Row.Path)
    if ($Row.Uploaded) {
        $base = (Split-Path -Path (Split-Path -Path $Row.Path -Parent) -Leaf) -replace '-[0-9a-f]{8}$', ''
        $proposed = "$base$([IO.Path]::GetExtension($Row.Path))"
    }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = "Save '$proposed'"
    $dialog.FileName = $proposed
    $dialog.Filter = "All files (*.*)|*.*"
    $picked = $dialog.ShowDialog($Owner)
    $script:EatEnter = $true
    if ($picked -ne $true) { return }
    try { Copy-Item -LiteralPath $Row.Path -Destination $dialog.FileName -Force } catch { return }
}

# -----------------------------------------------------------------------------
# A NEW INSTANCE - THE ADD FORM, WINDOW-SIDE
# -----------------------------------------------------------------------------
# build's first questions, answered in one window: the name - a name that
# exists is refused here, this road offers no destruction - the user name, the
# Windows account's cleaned form prefilled, both checked live (the red line
# under the box saying what is wrong), the build's recipe - a toggle between a
# Dockerfile and an uploaded Docker image, the first_boot beside them, each a
# list opening on the repository's own files, an upload and a download button
# and a trash apiece - and the packs, the same checklist as the editor's. Returns
# { Name; User; Dockerfile; FirstBoot; Image; Packs }, with whichever of
# Dockerfile and Image the toggle did not choose left empty - or $null when
# cancelled; the run itself then gets a console window of its own, because it
# is long, it is loud, and it still has questions only it can ask.
function Show-AddInstance {
    param($Catalog, [string]$ProposedUser, [string]$InstancesRoot, $Manager)

    [xml]$addXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\AddInstance.xaml"))

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($addXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))
    # The trash glyphs are Font Awesome, handed to the form the way the main
    # window hands them over; without the resource they would be empty boxes.
    if ($GuiFonts.IconFont) { $form.Resources["IconFace"] = $GuiFonts.IconFont }
    # The window may use the screen: the markup's 760 was a guess, and a big
    # window font makes the form taller than it (measured at 19pt). At this
    # cap the content scrolls, whatever the font, and the buttons below stay
    # put - the same rule as the main window's own height.
    $form.MaxHeight = [Math]::Max(360, [System.Windows.SystemParameters]::WorkArea.Height - 40)

    Set-WindowPhosphorFrame -Win $form -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $txtName = $form.FindName("TxtName")
    $txtNameError = $form.FindName("TxtNameError")
    $txtUser = $form.FindName("TxtUser")
    $txtUserError = $form.FindName("TxtUserError")
    $txtImageError = $form.FindName("TxtImageError")
    $lblUser = $form.FindName("LblUser")
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
        -Checked (Get-BuildDefaultPacks -Catalog $Catalog) `
        -TxtAdd $form.FindName("TxtAdd") -TxtDel $form.FindName("TxtDel") -TxtNotes $form.FindName("TxtNotes") `
        -NothingText "No pack selected - it will start bare."

    $txtName.Add_TextChanged($CheckName)
    $txtUser.Add_TextChanged($CheckUser)
    & $CheckName
    & $CheckUser

    # The build's recipe: three lists - the Dockerfile's and the first_boot's,
    # each opening on the repository's own file, and the images' (none of the
    # repository's: it ships none) - an upload and a download button and a
    # trash beside each, and a toggle above choosing the road: a Dockerfile,
    # or an image.
    # Lists, not arrays, for the reason the font picker's is one: the
    # handlers below append by method, and a scriptblock's `+=` would assign
    # a local copy (measured there).
    $recipes = Get-BuildRecipes -AssetsDir $AssetsDir
    $dockerChoices = [System.Collections.Generic.List[object]]::new()
    $bootChoices = [System.Collections.Generic.List[object]]::new()
    $imageChoices = [System.Collections.Generic.List[object]]::new()
    $cmbDockerfile = $form.FindName("CmbDockerfile")
    $cmbFirstBoot = $form.FindName("CmbFirstBoot")
    $cmbDockerImage = $form.FindName("CmbDockerImage")
    foreach ($choice in $recipes.Dockerfiles) {
        $dockerChoices.Add($choice)
        $null = $cmbDockerfile.Items.Add("$($choice.Name)")
    }
    foreach ($choice in $recipes.FirstBoots) {
        $bootChoices.Add($choice)
        $null = $cmbFirstBoot.Items.Add("$($choice.Name)")
    }
    foreach ($choice in $recipes.Images) {
        $imageChoices.Add($choice)
        $null = $cmbDockerImage.Items.Add("$($choice.Name)")
    }
    $cmbDockerfile.SelectedIndex = 0
    $cmbFirstBoot.SelectedIndex = 0
    if ($cmbDockerImage.Items.Count -gt 0) { $cmbDockerImage.SelectedIndex = 0 }

    # The toggle: one road or the other, and only its row shows - the checked
    # event covers both directions, since a radio leaving fires the arriving
    # one's.
    $rbDockerfile = $form.FindName("RbFromDockerfile")
    $rbImage = $form.FindName("RbFromImage")
    $boxDockerfile = $form.FindName("BoxDockerfile")
    $boxImage = $form.FindName("BoxDockerImage")
    $ShowRecipeBox = {
        $fromImage = [bool]$rbImage.IsChecked
        # The onboarding follows the road: an uploaded image is presumed
        # complete as it is - or foreign, alpine having no bash - so its
        # box arrives unticked; a Dockerfile build keeps it, our images
        # need the account. The user re-ticks it like any other default.
        $chkRunFirstBoot.IsChecked = -not $fromImage
        $boxDockerfile.Visibility = if ($fromImage) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
        $boxImage.Visibility = if ($fromImage) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    $rbDockerfile.Add_Checked({ & $ShowRecipeBox; & $RefreshChecklist })
    $rbImage.Add_Checked({ & $ShowRecipeBox; & $RefreshChecklist })

    # The onboarding box: unticked, the image is used as it is - nothing of
    # the first_boot is placed or run, and there is no account to name: the
    # field and its row grey out, they are exactly what the onboarding
    # brings. The empty first_boot the form sends is what tells the build.
    $chkRunFirstBoot = $form.FindName("ChkRunFirstBoot")
    $boxFirstBoot = $form.FindName("BoxFirstBoot")

    # The checklist follows the recipe: the shell pack is ticked for a
    # Debian-family one and for it alone - the family is read off the chosen
    # Dockerfile's FROM, and an image, whose family cannot be read off a
    # save-tar, ticks nothing. What the last paint ticked BY DEFAULT goes
    # with the old family; what the user ticked themselves survives the
    # redraw, and so do the boxes the new family still offers.
    $script:ChecklistDefaults = @(Get-BuildDefaultPacks -Catalog $Catalog)
    $RefreshChecklist = {
        $family = if ($rbImage.IsChecked) { "" } else { Get-BuildRecipeFamily -Dockerfile $dockerChoices[[Math]::Max(0, $cmbDockerfile.SelectedIndex)].Path }
        # A family that cannot be read is SAID, not hidden: the packs stay in
        # reach - the image may well be Debian under a name we cannot read -
        # and the line is the guard for whoever does not know.
        $form.FindName("TxtPacksForeign").Visibility = if ($family) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
        $ticked = @($script:ChecklistEntries | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Pack.Name })
        $mine = @($ticked | Where-Object { $_ -notin $script:ChecklistDefaults })
        $defaults = @(Get-BuildDefaultPacks -Catalog $Catalog -Family $family)
        $script:ChecklistDefaults = $defaults
        $form.FindName("Boxes").Children.Clear()
        New-PackChecklist -Panel $form.FindName("Boxes") -Installed @() -Catalog $Catalog `
            -Checked (@($mine) + $defaults) `
            -TxtAdd $form.FindName("TxtAdd") -TxtDel $form.FindName("TxtDel") -TxtNotes $form.FindName("TxtNotes") `
            -NothingText "No pack selected - it will start bare." `
            -Family $family
    }
    $UpdateOnboarding = {
        $on = [bool]$chkRunFirstBoot.IsChecked
        $txtUser.IsEnabled = $on
        $lblUser.IsEnabled = $on
        $boxFirstBoot.IsEnabled = $on
        if (-not $on) { $txtUserError.Visibility = [System.Windows.Visibility]::Collapsed }
    }
    # Checked/Unchecked, not Click: the road's toggle ticks this box by code,
    # and a programmatic tick fires no click - the greying must follow it too.
    $chkRunFirstBoot.Add_Checked({ & $UpdateOnboarding })
    $chkRunFirstBoot.Add_Unchecked({ & $UpdateOnboarding })

    # The trash beside each list: it deletes the SELECTED uploaded file,
    # asking first (the red CONFIRM) - greyed on the repository's own rows,
    # which are not the form's to take away, and with no image chosen there
    # is nothing to press either. (A trash inside the dropdown itself would
    # be a WPF item template; beside the list it is the same gesture with
    # less rope.)
    $btnDockerfileDelete = $form.FindName("BtnDockerfileDelete")
    $btnFirstBootDelete = $form.FindName("BtnFirstBootDelete")
    $btnDockerImageDelete = $form.FindName("BtnDockerImageDelete")
    $UpdateTrash = {
        $btnDockerfileDelete.IsEnabled = [bool]$dockerChoices[[Math]::Max(0, $cmbDockerfile.SelectedIndex)].Uploaded
        $btnFirstBootDelete.IsEnabled = [bool]$bootChoices[[Math]::Max(0, $cmbFirstBoot.SelectedIndex)].Uploaded
        $btnDockerImageDelete.IsEnabled = ($cmbDockerImage.SelectedIndex -ge 0) -and [bool]$imageChoices[[Math]::Max(0, $cmbDockerImage.SelectedIndex)].Uploaded
    }
    # The download stands on a selected file: the Dockerfile and first_boot
    # lists always open on one, an empty image list has none to hand out.
    $btnDockerImageDownload = $form.FindName("BtnDockerImageDownload")
    $UpdateDownload = { $btnDockerImageDownload.IsEnabled = ($cmbDockerImage.SelectedIndex -ge 0) }
    $cmbDockerfile.Add_SelectionChanged({ & $UpdateTrash; & $RefreshChecklist })
    $cmbFirstBoot.Add_SelectionChanged({ & $UpdateTrash })
    $cmbDockerImage.Add_SelectionChanged({ & $UpdateTrash; & $UpdateDownload; & $RefreshChecklist })
    & $UpdateTrash
    & $UpdateDownload

    $form.FindName("BtnDockerfileDelete").Add_Click({
        $row = $dockerChoices[[Math]::Max(0, $cmbDockerfile.SelectedIndex)]
        if ($row.Uploaded -and (Show-GuiConfirm -Owner $form -Title "Delete Dockerfile" `
                -Question "Remove '$($row.Name)' from the available Dockerfiles?")) {
            Remove-GuiBuildRecipe -Row $row -Choices $dockerChoices -Combo $cmbDockerfile
        }
    })
    $form.FindName("BtnFirstBootDelete").Add_Click({
        $row = $bootChoices[[Math]::Max(0, $cmbFirstBoot.SelectedIndex)]
        if ($row.Uploaded -and (Show-GuiConfirm -Owner $form -Title "Delete onboarding shell" `
                -Question "Remove '$($row.Name)' from the available onboarding shells?")) {
            Remove-GuiBuildRecipe -Row $row -Choices $bootChoices -Combo $cmbFirstBoot
        }
    })
    $form.FindName("BtnDockerImageDelete").Add_Click({
        $row = $imageChoices[[Math]::Max(0, $cmbDockerImage.SelectedIndex)]
        if ($row -and $row.Uploaded -and (Show-GuiConfirm -Owner $form -Title "Delete Docker image" `
                -Question "Remove '$($row.Name)' from the available Docker images?")) {
            Remove-GuiBuildRecipe -Row $row -Choices $imageChoices -Combo $cmbDockerImage
        }
    })

    # The file dialog's Enter lands on the owner once it closes, and the
    # default button answers it - the form would create on a keystroke meant
    # for the dialog (measured in the settings window). After each pick, the
    # Enter's pair is eaten off the window.
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

    $form.FindName("BtnDockerfileUpload").Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "A Dockerfile for the build"
        $dialog.Filter = "Dockerfiles (Dockerfile*)|Dockerfile*|All files (*.*)|*.*"
        $picked = $dialog.ShowDialog($form)
        $script:EatEnter = $true
        if ($picked -ne $true) { return }
        try {
            $target = Copy-GuiBuildRecipe -AssetsDir $AssetsDir -Kind "dockerfiles" -Source $dialog.FileName -FileName "Dockerfile"
        } catch { return }
        $row = [PSCustomObject]@{
            Name     = Format-BuildRecipeName -BaseName ([IO.Path]::GetFileNameWithoutExtension($dialog.FileName)) -Path $target
            Path     = $target
            Uploaded = $true
        }
        $dockerChoices.Add($row)
        $null = $cmbDockerfile.Items.Add("$($row.Name)")
        $cmbDockerfile.SelectedIndex = $cmbDockerfile.Items.Count - 1
    })
    $form.FindName("BtnFirstBootUpload").Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "A first_boot script for the build"
        $dialog.Filter = "Shell scripts (*.sh)|*.sh|All files (*.*)|*.*"
        $picked = $dialog.ShowDialog($form)
        $script:EatEnter = $true
        if ($picked -ne $true) { return }
        try {
            $target = Copy-GuiBuildRecipe -AssetsDir $AssetsDir -Kind "firstboots" -Source $dialog.FileName -FileName "first_boot.sh"
        } catch { return }
        $row = [PSCustomObject]@{
            Name     = Format-BuildRecipeName -BaseName ([IO.Path]::GetFileNameWithoutExtension($dialog.FileName)) -Path $target
            Path     = $target
            Uploaded = $true
        }
        $bootChoices.Add($row)
        $null = $cmbFirstBoot.Items.Add("$($row.Name)")
        $cmbFirstBoot.SelectedIndex = $cmbFirstBoot.Items.Count - 1
    })
    $form.FindName("BtnDockerImageUpload").Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "A Docker image for the build"
        $dialog.Filter = "Docker images (*.tar)|*.tar|All files (*.*)|*.*"
        $picked = $dialog.ShowDialog($form)
        $script:EatEnter = $true
        if ($picked -ne $true) { return }
        try {
            $target = Copy-GuiBuildRecipe -AssetsDir $AssetsDir -Kind "dockerimages" -Source $dialog.FileName -FileName ([IO.Path]::GetFileName($dialog.FileName))
        } catch { return }
        $row = [PSCustomObject]@{
            Name     = Format-BuildRecipeName -BaseName ([IO.Path]::GetFileNameWithoutExtension($dialog.FileName)) -Path $target
            Path     = $target
            Uploaded = $true
        }
        $imageChoices.Add($row)
        $null = $cmbDockerImage.Items.Add("$($row.Name)")
        $cmbDockerImage.SelectedIndex = $cmbDockerImage.Items.Count - 1
    })

    $form.FindName("BtnDockerfileDownload").Add_Click({
        Save-GuiFile -Owner $form -Row $dockerChoices[[Math]::Max(0, $cmbDockerfile.SelectedIndex)]
    })
    $form.FindName("BtnFirstBootDownload").Add_Click({
        Save-GuiFile -Owner $form -Row $bootChoices[[Math]::Max(0, $cmbFirstBoot.SelectedIndex)]
    })
    $form.FindName("BtnDockerImageDownload").Add_Click({
        if ($cmbDockerImage.SelectedIndex -ge 0) {
            Save-GuiFile -Owner $form -Row $imageChoices[$cmbDockerImage.SelectedIndex]
        }
    })

    $script:AddResult = $null
    $form.FindName("BtnAddCancel").Add_Click({ $script:AddResult = $null; $form.Close() })
    $form.FindName("BtnAddCreate").Add_Click({
        # The red lines are the refusal: say them and stay open. The image
        # road needs an image - the one refusal that is not a field. The
        # user name is the onboarding's business: off, there is no account
        # to name and the field's rule does not apply.
        & $CheckName
        $runFirstBoot = [bool]$chkRunFirstBoot.IsChecked
        if ($runFirstBoot) { & $CheckUser } else { $script:AddUserOk = $true }
        $fromImage = [bool]$rbImage.IsChecked
        $txtImageError.Text = if ($fromImage -and $cmbDockerImage.SelectedIndex -lt 0) { "Upload a Docker image first." } else { "" }
        $txtImageError.Visibility = if ($txtImageError.Text) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        if ($script:AddNameOk -and $script:AddUserOk -and -not $txtImageError.Text) {
            $script:AddResult = [PSCustomObject]@{
                Name       = $txtName.Text.Trim()
                User       = if ($runFirstBoot) { $txtUser.Text.Trim() } else { "" }
                Dockerfile = if ($fromImage) { "" } else { $dockerChoices[[Math]::Max(0, $cmbDockerfile.SelectedIndex)].Path }
                FirstBoot  = if ($runFirstBoot) { $bootChoices[[Math]::Max(0, $cmbFirstBoot.SelectedIndex)].Path } else { "" }
                Image      = if ($fromImage) { $imageChoices[$cmbDockerImage.SelectedIndex].Path } else { "" }
                Packs      = @($script:ChecklistSelection.ToAdd | ForEach-Object { $_.Name })
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
        $here = if ($Recipe -and $Recipe.Top -eq $field[1] -and $Recipe.Bottom -eq $field[2]) { "  ✓" } else { "" }
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
        $here = if ($Fonts[$i].Name -eq $CurrentFont) { "  ✓" } else { "" }
        if ($Fonts[$i].Name -eq $CurrentFont) { $fontIndex = $i }
        $null = $lstFonts.Items.Add("$($Fonts[$i].Name)$here")
    }
    if ($Fonts.Count -gt 0) { $lstFonts.SelectedIndex = $fontIndex }

    $lstSchemes = $form.FindName("LstSchemes")
    $schemeNames = @($Schemes.Keys | Sort-Object)
    $schemeIndex = 0
    for ($i = 0; $i -lt $schemeNames.Count; $i++) {
        $here = if ($schemeNames[$i] -eq $CurrentScheme) { "  ✓" } else { "" }
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
    param([string]$AssetsDir, [string]$CurrentFamily, [int]$CurrentSize, [string]$CurrentColourSet, [string]$CurrentRoot, $Catalog)

    [xml]$settingsXaml = [System.IO.File]::ReadAllText((Join-Path $GuiRoot "Views\Popups\GuiSettings.xaml"))

    $form = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($settingsXaml))
    $form.Resources.MergedDictionaries.Add((Get-ThemeDictionary))
    # The upload glyph is Font Awesome, handed over like the add form's.
    if ($GuiFonts.IconFont) { $form.Resources["IconFace"] = $GuiFonts.IconFont }

    Set-WindowPhosphorFrame -Win $form -UiFont $GuiFonts.UiFont -UiFontSize $GuiFonts.UiSize
    $form.FindName("TxtLead").Text = "Appearance"
    # The working folder: shown as it stands, greyed, until the edit button
    # opens it - the move itself is the apply's business, confirmed there.
    $txtRoot = $form.FindName("TxtRoot")
    $txtRoot.Text = $CurrentRoot
    $form.FindName("BtnGuiRootEdit").Add_Click({
        # The move, asked on its own: the warning, the folder now, a Cancel
        # and a red CONFIRM. A confirmed folder rides the answer and the
        # window steps out of the way - the console and the manager's return
        # are gui.ps1's.
        $chosen = Show-GuiRootMove -Owner $form -Current $txtRoot.Text.Trim()
        if ($chosen) {
            $script:MoveTo = $chosen
            $script:GuiSettingsResult = & $BuildResult
            $form.Close()
        }
    })

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
        if ($choiceRows[$i].Name -eq $CurrentFamily) { $fontIndex = $i }
        $null = $lstFonts.Items.Add("$($choiceRows[$i].Name)")
    }
    if ($choiceRows.Count -gt 0) { $lstFonts.SelectedIndex = $fontIndex }

    # The size: a short ladder; a hand-edited settings file keeps its rung.
    $lstSizes = $form.FindName("LstGuiSizes")
    $sizes = @(11, 13, 15, 17, 19)
    if ($sizes -notcontains $CurrentSize) { $sizes = @($CurrentSize) + $sizes }
    $sizeIndex = 0
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        if ($sizes[$i] -eq $CurrentSize) { $sizeIndex = $i }
        $null = $lstSizes.Items.Add("$($sizes[$i])")
    }
    $lstSizes.SelectedIndex = $sizeIndex

    # The themes: the little files under assets\colours - each carries its
    # dark and light versions, and the header's sun/moon switches between
    # them. A name the folder no longer holds is kept at the top, marked:
    # the select never lies about what the windows wear.
    $lstColours = $form.FindName("LstGuiColours")
    # Both lists' width - a multiple of the worn size, so it follows the
    # font size where a fixed pixel width would not.
    $comboWidth = 7 * $GuiFonts.UiSize
    $lstFonts.Width = $comboWidth
    $lstColours.Width = $comboWidth
    # A List, not an array: the upload and the trash below mutate it by
    # method - a scriptblock's `+=` would assign a local copy (the fonts'
    # own reason).
    $setNames = [System.Collections.Generic.List[object]]::new()
    $found = @(Get-GuiColourSets -AssetsDir $AssetsDir)
    if (-not $CurrentColourSet -or $found -notcontains $CurrentColourSet) { $setNames.Add($CurrentColourSet) }
    foreach ($setName in $found) { $setNames.Add($setName) }
    $setIndex = 0
    for ($i = 0; $i -lt $setNames.Count; $i++) {
        $label = if ($setNames[$i]) { $setNames[$i] } else { "Default" }
        if ($setNames[$i] -eq $CurrentColourSet) { $setIndex = $i }
        $null = $lstColours.Items.Add("$label")
    }
    $lstColours.SelectedIndex = $setIndex

    # The theme's trash and edit: both greyed on "Default" - no file to take
    # off the disk, none to open either.
    $txtThemeError = $form.FindName("TxtThemeError")
    $btnThemeDelete = $form.FindName("BtnGuiThemeDelete")
    $btnThemeEdit = $form.FindName("BtnGuiThemeEdit")
    $UpdateThemeButtons = {
        $at = $lstColours.SelectedIndex
        $hasFile = ($at -ge 0) -and [bool]$setNames[$at]
        $btnThemeDelete.IsEnabled = $hasFile
        $btnThemeEdit.IsEnabled = $hasFile
    }
    $lstColours.Add_SelectionChanged({ & $UpdateThemeButtons })
    & $UpdateThemeButtons

    # The face applies as it changes - the family, its size, the colour set:
    # the window behind repaints on each pick and the choice is saved at
    # once (the block lives in gui.ps1, where the window's own things are).
    # These three combos have nothing waiting on an APPLY.
    $ApplySelection = {
        $choice = $choiceRows[[Math]::Max(0, $lstFonts.SelectedIndex)]
        $size = $sizes[[Math]::Max(0, $lstSizes.SelectedIndex)]
        & $ApplyLook -Name $choice.Name -Family $choice.Family -Folder $choice.Folder `
            -Size $size -ColourSet $setNames[[Math]::Max(0, $lstColours.SelectedIndex)]
        # The window being looked at wears it too: the same chart, the same
        # face, and the fit redone at the new face - the "popups follow on
        # their next open" starts with this one.
        $form.Resources.MergedDictionaries[0] = (Get-ThemeDictionary)
        Set-WindowPhosphorFrame -Win $form -UiFont $choice.Family -UiFontSize $size
        Set-WindowFitToContent -Win $form -Shrink -Cap 640
    }
    $lstFonts.Add_SelectionChanged({ & $ApplySelection })
    $lstSizes.Add_SelectionChanged({ & $ApplySelection })
    $lstColours.Add_SelectionChanged({ & $ApplySelection })

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

    # The theme's three buttons: a .xaml dropped into the colours folder IS a
    # theme, its file name the theme's name. One that will not load as a
    # resource dictionary is refused, said on the red line; a name already
    # taken passes the red CONFIRM and the file replaces it in place; the
    # trash takes the selected theme's file off the disk - the shipped three
    # included, the confirmation on guard; "Default" is no file at all, so
    # the download offers the chart itself, the model to edit.
    $coloursRoot = Join-Path $AssetsDir "colours"
    $form.FindName("BtnGuiThemeUpload").Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "A theme file for the windows"
        $dialog.Filter = "Themes (*.xaml)|*.xaml"
        $picked = $dialog.ShowDialog($form)
        $script:EatEnter = $true
        if ($picked -ne $true) { return }
        $name = [IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
        $loads = $false
        try {
            $theme = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($dialog.FileName)))
            $loads = $theme -is [System.Windows.ResourceDictionary]
        } catch { }
        $txtThemeError.Text = if ($loads -and $name) { "" } else { "The chosen file is not a theme." }
        $txtThemeError.Visibility = if ($txtThemeError.Text) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        if ($txtThemeError.Text) { return }
        $existing = -1
        for ($i = 0; $i -lt $setNames.Count; $i++) { if ("$($setNames[$i])" -eq "$name") { $existing = $i; break } }
        if ($existing -ge 0 -and -not (Show-GuiConfirm -Owner $form -Title "Replace theme" -Question "Replace the theme '$name' with the chosen file?")) { return }
        Copy-Item -LiteralPath $dialog.FileName -Destination (Join-Path $coloursRoot "$name.xaml") -Force
        if ($existing -lt 0) {
            $setNames.Add($name)
            $null = $lstColours.Items.Add("$name  (just uploaded)")
            $existing = $setNames.Count - 1
        }
        $lstColours.SelectedIndex = $existing
    })
    $form.FindName("BtnGuiThemeDownload").Add_Click({
        $at = $lstColours.SelectedIndex
        if ($at -lt 0) { return }
        $name = $setNames[$at]
        $file = if ($name) { Join-Path $coloursRoot "$name.xaml" } else { Join-Path $GuiRoot "Theme\theme.xaml" }
        Save-GuiFile -Owner $form -Row ([PSCustomObject]@{ Path = $file; Uploaded = $false })
    })
    $form.FindName("BtnGuiThemeDelete").Add_Click({
        $at = $lstColours.SelectedIndex
        if ($at -lt 0) { return }
        $name = $setNames[$at]
        if (-not $name) { return }
        if (-not (Show-GuiConfirm -Owner $form -Title "Delete theme" -Question "Remove the theme '$name'?")) { return }
        Remove-Item -LiteralPath (Join-Path $coloursRoot "$name.xaml") -Force -ErrorAction SilentlyContinue
        $setNames.RemoveAt($at)
        $lstColours.Items.RemoveAt($at)
        $lstColours.SelectedIndex = [Math]::Min($at, $lstColours.Items.Count - 1)
        & $UpdateThemeButtons
    })
    $form.FindName("BtnGuiThemeEdit").Add_Click({
        $at = $lstColours.SelectedIndex
        if ($at -lt 0) { return }
        $name = $setNames[$at]
        if (-not $name) { return }
        # The selected theme's file, opened as Windows opens it - the default
        # application, or the picker once when none is set. A refusal is said
        # on the red line instead of killing the window.
        try {
            Invoke-Item -LiteralPath (Join-Path $coloursRoot "$name.xaml") -ErrorAction Stop
        } catch {
            $txtThemeError.Text = "The file did not open: $($_.Exception.Message)"
            $txtThemeError.Visibility = [System.Windows.Visibility]::Visible
        }
    })

    # The catalogue: the packs of assets\packs, in a list of their own - the
    # edit button opens the selected pack's folder as Windows opens folders,
    # the trash removes the folder whole (the red CONFIRM first). A removal
    # rides back in the result: the manager's catalogue is rebuilt behind it,
    # so a pack gone here is gone from every list at once.
    $script:CatalogueChanged = $false
    $txtCatalogueError = $form.FindName("TxtCatalogueError")
    $btnPackEdit = $form.FindName("BtnGuiPackEdit")
    $btnPackDelete = $form.FindName("BtnGuiPackDelete")
    $lstPacks = $form.FindName("LstGuiPacks")
    $lstPacks.Width = $comboWidth
    $packRows = [System.Collections.Generic.List[object]]::new()
    foreach ($Pack in @($Catalog.AvailablePacks | Sort-Object Name)) {
        $packRows.Add($Pack)
        $null = $lstPacks.Items.Add("$($Pack.Name) ($($Pack.Family))")
    }
    if ($lstPacks.Items.Count -gt 0) { $lstPacks.SelectedIndex = 0 }
    $UpdatePacks = {
        $has = $lstPacks.SelectedIndex -ge 0
        $btnPackEdit.IsEnabled = $has
        $btnPackDelete.IsEnabled = $has
    }
    $lstPacks.Add_SelectionChanged({ & $UpdatePacks })
    & $UpdatePacks

    $form.FindName("BtnGuiPackEdit").Add_Click({
        if ($lstPacks.SelectedIndex -lt 0) { return }
        # A refusal is said on the red line instead of killing the window.
        try {
            Invoke-Item -LiteralPath $packRows[$lstPacks.SelectedIndex].Path -ErrorAction Stop
        } catch {
            $txtCatalogueError.Text = "The folder did not open: $($_.Exception.Message)"
            $txtCatalogueError.Visibility = [System.Windows.Visibility]::Visible
        }
    })
    $form.FindName("BtnGuiPackDelete").Add_Click({
        $at = $lstPacks.SelectedIndex
        if ($at -lt 0) { return }
        $Pack = $packRows[$at]

        # Who would be left holding a missing pack: every pack whose chain of
        # PACK_REQUIRES runs through this one - the walk follows the requires
        # until nothing new answers. Named one per line, in the question.
        $Dependents = [System.Collections.Generic.List[string]]::new()
        $Frontier = @($Pack.Name)
        while ($Frontier.Count -gt 0) {
            $Next = @()
            foreach ($Row in $packRows) {
                if ($Row.Name -eq $Pack.Name -or $Dependents.Contains($Row.Name)) { continue }
                if (@($Row.Requires | Where-Object { $Frontier -contains $_ }).Count -gt 0) {
                    $Dependents.Add($Row.Name)
                    $Next += $Row.Name
                }
            }
            $Frontier = @($Next)
        }

        $Question = "Remove the pack '$($Pack.Name)'?"
        $Danger = ""
        if ($Dependents.Count -gt 0) {
            $Question += "`n`nThese packs depend on it:"
            $Question += "`n" + (@($Dependents | ForEach-Object { "- $_" }) -join "`n")
            $Danger = "Removing it may break them."
        } else {
            $Question += " Instances already carrying it keep their own copy."
        }
        if (-not (Show-GuiConfirm -Owner $form -Title "Remove the pack" -Question $Question -Danger $Danger)) { return }
        Remove-Item -LiteralPath $Pack.Path -Recurse -Force -ErrorAction SilentlyContinue
        $packRows.RemoveAt($at)
        $lstPacks.Items.RemoveAt($at)
        $lstPacks.SelectedIndex = [Math]::Min($at, $lstPacks.Items.Count - 1)
        & $UpdatePacks
        $script:CatalogueChanged = $true
    })

    # The window's answer, one shape for both ways out: CLOSE builds it from
    # the combos, the move dialog's CONFIRM builds the same and rides its
    # folder in MoveTo.
    $BuildResult = {
        $choice = $choiceRows[[Math]::Max(0, $lstFonts.SelectedIndex)]
        $size = $sizes[[Math]::Max(0, $lstSizes.SelectedIndex)]
        $set = if ($lstColours.SelectedIndex -ge 0) { $setNames[$lstColours.SelectedIndex] } else { "" }
        [PSCustomObject]@{ Name = $choice.Name; Family = $choice.Family; Folder = $choice.Folder; Size = [int]$size; ColourSet = $set; Root = $txtRoot.Text.Trim(); CatalogueChanged = [bool]$script:CatalogueChanged; MoveTo = "$script:MoveTo" }
    }

    $script:MoveTo = ""
    $script:GuiSettingsResult = $null
    # One way out: CLOSE hands the answer back (the catalogue's flag, the
    # move dialog's folder) - the face applied as it changed, so there is
    # nothing left for it to apply.
    $form.FindName("BtnGuiClose").Add_Click({
        $script:GuiSettingsResult = & $BuildResult
        $form.Close()
    })

    Set-WindowFitToContent -Win $form -Shrink -Cap 640
    Show-PopupExclusive $window { $null = $form.ShowDialog() }
    return $script:GuiSettingsResult
}
