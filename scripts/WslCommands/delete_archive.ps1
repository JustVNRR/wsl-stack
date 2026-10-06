# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # The archive's name, as typed on the command line: this command is not in
    # the menu - it is called by name, and the name is the whole confirmation.
    [Parameter(Position = 0)]
    [string]$Name,

    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager
)

$ErrorActionPreference = "Stop"

# 1. The name is the whole command line: without one, there is nothing to
# delete - and the list is where names are read from.
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host ""
    Write-Host "[ABORT] No archive name was given." -ForegroundColor (Get-MessageColour error)
    Write-Host "        The archives are listed by  .\wsl.ps1 list" -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Then:  .\wsl.ps1 delete_archive <name>" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# 2. Gone, whatever it weighs - the engine measures it first, then removes the
# folder. No question here: this command is offered nowhere a hand lands on it
# by accident, and the window's trash asks its own confirmation.
Write-Host ""
Write-Host "==> Deleting the archive '$Name'..." -ForegroundColor (Get-MessageColour info)

try {
    $Report = $Manager.DeleteArchive($Name)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing was touched." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       Archive '$Name' deleted" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Was              : " -NoNewline; Write-Host "$(Format-Size $Report.Freed)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Folder           : " -NoNewline; Write-Host "$($Report.ArchiveDir)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Gone for good - no trash, no copy kept." -ForegroundColor (Get-MessageColour muted)
Write-Host ""
