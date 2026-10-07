# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager
)

# No parameter on purpose: the instance comes from the list. The one command
# that does not act on an instance - it opens a session and steps aside.

$ErrorActionPreference = "Stop"

# 1. Which instance to open a shell in
$Distro = Select-Distro
$DistroName = $Distro.Name

Write-Host ""
Write-Host "==> Opening a shell in '$DistroName'..." -ForegroundColor (Get-MessageColour info)
if ((Get-DistroNames -Running) -notcontains $DistroName) {
    Write-Host "  It was stopped: WSL starts it on the way in, which takes a moment." -ForegroundColor (Get-MessageColour muted)
}

# 2. The shell itself: the instance opens it, on this console, through the
# engine's route. Nothing is captured from the session: it owns the terminal
# until the user leaves.
$Code = $Manager.Shell($Distro)

# The exit code is the shell's own - `exit 1` typed in there is not a failure
# of this command - and a shell that could not start must not look like a
# success: handed over, not interpreted.
exit $Code
