# The Windows account's name, cleaned into a user name this family accepts:
# lowercase, accents unfolded, separators turned into single dashes, and the
# dashes and underscores framing it trimmed. Nothing is proposed when what
# remains cannot be a user name - a name the build made up would be worse
# than no proposal. Reads $env:USERNAME, so a test can drive it with names of
# its own.
function Get-WindowsUserProposal {
    $Name = "$env:USERNAME".ToLower()
    $Name = $Name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $Name = $Name -replace '[^a-z0-9_-]+', '-'
    $Name = $Name.Trim('-', '_')
    if ($Name -cmatch '^[a-z][a-z0-9_-]*$') { return $Name }
    return ""
}
