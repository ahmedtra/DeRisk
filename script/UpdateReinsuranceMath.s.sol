// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceOracle.sol";
import "../src/MockToken.sol";
import "../src/InsuranceInsurer.sol";
import "../src/InsuranceReinsurer.sol";
import "../src/InsurancePolicyHolder.sol";
import "../src/InsuranceEvents.sol";
import "../src/InsuranceReinsuranceMath.sol";

contract UpdateReinsuranceMath is Script {
    
    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(deployerPrivateKey);

        // Use existing contracts
        MockToken mockToken = MockToken(0x9Fcca440F19c62CDF7f973eB6DDF218B15d4C71D);
        InsuranceOracle oracle = InsuranceOracle(0x01E21d7B8c39dc4C764c19b308Bd8b14B1ba139E);
        InsurancePolicyHolder policyHolder = InsurancePolicyHolder(0x3C1Cb427D20F15563aDa8C249E71db76d7183B6c);
        InsuranceInsurer insurer = InsuranceInsurer(0x22a9B82A6c3D2BFB68F324B2e8367f346Dd6f32a);
        InsuranceReinsurer reinsurer = InsuranceReinsurer(0x1343248Cbd4e291C6979e70a138f4c774e902561);
        InsuranceEvents eventsLogic = InsuranceEvents(0x7C8BaafA542c57fF9B2B90612bf8aB9E86e22C09);
        
        // Use the new, properly initialized reinsurance math contract
        InsuranceReinsuranceMath reinsuranceMath = InsuranceReinsuranceMath(0x975Ab64F4901Af5f0C96636deA0b9de3419D0c2F);
        
        // Deploy new insurance core with the new reinsurance math address
        InsuranceCore insurance = new InsuranceCore(
            address(mockToken),  // payment token
            address(policyHolder), 
            address(insurer), 
            address(reinsurer), 
            address(eventsLogic),
            address(reinsuranceMath)
        );
        console.log("New InsuranceCore deployed at:", address(insurance));

        // Register the same events
        insurance.registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20, // 20% threshold
            500 // 5% base premium
        );

        insurance.registerEvent(
            "AAVE Hack",
            "AAVE protocol gets hacked or exploited",
            100, // 100% threshold (any hack)
            1000 // 10% base premium
        );

        insurance.registerEvent(
            "ETH Crash",
            "Ethereum drops more than 30% in one day",
            30, // 30% threshold
            800 // 8% base premium
        );

        // Set up the relationships
        policyHolder.setEventsLogic(address(eventsLogic));
        policyHolder.setInsurer(address(insurer));
        insurer.setPolicyHolder(address(policyHolder));
        insurer.setEventsLogic(address(eventsLogic));
        insurer.setCore(address(insurance));

        vm.stopBroadcast();

        console.log("Updated deployment completed successfully!");
        console.log("New InsuranceCore:", address(insurance));
        console.log("ReinsuranceMath:", address(reinsuranceMath));
    }
}

