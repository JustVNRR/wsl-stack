# ==============================================================================
# THE MODULE: ONE NESTED FILE PER FAMILY
# ==============================================================================
# Imported fresh on every run - `Import-Module <this file> -Force` - so a
# terminal left open runs the code on disk: a module is cached, -Force re-reads
# it, and that is the rule the classes still follow by staying dot-sourced (a
# class imported from a module is frozen at import, and would be the code of
# yesterday).
#
# FunctionsToExport is the module's public surface, written here and nowhere
# else: what is not listed is not visible to the scripts, however nested the
# file that defines it. Nested files share the parent's session state, so the
# families can call each other while each file stays small.
# ==============================================================================
@{
    RootModule        = ''
    ModuleVersion     = '0.1.0'
    GUID              = '0e809065-003c-4390-9020-983a77ed2927'
    Author            = 'wsl-stack'
    Description       = 'The WSL Stack tooling, one nested module per family - the messages, and the families that follow.'
    PowerShellVersion = '7.0'

    NestedModules     = @(
        'WslStack.Message.psm1'
    )

    FunctionsToExport = @(
        # The messages
        'Get-MessageColour'
        'Write-DangerBanner'
        'Read-TerminalJson'
        'Get-SchemeColour'
    )
}
