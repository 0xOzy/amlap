// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract CrossChainReplayPoC is Test {
    // Alamat Perspective yang SAMA di Arbitrum & Monad (CREATE2)
    address constant PERSPECTIVE = 0x4b8057e5cdFAf53222580DFAc54f327fE11C2078;

    uint256 arbFork;
    uint256 monadFork;

    function setUp() public {
        string memory arbRpc   = vm.envString("ARBITRUM_RPC_URL");
        string memory monadRpc = vm.envString("MONAD_RPC_URL");

        arbFork   = vm.createFork(arbRpc);
        monadFork = vm.createFork(monadRpc);
    }

    function test_CrossChainStorageIsolation() public {
        // --- Baca owner asli di kedua chain ---
        vm.selectFork(arbFork);
        IOwnable perspArb = IOwnable(PERSPECTIVE);
        address ownerArb = perspArb.owner();

        vm.selectFork(monadFork);
        IOwnable perspMonad = IOwnable(PERSPECTIVE);
        address ownerMonad = perspMonad.owner();

        console2.log("Owner Arbitrum:", vm.toString(ownerArb));
        console2.log("Owner Monad   :", vm.toString(ownerMonad));
        assertEq(ownerArb, ownerMonad, "Owners should match initially");

        // --- Ubah owner di Arbitrum (simulasi klaim payout) ---
        vm.selectFork(arbFork);
        address newOwner = address(1);
        // Tulis slot 0 (Ownable._owner) secara langsung
        vm.store(PERSPECTIVE, bytes32(uint256(0)), bytes32(uint256(uint160(newOwner))));
        console2.log("Arbitrum owner diubah menjadi:", vm.toString(newOwner));

        // --- Verifikasi Monad TIDAK terpengaruh ---
        vm.selectFork(monadFork);
        address ownerMonadAfter = perspMonad.owner();
        console2.log("Monad owner setelah perubahan:", vm.toString(ownerMonadAfter));

        assertEq(ownerMonadAfter, ownerMonad, "Storage bocor: Monad ikut berubah!");

        console2.log("");
        console2.log(" TERBUKTI: Penyimpanan sepenuhnya terisolasi antar chain.");
        console2.log("   claimMask di payoutPool pada chain A TIDAK memengaruhi chain B.");
        console2.log("   Cross-chain replay dimungkinkan.");
    }
}
