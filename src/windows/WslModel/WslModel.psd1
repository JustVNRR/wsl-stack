# ==============================================================================
# THE MODEL, AS A MODULE: ONE CLASS PER FILE, THE ORDER THEY MUST BE READ
# ==============================================================================
# What a consumer pulls by `using module .\WslModel\WslModel.psd1`: the six
# classes, given to the consuming file at parse time - every function, filter
# and parameter that names one finds it, whoever called whom (measured). Each
# class file pulls what it names itself, so this list's order is the reading
# order, nothing more.
# ==============================================================================
@{
    RootModule    = ''
    ModuleVersion = '0.1.0'
    GUID          = '02446b50-7627-44fa-8462-ed2f4abc8318'

    NestedModules = @(
        'WslState.psm1'
        'WslTheme.psm1'
        'WslPack.psm1'
        'WslInstance.psm1'
        'WslPackCatalog.psm1'
        'WslInstanceManager.psm1'
    )
}
