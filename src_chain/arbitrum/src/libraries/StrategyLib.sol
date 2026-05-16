// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";

import {MarketConfig} from "./PendingLib.sol";
import {ErrorsLib} from "./ErrorsLib.sol";
import {UtilsLib} from "./UtilsLib.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´*/
/*                                   CHANGELOG                                    */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.*/
/*                                                                                */
/* - 2026-01-21: Created library to reduce EulerEarn bytecode                     */
/*   - Moved `_supplyStrategy()` and `_withdrawStrategy()` logic from EulerEarn   */
/*                                                                                */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.*/

/// @title StrategyLib
/// @author Forked with gratitude from Euler Labs & Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice External library for strategy allocation logic. Deployed separately to reduce EulerEarn bytecode.
library StrategyLib {
    using UtilsLib for uint256;
    using SafeCast for uint256;

    /// @notice Supplies `assets` to the strategy vaults in the supply queue.
    /// @param config The market config mapping storage reference.
    /// @param supplyQueue The supply queue array storage reference.
    /// @param assets The amount of assets to supply.
    function supplyStrategy(
        mapping(IERC4626 => MarketConfig) storage config,
        IERC4626[] storage supplyQueue,
        uint256 assets
    ) external {
        for (uint256 i; i < supplyQueue.length; ++i) {
            IERC4626 id = supplyQueue[i];

            uint256 supplyCap = config[id].cap;
            if (supplyCap == 0) continue;

            uint256 supplyAssets = id.previewRedeem(config[id].balance);

            uint256 toSupply =
                UtilsLib.min(UtilsLib.min(supplyCap.zeroFloorSub(supplyAssets), id.maxDeposit(address(this))), assets);

            if (toSupply > 0) {
                // Using try/catch to skip vaults that revert.
                try id.deposit(toSupply, address(this)) returns (uint256 suppliedShares) {
                    config[id].balance = (config[id].balance + suppliedShares).toUint112();
                    assets -= toSupply;
                } catch {}
            }

            if (assets == 0) return;
        }

        if (assets != 0) revert ErrorsLib.AllCapsReached();
    }

    /// @notice Withdraws `assets` from the strategy vaults in the withdraw queue.
    /// @param config The market config mapping storage reference.
    /// @param withdrawQueue The withdraw queue array storage reference.
    /// @param assets The amount of assets to withdraw.
    function withdrawStrategy(
        mapping(IERC4626 => MarketConfig) storage config,
        IERC4626[] storage withdrawQueue,
        uint256 assets
    ) external {
        for (uint256 i; i < withdrawQueue.length; ++i) {
            IERC4626 id = withdrawQueue[i];

            // Inline maxWithdrawFromStrategy: min(id.maxWithdraw(this), expectedSupplyAssets(id))
            uint256 expectedAssets = id.previewRedeem(config[id].balance);
            uint256 toWithdraw = UtilsLib.min(id.maxWithdraw(address(this)), expectedAssets);
            toWithdraw = UtilsLib.min(toWithdraw, assets);

            if (toWithdraw > 0) {
                // Using try/catch to skip vaults that revert.
                try id.withdraw(toWithdraw, address(this), address(this)) returns (uint256 withdrawnShares) {
                    config[id].balance = uint112(config[id].balance - withdrawnShares);
                    assets -= toWithdraw;
                } catch {}
            }

            if (assets == 0) return;
        }

        if (assets != 0) revert ErrorsLib.NotEnoughLiquidity();
    }
}

