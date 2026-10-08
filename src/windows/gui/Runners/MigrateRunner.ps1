# The migrate's own window, for real: the command runs in this console - the
# console IS the log - and the window waits for a key whatever happened,
# because pressing it reopens the fleet manager: the move started with the
# window closed, and the key is how it comes back. The window's road hands
# its arguments over positionally, in the order the param line below declares
# - gui.ps1's ArgumentList and that line must agree, and gui-test.ps1 pins
# both.

param([string]$Target, [string]$Module, [string]$Entry)

Import-Module $Module -Force
& $Entry migrate -Target $Target

Write-Host ""
Write-Host "  Press any key to close this window - the fleet manager reopens with it." -ForegroundColor (Get-MessageColour hint)
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Start-Process pwsh -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$Entry`"", "gui") -WindowStyle Hidden
