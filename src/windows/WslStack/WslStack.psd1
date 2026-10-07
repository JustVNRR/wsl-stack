# ==============================================================================
# THE MODULE: ONE NESTED FILE PER FAMILY
# ==============================================================================
# Imported fresh on every run - `Import-Module <this file> -Force` - so a
# terminal left open runs the code on disk, functions-wise. The classes are
# the chosen exception: pulled by `using module` at each naming file's top,
# they load once per window - a pull is seen by the next window (measured: the
# price of types that resolve in every file, whichever called in what shape).
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
        'WslStack.Instance.psm1'
        'WslStack.Packs.psm1'
        'WslStack.Prompts.psm1'
        'WslStack.Menus.psm1'
    )

    FunctionsToExport = @(
        # The messages
        'Get-MessageColour'
        'Write-DangerBanner'
        'Read-TerminalJson'
        'Get-SchemeColour'
        'Get-ColorSchemes'

        # The instances - the marker, the look, Docker Desktop, the engine
        'Test-TemplateInstance'
        'New-InstanceMarker'
        'Test-FontInstalled'
        'Get-UsableFonts'
        'Get-InstanceFolder'
        'Get-RegisteredDistros'
        'Get-InstanceLook'
        'Get-IconRecipe'
        'New-InstanceLook'
        'Set-InstanceLook'
        'Update-TerminalSettings'
        'Get-WslProfileGuid'
        'Set-InstanceFragment'
        'Get-InstanceAppearance'
        'ConvertTo-WslTheme'
        'Set-InstanceState'
        'Get-DockerState'
        'Set-DockerState'
        'Get-WslFragmentGuids'
        'Remove-TerminalGhostEntries'
        'Remove-StaleAppearanceFragments'
        'Remove-DockerIntegration'
        'Invoke-External'
        'Invoke-NativeCommand'
        'Test-NativeCommand'
        'Get-Distros'
        'Get-DistroNames'
        'Get-VhdxSize'
        'Format-Size'
        'Invoke-InInstance'
        'Get-InInstanceOutput'
        'Get-InstanceHome'
        'Get-InstanceFamily'
        'New-InstanceManager'

        # The packs - the catalog, and the moves a pack makes - the manager's
        # class file drives the moves by name, and only this surface is
        # visible to it
        'Get-PackCatalog'
        'Get-InstalledPacks'
        'Get-PackFolder'
        'Test-PackScript'
        'Copy-PackIntoInstance'
        'Invoke-PackScript'
        'Remove-PackFolder'
        'Enable-PackSudo'
        'Disable-PackSudo'
        'Invoke-PackOrphanCleanup'
        'Invoke-PackApply'

        # The questions - what a command asks
        'Test-InstanceName'
        'Confirm-YesNo'
        'Confirm-Destruction'
        'Stop-Cancelled'
        'Read-Answer'
        'Read-InstanceName'
        'Select-EligibleInstance'
        'Select-Packs'
        'Resolve-PackSelection'
        'Get-BuildDefaultPacks'
        'Resolve-InstallPath'
        'Resolve-InstanceIdentity'
        'Resolve-DefaultUser'
        'Get-WindowsUserProposal'

        # The menus - the doors, and the helpers beside them
        'Select-FromList'
        'Select-Distro'
        'Test-KeyInput'
        'Test-ColourOutput'
        'ConvertTo-Rgb'
        'Clear-MenuScreen'
    )
}
