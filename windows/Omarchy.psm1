#Requires -Version 5.1

# Order matters: Common defines the defaults and logging the rest lean on.
$libs = @('Common.ps1', 'Preflight.ps1', 'Cidata.ps1', 'Vm.ps1', 'Guest.ps1')
foreach ($lib in $libs) {
    . (Join-Path $PSScriptRoot "lib/$lib")
}

Export-ModuleMember -Function @(
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
