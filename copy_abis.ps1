# PowerShell script to copy contract ABIs for frontend use

Copy-Item -Path "out/InsuranceCore.sol/InsuranceCore.json" -Destination "frontend/InsuranceCore.abi.json" -Force
Copy-Item -Path "out/InsuranceOracle.sol/InsuranceOracle.json" -Destination "frontend/InsuranceOracle.abi.json" -Force
Copy-Item -Path "out/MockToken.sol/MockToken.json" -Destination "frontend/MockToken.abi.json" -Force

Write-Host "ABIs copied to frontend directory." 