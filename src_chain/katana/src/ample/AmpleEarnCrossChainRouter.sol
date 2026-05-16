// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IAmpleEarn} from "./interfaces/IAmpleEarn.sol";
import {IAmpleEarnFactory} from "./interfaces/IAmpleEarnFactory.sol";
import {
    IAmpleEarnCrossChainRouter,
    LayerZeroClaimPayoutParams,
    ClaimPayoutParams
} from "./interfaces/IAmpleEarnCrossChainRouter.sol";

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

/// @title AmpleEarnCrossChainRouter
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice Cross-chain router for claiming payouts across chains using LayerZero.
/// @dev Inherits from LayerZero OApp for cross-chain messaging capabilities.
contract AmpleEarnCrossChainRouter is OApp, IAmpleEarnCrossChainRouter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Message type for batched cross-chain claim payouts.
    uint8 internal constant MSG_TYPE_BATCH_CLAIM_PAYOUT = 1;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarnCrossChainRouter
    address public immutable factory;

    /// @inheritdoc IAmpleEarnCrossChainRouter
    uint32 public immutable localEid;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Constructs the AmpleEarnCrossChainRouter contract.
    /// @param _endpoint The address of the LayerZero endpoint on this chain.
    /// @param _owner The owner of the contract (can configure OApp peers).
    /// @param _factory The address of the AmpleEarnFactory contract on this chain.
    constructor(address _endpoint, address _owner, address _factory) OApp(_endpoint, _owner) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
        localEid = ILayerZeroEndpointV2(_endpoint).eid();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarnCrossChainRouter
    function quoteCrossChainClaim(LayerZeroClaimPayoutParams[] calldata params)
        external
        view
        returns (uint256 nativeFee)
    {
        uint256 length = params.length;
        if (length == 0) revert EmptyArray();

        for (uint256 i; i < length; ++i) {
            LayerZeroClaimPayoutParams calldata chainParams = params[i];
            if (chainParams.dstEid == localEid) continue;

            bytes memory message = _encodeBatchClaimMessage(chainParams.claims);
            MessagingFee memory fee = _quote(chainParams.dstEid, message, chainParams.options, false);
            nativeFee += fee.nativeFee;
        }
    }

    /// @inheritdoc IAmpleEarnCrossChainRouter
    function batchCrossChainClaimPayout(LayerZeroClaimPayoutParams[] calldata params)
        external
        payable
        returns (bytes32[] memory guids)
    {
        uint256 length = params.length;
        if (length == 0) revert EmptyArray();

        guids = new bytes32[](length);
        uint256 totalValueUsed;

        for (uint256 i = 0; i < length; i++) {
            LayerZeroClaimPayoutParams calldata chainParams = params[i];
            uint256 claimCount = chainParams.claims.length;
            if (claimCount == 0) continue;

            if (chainParams.dstEid == localEid) {
                _executeClaims(localEid, chainParams.claims);
                continue;
            }

            bytes memory message = _encodeBatchClaimMessage(chainParams.claims);
            MessagingFee memory fee = _quote(chainParams.dstEid, message, chainParams.options, false);

            if (totalValueUsed + fee.nativeFee > msg.value) revert InsufficientFee();

            MessagingReceipt memory receipt = _lzSend(
                chainParams.dstEid, message, chainParams.options, MessagingFee(fee.nativeFee, 0), payable(msg.sender)
            );

            guids[i] = receipt.guid;
            totalValueUsed += fee.nativeFee;

            for (uint256 j = 0; j < claimCount; j++) {
                ClaimPayoutParams memory claim = chainParams.claims[j];
                emit CrossChainClaimInitiated(chainParams.dstEid, msg.sender, claim.vault, claim.payoutId, receipt.guid);
            }
        }

        // Refund excess native token
        if (msg.value > totalValueUsed) {
            (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
            if (!success) revert TransferFailed();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Encode a batch of claim messages for cross-chain transmission.
    /// @param claims The batch of claims to encode.
    /// @return message The encoded message.
    function _encodeBatchClaimMessage(ClaimPayoutParams[] memory claims) internal pure returns (bytes memory message) {
        return abi.encode(MSG_TYPE_BATCH_CLAIM_PAYOUT, claims);
    }

    /// @dev Internal function to receive LayerZero messages.
    /// @param _origin The origin information (source chain endpoint ID, sender).
    /// @param _guid The unique message identifier.
    /// @param _message The encoded message payload.
    /// @param _executor The executor address.
    /// @param _extraData Extra data provided by the executor.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Silence unused warnings (guid/executor/extraData not needed)
        _guid;
        _executor;
        _extraData;
        (uint8 msgType, ClaimPayoutParams[] memory claims) = abi.decode(_message, (uint8, ClaimPayoutParams[]));

        if (claims.length == 0) revert EmptyArray();

        if (msgType != MSG_TYPE_BATCH_CLAIM_PAYOUT) {
            revert InvalidMessageType(msgType);
        }

        _executeClaims(_origin.srcEid, claims);
    }

    /// @dev Execute a batch of claims.
    /// @param srcEid The source chain endpoint ID (0 for local claims).
    /// @param claims The claims to execute.
    function _executeClaims(uint32 srcEid, ClaimPayoutParams[] memory claims) internal {
        bool isLocal = srcEid == localEid;
        uint256 claimCount = claims.length;

        for (uint256 i = 0; i < claimCount; i++) {
            ClaimPayoutParams memory claim = claims[i];

            if (!IAmpleEarnFactory(factory).isVault(claim.vault)) revert InvalidVault(claim.vault);

            if (IAmpleEarn(claim.vault)
                    .isPayoutClaimed(claim.payoutId, claim.designatedRecipientLeaf.designatedRecipientIndex)) continue;

            IAmpleEarn(claim.vault)
                .claimPayout(
                    claim.payoutId,
                    claim.designatedRecipientLeaf,
                    claim.designatedRecipientProof,
                    claim.claimInUnderlying
                );

            if (isLocal) {
                emit LocalClaimExecuted(claim.vault, claim.payoutId, claim.designatedRecipientLeaf.user);
            } else {
                emit CrossChainClaimExecuted(srcEid, claim.vault, claim.payoutId, claim.designatedRecipientLeaf.user);
            }
        }
    }

    /// @dev Override to handle multiple LayerZero messages in a single transaction.
    /// @param _nativeFee The native fee to pay.
    /// @return nativeFee The native fee paid.
    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert InsufficientFee();
        return _nativeFee;
    }
}
