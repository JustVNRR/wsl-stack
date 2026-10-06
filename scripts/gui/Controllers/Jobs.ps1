# The job machinery, out of the command file: the watcher every job shares,
# the row's busy mark, and the launch. Dot-sourced at the entry's script
# level - the blocks read and write the script scope, where the state (Child,
# Poller, Ticks) lives, and the handlers read the blocks by name.

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
        # The menage: the trail is done once it has told the ending - kept
        # only when it could not.
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

# The launch every row gesture shares: the runner from the gui folder, the
# trail cleared, the child out, the watcher on - the verb says what it does.
$LaunchJob = {
    param([string]$Verb, [string]$Name, [string]$ArchiveFirst)

    # The paths hang off the entry's $GuiRoot: in a dot-sourced file,
    # $PSScriptRoot names THIS folder - the child pwsh died on a missing
    # runner (exit 64, nothing in the trail).
    $ModulePath = (Resolve-Path (Join-Path $GuiRoot "..\WslStack\WslStack.psd1")).Path
    $RunnerPath = (Resolve-Path (Join-Path $GuiRoot "Runners\JobRunner.ps1")).Path
    Remove-Item -LiteralPath (Join-Path $env:TEMP "wsl-stack-gui-job.log") -ErrorAction SilentlyContinue

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

# The machine's two lookup lists - the fonts a terminal can use and the
# Terminal's colour schemes - are heavy to read (every family probed glyph
# by glyph, every package asked) and read at most once per session. The
# reading STARTS at launch, in a thread of its own (the entry starts it);
# this is where the popups harvest it, and only when it has finished: a
# popup opened first waits for nothing, it reads the lists itself. The
# schemes travel as a HASHTABLE, never wrapped in @(): wrapped, the
# appearance form finds no scheme and its preview falls back to the bare
# phosphor literals (measured, by his eye).
function Get-GuiLookups {
    if ($script:GuiFontList -and $script:GuiSchemeList) {
        return @{ Fonts = $script:GuiFontList; Schemes = $script:GuiSchemeList }
    }

    if ($script:GuiLookupJob) {
        if ($script:GuiLookupJob.State -eq 'Completed') {
            try {
                $warm = @(Receive-Job $script:GuiLookupJob | Where-Object { $_ -is [hashtable] })
                if ($warm.Count -gt 0) {
                    $script:GuiFontList = @($warm[-1].Fonts)
                    $script:GuiSchemeList = $warm[-1].Schemes
                }
            } catch { }
        }
        Remove-Job $script:GuiLookupJob -Force -ErrorAction SilentlyContinue
        $script:GuiLookupJob = $null
    }

    if (-not $script:GuiFontList) { $script:GuiFontList = @(Get-UsableFonts) }
    if (-not $script:GuiSchemeList) { $script:GuiSchemeList = Get-ColorSchemes }
    return @{ Fonts = $script:GuiFontList; Schemes = $script:GuiSchemeList }
}
