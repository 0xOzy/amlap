/// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

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

/// @title AmpleErrorsLib
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice Library exposing error messages.
library AmpleErrorsLib {
    /// @notice Thrown when the value is already set.
    error AlreadySet();

    /// @notice Thrown when the designated recipient index is invalid.
    error DesignatedRecipientInvalid();

    /// @notice Thrown when the designated recipients count is invalid (0 or > 256).
    error DesignatedRecipientsCountInvalid();

    /// @notice Thrown when the accrued interest calculated offchain is more than actual accrued interest.
    error InsufficientAccruedInterest(uint256 calculatedAccruedInterest, uint256 actualAccruedInterest);

    /// @notice Thrown when the Merkle proof is invalid.
    error MerkleProofInvalid();

    /// @notice Thrown when either of the Merkle roots are empty.
    error MerkleRootEmpty(bytes32 participantsRoot, bytes32 designatedRecipientsRoot);

    /// @notice Thrown when the Merkle root is not set.
    error MerkleRootNotSet();

    /// @notice Thrown when the caller doesn't have the payout manager role.
    error NotPayoutManagerRole();

    /// @notice Thrown when the caller is not the AmpleEarn contract.
    error NotAmpleEarn();

    /// @notice Thrown when the payout has been canceled.
    error PayoutCanceled();

    /// @notice Thrown when the payout has been claimed.
    error PayoutClaimed();

    /// @notice Thrown when the payout ID is invalid.
    error PayoutIdInvalid();

    /// @notice Thrown when the payout pool has insufficient remaining payouts.
    error PayoutInsufficient();

    /// @notice Thrown when payout recipient is the `PAYOUT_RESERVE`
    error PayoutReserveCannotClaimUnderlying();

    /// @notice Thrown when VRF proof details are empty.
    error VRFProofDetailsEmpty();

    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the amount is zero.
    error ZeroAmount();

    /// @notice Thrown when the total tickets is zero.
    error ZeroTickets();

    /// @notice Thrown when the payout is zero.
    error ZeroPayout();
}
