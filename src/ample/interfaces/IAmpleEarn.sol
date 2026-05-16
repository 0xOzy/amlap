// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IEulerEarnStaticTyping} from "../../interfaces/IEulerEarn.sol";

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

uint96 constant ONE_HUNDRED_PERCENT_FEE = 1e18;

struct VRFProofDetails {
    bytes32 proof;
    bytes32 seed;
    bytes32 publicKey;
    bytes32 vrfHash;
}

struct PayoutPool {
    bool canceled;
    uint8 designatedRecipientsCount;
    uint8 claimCount;
    uint256 claimMask;
    uint256 totalPayoutAmount;
    uint256 remainingPayoutAmount;
    uint256 totalTickets;
    bytes32 participantsRoot;
    bytes32 designatedRecipientsRoot;
    VRFProofDetails vrfProofDetails;
}

struct DesignatedRecipientMerkleLeaf {
    uint256 payoutAmount;
    address user;
    uint8 designatedRecipientIndex;
}

/// @title IAmpleEarn
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice An interface for the AmpleEarn contract.
interface IAmpleEarn is IERC4626, IEulerEarnStaticTyping {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The version of the AmpleEarn contract.
    function VERSION() external pure returns (string memory);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The address of the AmpleEarnReserve contract.
    /// @dev This is immutable and set in the constructor.
    function PAYOUT_RESERVE() external view returns (address);

    /// @notice Whether an account is a payout manager.
    function isPayoutManager(address account) external view returns (bool);

    /// @notice The payout pool for a given payout ID.
    function payoutPool(uint256 payoutId)
        external
        view
        returns (
            bool canceled,
            uint8 designatedRecipientsCount,
            uint8 claimCount,
            uint256 claimMask,
            uint256 totalPayoutAmount,
            uint256 remainingPayoutAmount,
            uint256 totalTickets,
            bytes32 participantsRoot,
            bytes32 designatedRecipientsRoot,
            VRFProofDetails memory vrfProofDetails
        );

    /// @notice The total payouts claimed from the payout reserve.
    function totalPayoutsClaimed() external view returns (uint256);

    /// @notice The total payouts reserved in the payout reserve.
    function totalPayoutsReserved() external view returns (uint256);

    /// @notice The current payout ID.
    function currentPayoutId() external view returns (uint256);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ONLY OWNER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Cancel a payout for a given payout ID.
    /// @dev The payout is no longer claimable and the remaining payout amount is allocated to the next cycle.
    function cancelPayout(uint256 payoutId) external;

    /// @notice Set whether an account is a payout manager.
    function setIsPayoutManager(address newPayoutManager, bool newIsPayoutManager) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ONLY PAYOUT MANAGER FUNCTIONS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the Merkle roots for a new payout and return its payout ID.
    /// @param totalTickets The total tickets considered in the payout cycle.
    /// @param designatedRecipientsCount The number of designated recipients.
    /// @param designatedRecipientsRoot The merkle root for designated recipients.
    /// @param participantsRoot The merkle root for participants.
    /// @param accruedInterestInPayoutReserve The accrued interest to reserve.
    /// @param vrfProofDetails The VRF proof details.
    function setMerkleRoots(
        uint256 totalTickets,
        uint8 designatedRecipientsCount,
        bytes32 designatedRecipientsRoot,
        bytes32 participantsRoot,
        uint256 accruedInterestInPayoutReserve,
        VRFProofDetails calldata vrfProofDetails
    ) external returns (uint256);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    AMPLE VAULT (PUBLIC)                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Claim a payout for a given payout ID.
    /// @dev Anyone can call this on behalf of a designated recipient. The merkle proof is the sole authorization.
    /// Funds are always sent to the designated recipient specified in the merkle leaf.
    /// @param payoutId The ID of the payout to claim.
    /// @param merkleLeaf The designated recipient merkle leaf data.
    /// @param merkleProof The merkle proof for verification.
    /// @param claimInUnderlying Whether to receive the payout in underlying assets instead of shares.
    function claimPayout(
        uint256 payoutId,
        DesignatedRecipientMerkleLeaf memory merkleLeaf,
        bytes32[] calldata merkleProof,
        bool claimInUnderlying
    ) external;

    /// @notice Get the current payout amount in shares.
    function getCurrentPayoutAmount() external view returns (uint256);

    /// @notice Check if a payout has been claimed for a given payout ID and designated recipient index.
    /// @param payoutId The ID of the payout to check.
    /// @param designatedRecipientIndex The index of the designated recipient to check.
    function isPayoutClaimed(uint256 payoutId, uint8 designatedRecipientIndex) external view returns (bool);
}
