// SPDX-License-Identifier: GPL-2.0-or-later
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

/// @title AmpleEventsLib
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice Library exposing events.
library AmpleEventsLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         AMPLE EARN                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a payout is canceled for a given `payoutId`.
    event CancelPayout(uint256 indexed payoutId, uint256 recoveredPayoutAmount);

    /// @notice Emitted when a payout is claimed for a given `recipient`, `payoutAmount`, and `claimInUnderlying`.
    event ClaimPayout(
        uint256 indexed payoutId, address indexed recipient, uint256 payoutAmount, bool claimInUnderlying
    );

    /// @notice Emitted when the `merkleRoots`, `designatedRecipientsCount`, `totalTickets`, and `totalPayoutAmount` are set for a given `payoutId`.
    event SetMerkleRoots(
        uint256 indexed payoutId,
        bytes32 indexed participantsRoot,
        bytes32 indexed designatedRecipientsRoot,
        uint256 designatedRecipientsCount,
        uint256 totalTickets,
        uint256 totalPayoutAmount
    );

    /// @notice Emitted when an `payoutManager` is set to `isPayoutManager`.
    event SetIsPayoutManager(address indexed payoutManager, bool indexed isPayoutManager);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     AMPLE EARN FACTORY                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new AmpleEarn vault is created.
    /// @param ampleEarn The address of the AmpleEarn vault.
    /// @param caller The caller of the function.
    /// @param initialOwner The initial owner of the AmpleEarn vault.
    /// @param initialTimelock The initial timelock of the AmpleEarn vault.
    /// @param asset The address of the underlying asset.
    /// @param name The name of the AmpleEarn vault.
    /// @param symbol The symbol of the AmpleEarn vault.
    /// @param protocolFee The protocol fee of the AmpleEarn vault.
    /// @param protocolFeeRecipient The protocol fee recipient of the AmpleEarn vault.
    /// @param salt The salt used for the AmpleEarn vault's CREATE2 address.
    event CreateAmpleEarn(
        address indexed ampleEarn,
        address indexed caller,
        address initialOwner,
        uint256 initialTimelock,
        address indexed asset,
        string name,
        string symbol,
        uint96 protocolFee,
        address protocolFeeRecipient,
        bytes32 salt
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     AMPLE EARN RESERVE                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when vault shares are transferred as a payout to `to`.
    event SafeTransferPayout(address indexed to, uint256 payoutAmount);

    /// @notice Emitted when a payout is sponsored for a given `sponsor`, `amount`, and `shares`.
    event SponsorPayout(address indexed sponsor, uint256 amount, uint256 shares);
}
