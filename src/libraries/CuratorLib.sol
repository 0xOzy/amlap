// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";

import {PendingLib, MarketConfig, PendingUint136} from "./PendingLib.sol";
import {ConstantsLib} from "./ConstantsLib.sol";
import {ErrorsLib} from "./ErrorsLib.sol";
import {EventsLib} from "./EventsLib.sol";
import {SafeERC20Permit2Lib} from "./SafeERC20Permit2Lib.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          CHANGELOG                         */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
/*                                                            */
/* - 2026-01-16: Created library to reduce EulerEarn bytecode */
/*   - Moved submitCap validation logic from EulerEarn        */
/*   - Moved setCap logic from EulerEarn                      */
/* - 2026-01-21: Emit SubmitCap event in `submitCap()`        */
/*                                                            */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @title CuratorLib
/// @author Forked with gratitude from Euler Labs & Morpho Labs.
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice External library for curator logic. Deployed separately to reduce EulerEarn bytecode.
library CuratorLib {
    using SafeCast for uint256;
    using SafeERC20Permit2Lib for IERC20;
    using PendingLib for PendingUint136;

    /// @notice Validates and processes a submitCap request.
    /// @param config The market config mapping storage reference.
    /// @param pendingCap The pending cap mapping storage reference.
    /// @param id The strategy vault to set the cap for.
    /// @param newSupplyCap The new supply cap to set.
    /// @param asset The underlying asset of the vault.
    /// @param isStrategyAllowed Whether the strategy is allowed by the factory.
    /// @param timelock The current timelock duration.
    /// @return shouldSetCap Whether the cap should be set immediately (vs pending).
    /// @return normalizedCap The normalized supply cap value.
    function submitCap(
        mapping(IERC4626 => MarketConfig) storage config,
        mapping(IERC4626 => PendingUint136) storage pendingCap,
        IERC4626 id,
        uint256 newSupplyCap,
        address asset,
        bool isStrategyAllowed,
        uint256 timelock,
        address msgSender
    ) external returns (bool shouldSetCap, uint136 normalizedCap) {
        if (id.asset() != asset) revert ErrorsLib.InconsistentAsset(id);
        if (pendingCap[id].validAt != 0) revert ErrorsLib.AlreadyPending();
        if (config[id].removableAt != 0) revert ErrorsLib.PendingRemoval();

        // For the sake of backwards compatibility, the max allowed cap can either be set to type(uint184).max or type(uint136).max.
        normalizedCap = newSupplyCap == type(uint184).max ? type(uint136).max : newSupplyCap.toUint136();

        uint256 supplyCap = config[id].cap;
        if (normalizedCap == supplyCap) revert ErrorsLib.AlreadySet();

        if (normalizedCap < supplyCap) {
            shouldSetCap = true;
        } else {
            if (!isStrategyAllowed) revert ErrorsLib.UnauthorizedMarket(id);

            pendingCap[id].update(normalizedCap, timelock);

            emit EventsLib.SubmitCap(msgSender, id, normalizedCap);
        }
    }

    /// @notice Sets the cap of a strategy vault.
    /// @param config The market config mapping storage reference.
    /// @param pendingCap The pending cap mapping storage reference.
    /// @param withdrawQueue The withdraw queue array storage reference.
    /// @param id The strategy vault to set the cap for.
    /// @param supplyCap The new supply cap.
    /// @param asset The underlying asset.
    /// @param msgSender The msg.sender from the calling contract (for events).
    /// @return assetsToAdd The amount of assets to add to lastTotalAssets (0 if market wasn't newly enabled).
    function setCap(
        mapping(IERC4626 => MarketConfig) storage config,
        mapping(IERC4626 => PendingUint136) storage pendingCap,
        IERC4626[] storage withdrawQueue,
        IERC4626 id,
        uint136 supplyCap,
        address asset,
        address msgSender
    ) external returns (uint256 assetsToAdd) {
        MarketConfig storage marketConfig = config[id];

        (bool success, bytes memory data) = address(id).staticcall(abi.encodeWithSignature("permit2Address()"));
        address permit2 = success && data.length >= 32 ? abi.decode(data, (address)) : address(0);

        if (supplyCap > 0) {
            IERC20(asset).forceApproveMaxWithPermit2(address(id), permit2);

            if (!marketConfig.enabled) {
                withdrawQueue.push(id);

                if (withdrawQueue.length > ConstantsLib.MAX_QUEUE_LENGTH) revert ErrorsLib.MaxQueueLengthExceeded();

                marketConfig.enabled = true;
                marketConfig.balance = id.balanceOf(address(this)).toUint112();

                // Return the assets to add to lastTotalAssets (calculated as expectedSupplyAssets)
                assetsToAdd = id.previewRedeem(marketConfig.balance);

                emit EventsLib.SetWithdrawQueue(msgSender, withdrawQueue);
            }

            marketConfig.removableAt = 0;
        } else {
            IERC20(asset).revokeApprovalWithPermit2(address(id), permit2);
        }

        marketConfig.cap = supplyCap;

        emit EventsLib.SetCap(msgSender, id, supplyCap);

        delete pendingCap[id];
    }
}

