# Reads every .ps1, .psm1 and .psd1 in the checkout with the parser PowerShell
# itself uses before it runs a file - a parse error left here surfaces the day
# a command runs.
#
# The classes are the one place where a file names another file's types, and
# the parser settles a type the moment it reads the file naming it: read one by
# one, every cross-reference comes up unknown. So they are read as one text, in
# the manifest's order (WslModel.psd1) with the `using` lines dropped for the
# join - and the rest of the checkout one by one.
#
# Usage:  pwsh -NoProfile -File tests\parse-check.ps1

$bad = 0

$ClassOrder = @("WslState.psm1", "WslTheme.psm1", "WslRecipe.psm1", "WslPack.psm1", "WslInstance.psm1", "WslPackCatalog.psm1", "WslInstanceManager.psm1")
$ClassesDir = Join-Path $PSScriptRoot "..\src\windows\WslModel"
$ClassPaths = @()
foreach ($ClassLib in $ClassOrder) {
    $ClassPath = Join-Path $ClassesDir $ClassLib
    if (Test-Path $ClassPath) { $ClassPaths += (Get-Item $ClassPath).FullName }
}

# The menus file carries classes of its own, and the suites' fake console
# derives from one of them: read as one text after the classes - the order the
# runtime uses - and read nowhere else.
$ClassPaths += @((Get-Item (Join-Path $PSScriptRoot "..\src\windows\WslUI.psm1")).FullName)
$ClassPaths += @((Get-Item (Join-Path $PSScriptRoot "fake-console.ps1")).FullName)

$errors = $null
$ClassText = (@($ClassPaths | ForEach-Object { (Get-Content -Path $_ -Raw) -replace '(?m)^using module .*\r?\n', '' }) -join "`n")
[void][System.Management.Automation.Language.Parser]::ParseInput($ClassText, [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host "::error file=scripts\WslModel::$($errors.Count) parse error(s)"
    foreach ($e in $errors) { Write-Host ("  line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
    $bad = 1
}

$files = @(Get-ChildItem -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
    Where-Object { $ClassPaths -notcontains $_.FullName })
foreach ($f in $files) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Host "::error file=$($f.FullName)::$($errors.Count) parse error(s)"
        foreach ($e in $errors) { Write-Host ("  line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
        $bad = 1
    }
}
Write-Host "$($files.Count + $ClassPaths.Count) file(s) read, $bad failure(s)."
exit $bad
