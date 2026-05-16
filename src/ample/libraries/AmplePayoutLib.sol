// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";

import {PayoutPool, DesignatedRecipientMerkleLeaf, VRFProofDetails} from "../interfaces/IAmpleEarn.sol";
import {AmpleErrorsLib} from "./AmpleErrorsLib.sol";

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

/// @title AmplePayoutLib
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice External library for payout claiming logic. Deployed separately to reduce AmpleEarnImplementation bytecode.
library AmplePayoutLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ONLY PAYOUT MANAGER FUNCTIONS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates and sets merkle roots for a new payout pool.
    /// @param payoutPool The payout pool storage reference.
    /// @param accruedInterest The accrued interest to reserve.
    /// @param totalTickets The total tickets considered in the payout cycle.
    /// @param vrfProofDetails The VRF proof details.
    /// @param participantsRoot The merkle root for participants.
    /// @param designatedRecipientsRoot The merkle root for designated recipients.
    /// @param designatedRecipientsCount The number of designated recipients.
    function setMerkleRoots(
        PayoutPool storage payoutPool,
        uint256 accruedInterest,
        uint256 totalTickets,
        VRFProofDetails calldata vrfProofDetails,
        bytes32 participantsRoot,
        bytes32 designatedRecipientsRoot,
        uint8 designatedRecipientsCount
    ) external {
        if (participantsRoot == bytes32(0) || designatedRecipientsRoot == bytes32(0)) {
            revert AmpleErrorsLib.MerkleRootEmpty(participantsRoot, designatedRecipientsRoot);
        }
        if (totalTickets == 0) revert AmpleErrorsLib.ZeroTickets();
        if (designatedRecipientsCount == 0) revert AmpleErrorsLib.DesignatedRecipientsCountInvalid();
        if (
            vrfProofDetails.proof == bytes32(0) || vrfProofDetails.seed == bytes32(0)
                || vrfProofDetails.publicKey == bytes32(0) || vrfProofDetails.vrfHash == bytes32(0)
        ) {
            revert AmpleErrorsLib.VRFProofDetailsEmpty();
        }

        if (payoutPool.participantsRoot != bytes32(0) || payoutPool.designatedRecipientsRoot != bytes32(0)) {
            revert AmpleErrorsLib.AlreadySet();
        }

        if (accruedInterest == 0) revert AmpleErrorsLib.ZeroPayout();

        payoutPool.totalPayoutAmount = payoutPool.remainingPayoutAmount = accruedInterest;
        payoutPool.totalTickets = totalTickets;
        payoutPool.participantsRoot = participantsRoot;
        payoutPool.designatedRecipientsRoot = designatedRecipientsRoot;
        payoutPool.designatedRecipientsCount = designatedRecipientsCount;
        payoutPool.vrfProofDetails = vrfProofDetails;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    AMPLE VAULT (PUBLIC)                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates and processes a payout claim.
    /// @param payoutPool The payout pool storage reference.
    /// @param designatedRecipientLeaf The designated recipient's merkle leaf data.
    /// @param designatedRecipientProof The merkle proof for the designated recipient.
    function claimPayout(
        PayoutPool storage payoutPool,
        DesignatedRecipientMerkleLeaf calldata designatedRecipientLeaf,
        bytes32[] calldata designatedRecipientProof
    ) external {
        PayoutPool memory pool = payoutPool;
        if (designatedRecipientLeaf.designatedRecipientIndex >= pool.designatedRecipientsCount) {
            revert AmpleErrorsLib.DesignatedRecipientInvalid();
        }

        uint256 designatedRecipientBit = uint256(1) << designatedRecipientLeaf.designatedRecipientIndex;
        if ((pool.claimMask & designatedRecipientBit) != 0) {
            revert AmpleErrorsLib.PayoutClaimed();
        }

        if (pool.participantsRoot == bytes32(0) || pool.designatedRecipientsRoot == bytes32(0)) {
            revert AmpleErrorsLib.MerkleRootNotSet();
        }

        uint256 payoutAmount = designatedRecipientLeaf.payoutAmount;

        bytes32 leaf = keccak256(
            abi.encode(payoutAmount, designatedRecipientLeaf.user, designatedRecipientLeaf.designatedRecipientIndex)
        );
        if (!MerkleProof.verify(designatedRecipientProof, pool.designatedRecipientsRoot, leaf)) {
            revert AmpleErrorsLib.MerkleProofInvalid();
        }

        // Validate payout accounting
        if (pool.remainingPayoutAmount < payoutAmount) {
            revert AmpleErrorsLib.PayoutInsufficient();
        }

        // Set the bit for this specific outcome in the claim mask using bitwise OR
        payoutPool.claimMask |= designatedRecipientBit;
        unchecked {
            ++payoutPool.claimCount;
        }

        // Update payoutPool state
        payoutPool.remainingPayoutAmount -= payoutAmount;
    }
}
