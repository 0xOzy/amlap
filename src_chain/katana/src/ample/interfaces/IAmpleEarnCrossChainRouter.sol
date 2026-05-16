// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {DesignatedRecipientMerkleLeaf} from "./IAmpleEarn.sol";

/*
                                   /$$
                                  | $$
  /$$$$$$  /$$$$$$/$$$$   /$$$$$$ | $$  /$$$$$$
 |____  $$| $$_  $$_  $$ /$$__  $$| $$ /$$__  $$
  /$$$$$$$| $$ \ $$ \ $$| $$  \ $$| $$| $$$$$$$$
 /$$__  $$| $$ | $$ | $$| $$  | $$| $$| $$_____/
|  $$$$$$$| $$ | $$ | $$| $$$$$$$/| $$|  $$$$$$$
 \_______/|__/ |__/ |__/| $$____/ |__/ \_______/
                        | $$
                        | $$
                        |__/
*/

/// @notice Individual claim parameters for a vault.
struct ClaimPayoutParams {
    uint256 payoutId;
    address vault;
    DesignatedRecipientMerkleLeaf designatedRecipientLeaf;
    bytes32[] designatedRecipientProof;
    bool claimInUnderlying;
}

/// @notice Parameters for claiming payouts to a single destination chain.
struct LayerZeroClaimPayoutParams {
    /// @notice Destination chain LayerZero endpoint ID.
    uint32 dstEid;
    /// @notice LayerZero executor options for this destination.
    bytes options;
    /// @notice Claims to execute on the destination chain.
    ClaimPayoutParams[] claims;
}

/// @title IAmpleEarnCrossChainRouter
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice Interface for the AmpleEarnCrossChainRouter contract.
/// @dev Uses LayerZero OApp for cross-chain messaging.
interface IAmpleEarnCrossChainRouter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();

    /// @notice Thrown when an empty array is provided to the router.
    error EmptyArray();

    /// @notice Thrown when insufficient native token is sent for the cross-chain fee.
    error InsufficientFee();

    /// @notice Thrown when an unexpected message type is received.
    error InvalidMessageType(uint8 msgType);

    /// @notice Thrown when the native token transfer fails.
    error TransferFailed();

    /// @notice Thrown when a vault is not registered with the factory.
    error InvalidVault(address vault);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a cross-chain claim is initiated.
    /// @param dstEid The destination chain's LayerZero endpoint ID.
    /// @param caller The address initiating the claim.
    /// @param vault The vault address on the destination chain.
    /// @param payoutId The payout ID being claimed.
    /// @param guid The LayerZero message GUID.
    event CrossChainClaimInitiated(
        uint32 indexed dstEid, address indexed caller, address indexed vault, uint256 payoutId, bytes32 guid
    );

    /// @notice Emitted when a cross-chain claim is executed on the destination.
    /// @param srcEid The source chain's LayerZero endpoint ID.
    /// @param vault The vault address.
    /// @param payoutId The payout ID claimed.
    /// @param to The recipient address.
    event CrossChainClaimExecuted(uint32 indexed srcEid, address indexed vault, uint256 indexed payoutId, address to);

    /// @notice Emitted when a local claim is executed directly (same chain, no cross-chain message).
    /// @param vault The vault address.
    /// @param payoutId The payout ID claimed.
    event LocalClaimExecuted(address indexed vault, uint256 indexed payoutId, address indexed to);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The AmpleEarnFactory contract address on this chain.
    function factory() external view returns (address);

    /// @notice The local chain's LayerZero endpoint ID.
    function localEid() external view returns (uint32);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Quote the fee required to send a cross-chain claim.
    /// @param params The claim parameters grouped per destination.
    /// @return nativeFee The native token fee required.
    function quoteCrossChainClaim(LayerZeroClaimPayoutParams[] calldata params)
        external
        view
        returns (uint256 nativeFee);

    /// @notice Batch initiate cross-chain payout claims to multiple chains.
    /// @dev All claims must be from the same caller (designated recipient).
    /// @param params Array of claim parameters grouped per destination.
    /// @return guids Array of LayerZero message GUIDs.
    function batchCrossChainClaimPayout(LayerZeroClaimPayoutParams[] calldata params)
        external
        payable
        returns (bytes32[] memory guids);
}
