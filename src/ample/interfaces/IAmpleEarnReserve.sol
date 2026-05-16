// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IAmpleEarn} from "./IAmpleEarn.sol";

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

/// @title IAmpleEarnReserve
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice An interface for the AmpleEarnReserve contract
interface IAmpleEarnReserve {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The AmpleEarn contract
    function AMPLE_EARN() external view returns (IAmpleEarn);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  ONLY AMPLE EARN FUNCTIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Safe transfer vault shares as a payout from the reserve.
    /// @param to Recipient address.
    /// @param payout Amount of shares to transfer.
    /// @dev Only callable by the AmpleEarn contract. For underlying redemption, AmpleEarn handles it directly.
    function safeTransferPayout(address to, uint256 payout) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sponsor a payout for a given `amount` and `isUnderlying`.
    /// @param amount The amount of the payout to sponsor.
    /// @param isUnderlying Whether the sponsor is transferring the payout in underlying or shares.
    /// @return shares The number of shares distributed to the contract.
    /// @dev Payouts are always distributed in shares.
    function sponsorPayout(uint256 amount, bool isUnderlying) external returns (uint256 shares);
}
