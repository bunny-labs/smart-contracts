// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {Clonable} from "bunny-libs/Clonable/Clonable.sol";

import "src/Distributor/Distributor.sol";

contract DistributorDeployment is Script {
    function run() external {
        vm.startBroadcast();

        address payable original = payable(0x9Fa861c2f0eC985c14b15486301C71Da93A1a525);
        Distributor d = Distributor(original);

        d.updateCloningConfig(
            Clonable.CloningConfig({
                author: 0xA91AccFfaf556C45d18dd33B8c9B82CD3464DCCB,
                feeBps: 0,
                feeRecipient: 0x19c366da11bC29d904092A344F313FB030AC9D7f
            })
        );

        vm.stopBroadcast();
    }
}
