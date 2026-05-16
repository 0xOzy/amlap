// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";

import {MarketConfig, PendingUint136} from "./PendingLib.sol";
import {MarketAllocation} from "../interfaces/IEulerEarn.sol";
import {ConstantsLib} from "./ConstantsLib.sol";
import {ErrorsLib} from "./ErrorsLib.sol";
import {EventsLib} from "./EventsLib.sol";
import {UtilsLib} from "./UtilsLib.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          CHANGELOG                         */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
/*                                                            */
/* - 2026-01-16: Created library to reduce EulerEarn bytecode */
/*   - Moved reallocate logic from EulerEarn                  */
/*   - Moved updateWithdrawQueue logic from EulerEarn         */
/*   - Added validateSupplyQueue function                     */
/*                                                            */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @title ReallocateLib
/// @author Forked with gratitude from Euler Labs & Morpho Labs.
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice External library for reallocation and queue management logic. Deployed separately to reduce EulerEarn bytecode.
library ReallocateLib {
    using UtilsLib for uint256;
    using SafeCast for uint256;

    /// @notice Reallocates liquidity across strategy vaults.
    /// @param config The market config mapping storage reference.
    /// @param allocations The array of market allocations to process.
    /// @param msgSender The msg.sender from the calling contract (for events).
    function reallocate(
        mapping(IERC4626 => MarketConfig) storage config,
        MarketAllocation[] calldata allocations,
        address msgSender
    ) external {
        uint256 totalSupplied;
        uint256 totalWithdrawn;

        for (uint256 i; i < allocations.length; ++i) {
            MarketAllocation memory allocation = allocations[i];
            IERC4626 id = allocation.id;
            if (!config[id].enabled) revert ErrorsLib.MarketNotEnabled(id);

            uint256 supplyShares = config[id].balance;
            uint256 supplyAssets = id.previewRedeem(supplyShares);
            uint256 withdrawn = supplyAssets.zeroFloorSub(allocation.assets);

            if (withdrawn > 0) {
                // Guarantees that unknown frontrunning donations can be withdrawn, in order to disable a market.
                uint256 shares;
                if (allocation.assets == 0) {
                    shares = supplyShares;
                    withdrawn = 0;
                }

                uint256 withdrawnAssets;
                uint256 withdrawnShares;

                if (shares == 0) {
                    withdrawnAssets = withdrawn;
                    withdrawnShares = id.withdraw(withdrawn, address(this), address(this));
                } else {
                    withdrawnAssets = id.redeem(shares, address(this), address(this));
                    withdrawnShares = shares;
                }

                config[id].balance = uint112(supplyShares - withdrawnShares);

                emit EventsLib.ReallocateWithdraw(msgSender, id, withdrawnAssets, withdrawnShares);

                totalWithdrawn += withdrawnAssets;
            } else {
                uint256 suppliedAssets = allocation.assets == type(uint256).max
                    ? totalWithdrawn.zeroFloorSub(totalSupplied)
                    : allocation.assets.zeroFloorSub(supplyAssets);

                if (suppliedAssets == 0) continue;

                uint256 supplyCap = config[id].cap;
                if (supplyAssets + suppliedAssets > supplyCap) revert ErrorsLib.SupplyCapExceeded(id);

                // The vault's underlying asset is guaranteed to be the vault's asset because it has a non-zero supply cap.
                uint256 suppliedShares = id.deposit(suppliedAssets, address(this));

                config[id].balance = (supplyShares + suppliedShares).toUint112();

                emit EventsLib.ReallocateSupply(msgSender, id, suppliedAssets, suppliedShares);

                totalSupplied += suppliedAssets;
            }
        }

        if (totalWithdrawn != totalSupplied) revert ErrorsLib.InconsistentReallocation();
    }

    /// @notice Updates the withdraw queue by reordering and optionally removing markets.
    /// @param config The market config mapping storage reference.
    /// @param pendingCap The pending cap mapping storage reference.
    /// @param withdrawQueue The withdraw queue array storage reference.
    /// @param indexes The new order of indexes for the withdraw queue.
    /// @return newWithdrawQueue The new withdraw queue.
    function updateWithdrawQueue(
        mapping(IERC4626 => MarketConfig) storage config,
        mapping(IERC4626 => PendingUint136) storage pendingCap,
        IERC4626[] calldata withdrawQueue,
        uint256[] calldata indexes
    ) external returns (IERC4626[] memory newWithdrawQueue){
        uint256 newLength = indexes.length;
        uint256 currLength = withdrawQueue.length;

        bool[] memory seen = new bool[](currLength);
        newWithdrawQueue = new IERC4626[](newLength);

        for (uint256 i; i < newLength; ++i) {
            uint256 prevIndex = indexes[i];

            // If prevIndex >= currLength, it will revert with native "Index out of bounds".
            IERC4626 id = withdrawQueue[prevIndex];
            if (seen[prevIndex]) revert ErrorsLib.DuplicateMarket(id);
            seen[prevIndex] = true;

            newWithdrawQueue[i] = id;
        }

        for (uint256 i; i < currLength; ++i) {
            if (!seen[i]) {
                IERC4626 id = withdrawQueue[i];

                if (config[id].cap != 0) revert ErrorsLib.InvalidMarketRemovalNonZeroCap(id);
                if (pendingCap[id].validAt != 0) revert ErrorsLib.PendingCap(id);

                if (id.previewRedeem(config[id].balance) != 0) {
                    if (config[id].removableAt == 0) revert ErrorsLib.InvalidMarketRemovalNonZeroSupply(id);

                    if (block.timestamp < config[id].removableAt) {
                        revert ErrorsLib.InvalidMarketRemovalTimelockNotElapsed(id);
                    }
                }

                delete config[id];
            }
        }
    }

    /// @notice Validates the new supply queue.
    /// @param config The market config mapping storage reference.
    /// @param newSupplyQueue The new supply queue to validate.
    function validateSupplyQueue(
        mapping(IERC4626 => MarketConfig) storage config,
        IERC4626[] calldata newSupplyQueue
    ) external view {
        uint256 length = newSupplyQueue.length;

        if (length > ConstantsLib.MAX_QUEUE_LENGTH) revert ErrorsLib.MaxQueueLengthExceeded();

        for (uint256 i; i < length; ++i) {
            if (config[newSupplyQueue[i]].cap == 0) revert ErrorsLib.UnauthorizedMarket(newSupplyQueue[i]);
        }
    }

}

