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

# No parameter on purpose: there is one .wslconfig on a machine, and it is the
# user's own file - no list, nothing to pick.

$ErrorActionPreference = "Stop"

# The file WSL reads before it starts the virtual machine - the memory cap, the
# processors, the DNS tunnel, the networking mode. Per machine, not per distro:
# the instance's own wsl.conf is gmake's (wsl_config, from inside). The engine
# provides it, created commented when there was none: it documents itself, and
# WSL reads no setting nobody asked for.
$Report = $Manager.WslConfig()
$Path = $Report.Path

Write-Host ""
if ($Report.Created) {
    Write-Host "  * .wslconfig : " -NoNewline
    Write-Host "created - there was none" -ForegroundColor (Get-MessageColour success)
} else {
    Write-Host "  * .wslconfig : " -NoNewline
    Write-Host "$Path" -ForegroundColor (Get-MessageColour info)
}

Write-Host ""
Write-Host "==> Opening it - Windows picks the application it gives a .wslconfig..." -ForegroundColor (Get-MessageColour info)
try {
    Start-Process -FilePath $Path
} catch {
    Write-Host ""
    Write-Host "[WARNING] Windows did not open it: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour warning)
    Write-Host "          No application is set for .wslconfig yet - open the file" -ForegroundColor (Get-MessageColour muted)
    Write-Host "          once from Explorer and pick one; Windows remembers it." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "  A change here is read when the WSL machine starts - not by" -ForegroundColor (Get-MessageColour muted)
Write-Host "  .\wsl.ps1 restart, which restarts one instance. Stop the machine" -ForegroundColor (Get-MessageColour muted)
Write-Host "  with  wsl --shutdown  first, then open an instance again." -ForegroundColor (Get-MessageColour muted)
Write-Host ""
