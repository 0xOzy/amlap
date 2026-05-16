// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          CHANGELOG                         */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
/*                                                            */
/* - 2025-11-12: Updated MAX_FEE from 0.5e18 to 1e18 (100%)   */
/*                                                            */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @title ConstantsLib
/// @author Forked with gratitude from Euler Labs & Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice Library exposing constants.
library ConstantsLib {
    /// @dev The maximum delay of a timelock.
    uint256 internal constant MAX_TIMELOCK = 2 weeks;

    /// @dev The minimum delay of a timelock post initialization.
    uint256 internal constant POST_INITIALIZATION_MIN_TIMELOCK = 1 days;

    /// @dev The maximum number of vaults in the supply/withdraw queue.
    uint256 internal constant MAX_QUEUE_LENGTH = 30;

    /// @dev The maximum fee the vault can have (100%).
    uint256 internal constant MAX_FEE = 1e18;

    /// @dev The virtual amount added to total shares and total assets.
    uint256 internal constant VIRTUAL_AMOUNT = 1e6;
}
