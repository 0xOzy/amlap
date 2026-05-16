// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {IAmpleEarnReserve} from "./interfaces/IAmpleEarnReserve.sol";
import {IAmpleEarn} from "./interfaces/IAmpleEarn.sol";
import {AmpleErrorsLib} from "./libraries/AmpleErrorsLib.sol";
import {AmpleEventsLib} from "./libraries/AmpleEventsLib.sol";

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

/// @title AmpleEarnReserve
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice A contract to distribute payouts to designated recipients
contract AmpleEarnReserve is IAmpleEarnReserve {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarnReserve
    IAmpleEarn public immutable AMPLE_EARN;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Initializes the contract.
    /// @param ampleEarn The address of the AmpleEarn contract
    constructor(IAmpleEarn ampleEarn) {
        AMPLE_EARN = ampleEarn;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 ONLY PAYOUT VAULT FUNCTIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarnReserve
    function safeTransferPayout(address to, uint256 payout) external {
        if (msg.sender != address(AMPLE_EARN)) revert AmpleErrorsLib.NotAmpleEarn();

        IERC20(address(AMPLE_EARN)).safeTransfer(to, payout);

        emit AmpleEventsLib.SafeTransferPayout(to, payout);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarnReserve
    function sponsorPayout(uint256 amount, bool isUnderlying) external returns (uint256 shares) {
        if (amount == 0) revert AmpleErrorsLib.ZeroAmount();

        if (isUnderlying) {
            IERC20 underlying = IERC20(AMPLE_EARN.asset());

            // Pull underlying from sponsor
            underlying.safeTransferFrom(msg.sender, address(this), amount);

            // Approve vault to spend the underlying
            underlying.forceApprove(address(AMPLE_EARN), amount);

            // Deposit the underlying and receive shares to this contract
            shares = AMPLE_EARN.deposit(amount, address(this));
        } else {
            shares = amount;
            // Transfer the shares from the sponsor to the contract
            IERC20(address(AMPLE_EARN)).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit AmpleEventsLib.SponsorPayout(msg.sender, amount, shares);
    }
}
