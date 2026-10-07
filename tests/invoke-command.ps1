# Runs one command of scripts\WslCommands\ the way wsl.ps1 does: the module is
# imported here, first, for the case - the commands carry no load of their own
# any more, they run through the entry and use what it imported. The manager
# travels in as a parameter, typed and bound from the command's first line.
#
# The suites drive their commands through this file. The answers travel on
# standard input, as they always did. $LASTEXITCODE is zeroed before the
# command: a run that simply ends returns zero - what -File gave - and a
# command that raises its own exit has it forwarded.
#
# Usage:  $Answers | & $Engine -NoProfile -File tests\invoke-command.ps1 -Script <command.ps1>
using module ..\src\windows\WslModel\WslModel.psd1

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$Script
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\src\windows\WslStack\WslStack.psd1") -Force

$LASTEXITCODE = 0
& $Script -Manager ([WslInstanceManager]::new([WslInstanceManager]::Root()))
exit $LASTEXITCODE
