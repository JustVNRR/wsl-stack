# Runs one command of scripts\WslCommands\ the way wsl.ps1 does: the shared half is loaded
# first, so the command's own -Manager parameter - typed, and settled before the
# command's first line runs - finds its type. A fresh pwsh knows nothing of the
# classes, and a parameter type is resolved before the file executes: without
# this, a command whose manager has a default dies on bind.
#
# The suites drive their commands through this file. The answers travel on
# standard input, as they always did. $LASTEXITCODE is zeroed before the
# command: a run that simply ends returns zero - what -File gave - and a
# command that raises its own exit has it forwarded.
#
# Usage:  $Answers | & $Engine -NoProfile -File tests\invoke-command.ps1 -Script <command.ps1>
[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$Script
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\scripts\instance.ps1")

$LASTEXITCODE = 0
& $Script
exit $LASTEXITCODE
