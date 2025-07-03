# PowerShell script to copy latest ABIs to frontend
$ErrorActionPreference = 'Stop'

$contracts = @(
    @{ name = 'InsuranceCore';         src = 'out/InsuranceCore.sol/InsuranceCore.json';         dest = 'frontend/src/abis/InsuranceCore.abi.json' },
    @{ name = 'InsuranceEvents';       src = 'out/InsuranceEvents.sol/InsuranceEvents.json';     dest = 'frontend/src/abis/InsuranceEvents.abi.json' },
    @{ name = 'InsuranceInsurer';      src = 'out/InsuranceInsurer.sol/InsuranceInsurer.json';   dest = 'frontend/src/abis/InsuranceInsurer.abi.json' },
    @{ name = 'InsuranceReinsurer';    src = 'out/InsuranceReinsurer.sol/InsuranceReinsurer.json'; dest = 'frontend/src/abis/InsuranceReinsurer.abi.json' },
    @{ name = 'InsurancePolicyHolder'; src = 'out/InsurancePolicyHolder.sol/InsurancePolicyHolder.json'; dest = 'frontend/src/abis/InsurancePolicyHolder.abi.json' },
    @{ name = 'MockToken';             src = 'out/MockToken.sol/MockToken.json';                 dest = 'frontend/src/abis/MockToken.abi.json' }
)

foreach ($contract in $contracts) {
    Write-Host "Copying ABI for $($contract.name) ..."
    $json = Get-Content $contract.src -Raw | ConvertFrom-Json
    $abi = $json.abi | ConvertTo-Json -Depth 100
    Set-Content -Path $contract.dest -Value $abi
    Write-Host "  -> $($contract.dest)"
}

Write-Host "All ABIs copied successfully!" 