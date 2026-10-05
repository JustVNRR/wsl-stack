# The name a Windows account proposes, cleaned for the user name question: no
# build, no console, no instance - $env:USERNAME is set case by case.
#
# The rule it checks: lowercase, accents unfolded, separators turned into
# single dashes, the dashes and underscores framing the name trimmed - and
# nothing proposed when what remains cannot be a user name, because a name
# the build made up would be worse than no proposal.
#
# Usage:  pwsh -NoProfile -File tests\user-name-test.ps1

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\scripts\prompts.ps1")

$Failures = 0
function Check {
    param([string]$Name, $Got, $Expected)
    if ("$Got" -eq "$Expected") {
        Write-Output "OK   $Name"
    } else {
        Write-Output "FAIL $Name : expected '$Expected', got '$Got'"
        $script:Failures++
    }
}

function ProposalOf {
    param([string]$WindowsName)
    $env:USERNAME = $WindowsName
    return (Get-WindowsUserProposal)
}

Write-Output "--- separators become single dashes ---"
Check "Jean.Dupont" (ProposalOf "Jean.Dupont") "jean-dupont"
Check "Jean Dupont, the same" (ProposalOf "Jean Dupont") "jean-dupont"
Check "a run of them collapses" (ProposalOf "Jean  .  Dupont") "jean-dupont"

Write-Output ""
Write-Output "--- the rest is lowered, accents unfolded ---"
Check "ÉLODIE" (ProposalOf "ÉLODIE") "elodie"
Check "René" (ProposalOf "René") "rene"
Check "Jean_PC keeps its underscore" (ProposalOf "Jean_PC") "jean_pc"
Check "vieux-PC keeps its dash" (ProposalOf "vieux-PC") "vieux-pc"

Write-Output ""
Write-Output "--- the framing is trimmed ---"
Check "_jean" (ProposalOf "_jean") "jean"
Check "-jean" (ProposalOf "-jean") "jean"
Check "jean." (ProposalOf "jean.") "jean"

Write-Output ""
Write-Output "--- nothing when no user name can be made ---"
Check "a name starting with a digit" (ProposalOf "2fast") ""
Check "only separators" (ProposalOf "...") ""
Check "an empty name" (ProposalOf "") ""
Check "an underscore alone" (ProposalOf "_") ""

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
