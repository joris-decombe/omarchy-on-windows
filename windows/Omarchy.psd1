@{
    RootModule        = 'Omarchy.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a3f1c6e4-7b2d-4f18-9c31-5e0d8a2b6417'
    Author            = 'Joris Decombe'
    Description       = 'Run Omarchy in a Hyper-V VM on Windows, with display and sound on the Windows desktop.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('Hyper-V')
    FunctionsToExport = @(
        'Test-OmarchyHost'
        'New-OmarchyVM'
        'Connect-OmarchyVM'
        'Remove-OmarchyVM'
        'New-OmarchyCidataDisk'
        'New-OmarchyPasswordHash'
        'Get-OmarchyVMAddress'
        'Copy-OmarchyGuestKit'
        'Install-OmarchyMoonlight'
        'Get-OmarchyMoonlightPath'
        'Start-OmarchyDesktop'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{
        Tags       = @('Omarchy', 'Hyper-V', 'Hyprland', 'Arch', 'Moonlight')
        LicenseUri = 'https://opensource.org/licenses/MIT'
    } }
}
