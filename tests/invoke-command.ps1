# Runs one command of scripts\WslCommands\ the way wsl.ps1 does: the shared half is loaded
# first, so the command's own load finds this run's marker and stops at once -
# one read for the whole case, the classes in reach of the checks around the
# call. Nothing in a command names a class before its own load any more: a
# typed -Manager parameter used to be bound before the file's first line, and a
# standalone run died there on "Unable to find type [WslInstanceManager]"
# (measured).
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
