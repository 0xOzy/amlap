// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {
    MarketConfig,
    PendingUint136,
    PendingAddress,
    MarketAllocation,
    IEulerEarnBase,
    IEulerEarnStaticTyping
} from "./interfaces/IEulerEarn.sol";
import {IEulerEarnFactory} from "./interfaces/IEulerEarnFactory.sol";

import {PendingLib} from "./libraries/PendingLib.sol";
import {ConstantsLib} from "./libraries/ConstantsLib.sol";
import {CuratorLib} from "./libraries/CuratorLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ReallocateLib} from "./libraries/ReallocateLib.sol";
import {StrategyLib} from "./libraries/StrategyLib.sol";
import {SafeERC20Permit2Lib} from "./libraries/SafeERC20Permit2Lib.sol";
import {UtilsLib, WAD} from "./libraries/UtilsLib.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Context} from "openzeppelin-contracts/utils/Context.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {
    IERC20,
    IERC4626,
    ERC20,
    ERC4626,
    Math,
    SafeERC20
} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

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

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:˚.°*.˚*/
/*                                                   CHANGELOG                                                    */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´•*.+°.•°:´*.•.´•*.*/
/*                                                                                                                */
/* - 2025-12-05: Added protocol fee and recipient                                                                 */
/* - 2026-01-16: - Moved modifier logic to internal functions                                                     */
/*   - Removed configurability of name and symbol                                                                 */
/*   - Moved logic for `submitCap()` and `_setCap()` to CuratorLib library                                        */
/*   - Moved logic for `setSupplyQueue()`, `updateWithdrawQueue()` and `reallocate()` to ReallocateLib            */
/* - 2026-01-21: - Moved logic for `_supplyStrategy()` and `_withdrawStrategy()` to StrategyLib                   */
/*                                                                                                                */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´•*.+°.•°:´*.•.´•*.*/

/// @title EulerEarn
/// @author Forked with gratitude from Euler Labs & Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice ERC4626 compliant vault allowing users to deposit assets to any ERC4626 strategy vault allowed by the factory.
contract EulerEarn is ReentrancyGuard, ERC4626, Ownable2Step, EVCUtil, IEulerEarnStaticTyping {
    using Math for uint256;
    using UtilsLib for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20Permit2Lib for IERC20;
    using PendingLib for MarketConfig;
    using PendingLib for PendingUint136;
    using PendingLib for PendingAddress;

    /* IMMUTABLES */

    /// @inheritdoc IEulerEarnBase
    address public immutable permit2Address;

    /// @inheritdoc IEulerEarnBase
    address public immutable creator;

    /* STORAGE */

    /// @inheritdoc IEulerEarnBase
    address public curator;

    /// @inheritdoc IEulerEarnBase
    mapping(address => bool) public isAllocator;

    /// @inheritdoc IEulerEarnBase
    address public guardian;

    /// @inheritdoc IEulerEarnStaticTyping
    mapping(IERC4626 => MarketConfig) public config;

    /// @inheritdoc IEulerEarnBase
    uint256 public timelock;

    /// @inheritdoc IEulerEarnStaticTyping
    PendingAddress public pendingGuardian;

    /// @inheritdoc IEulerEarnStaticTyping
    mapping(IERC4626 => PendingUint136) public pendingCap;

    /// @inheritdoc IEulerEarnStaticTyping
    PendingUint136 public pendingTimelock;

    /// @inheritdoc IEulerEarnBase
    uint96 public fee;

    /// @inheritdoc IEulerEarnBase
    address public feeRecipient;

    /// @inheritdoc IEulerEarnBase
    uint96 public protocolFee;

    /// @inheritdoc IEulerEarnBase
    address public protocolFeeRecipient;

    /// @inheritdoc IEulerEarnBase
    IERC4626[] public supplyQueue;

    /// @inheritdoc IEulerEarnBase
    IERC4626[] public withdrawQueue;

    /// @inheritdoc IEulerEarnBase
    uint256 public lastTotalAssets;

    /// @inheritdoc IEulerEarnBase
    uint256 public lostAssets;

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param owner The owner of the contract.
    /// @param evc The EVC address.
    /// @param permit2 The address of the Permit2 contract.
    /// @param initialTimelock The initial timelock.
    /// @param _asset The address of the underlying asset.
    /// @param __name The name of the Earn vault.
    /// @param __symbol The symbol of the Earn vault.
    constructor(
        address owner,
        address evc,
        address permit2,
        uint256 initialTimelock,
        address _asset,
        string memory __name,
        string memory __symbol
    ) ERC4626(IERC20(_asset)) ERC20(__name, __symbol) Ownable(owner) EVCUtil(evc) {
        if (initialTimelock != 0) _checkTimelockBounds(initialTimelock);
        _setTimelock(initialTimelock);

        permit2Address = permit2;
        creator = msg.sender;
    }

    /* MODIFIERS */

    /// @dev Reverts if the caller doesn't have the curator role.
    modifier onlyCuratorRole() {
        _checkCuratorRole();
        _;
    }

    /// @dev Reverts if the caller doesn't have the allocator role.
    modifier onlyAllocatorRole() {
        _checkAllocatorRole();
        _;
    }

    /// @dev Reverts if the caller doesn't have the guardian role.
    modifier onlyGuardianRole() {
        _checkGuardianRole();
        _;
    }

    /// @dev Reverts if the caller doesn't have the curator nor the guardian role.
    modifier onlyCuratorOrGuardianRole() {
        _checkCuratorOrGuardianRole();
        _;
    }

    /// @dev Makes sure conditions are met to accept a pending value.
    /// @dev Reverts if:
    /// - there's no pending value;
    /// - the timelock has not elapsed since the pending value has been submitted.
    modifier afterTimelock(uint256 validAt) {
        _checkAfterTimelock(validAt);
        _;
    }

    /* ONLY OWNER FUNCTIONS */

    /// @inheritdoc IEulerEarnBase
    function setCurator(address newCurator) external onlyOwner {
        if (newCurator == curator) revert ErrorsLib.AlreadySet();

        curator = newCurator;

        emit EventsLib.SetCurator(newCurator);
    }

    /// @inheritdoc IEulerEarnBase
    function setIsAllocator(address newAllocator, bool newIsAllocator) external onlyOwner {
        if (isAllocator[newAllocator] == newIsAllocator) revert ErrorsLib.AlreadySet();

        isAllocator[newAllocator] = newIsAllocator;

        emit EventsLib.SetIsAllocator(newAllocator, newIsAllocator);
    }

    /// @inheritdoc IEulerEarnBase
    function submitTimelock(uint256 newTimelock) external onlyOwner {
        if (newTimelock == timelock) revert ErrorsLib.AlreadySet();
        if (pendingTimelock.validAt != 0) revert ErrorsLib.AlreadyPending();
        _checkTimelockBounds(newTimelock);

        if (newTimelock > timelock) {
            _setTimelock(newTimelock);
        } else {
            // Safe "unchecked" cast because newTimelock <= MAX_TIMELOCK.
            pendingTimelock.update(uint136(newTimelock), timelock);

            emit EventsLib.SubmitTimelock(newTimelock);
        }
    }

    /// @inheritdoc IEulerEarnBase
    function setFee(uint256 newFee) external nonReentrant onlyOwner {
        if (newFee == fee) revert ErrorsLib.AlreadySet();
        if (newFee > ConstantsLib.MAX_FEE) revert ErrorsLib.MaxFeeExceeded();
        if (newFee != 0 && feeRecipient == address(0)) revert ErrorsLib.ZeroFeeRecipient();

        // Accrue interest and fee using the previous fee set before changing it.
        _accrueInterest();

        // Safe "unchecked" cast because newFee <= MAX_FEE.
        fee = uint96(newFee);

        emit EventsLib.SetFee(_msgSender(), fee);
    }

    /// @inheritdoc IEulerEarnBase
    function setFeeRecipient(address newFeeRecipient) external nonReentrant onlyOwner {
        if (newFeeRecipient == feeRecipient) revert ErrorsLib.AlreadySet();
        if (newFeeRecipient == address(0) && fee != 0) revert ErrorsLib.ZeroFeeRecipient();

        // Accrue interest and fee to the previous fee recipient set before changing it.
        _accrueInterest();

        feeRecipient = newFeeRecipient;

        emit EventsLib.SetFeeRecipient(newFeeRecipient);
    }

    /// @inheritdoc IEulerEarnBase
    function setProtocolFee(uint256 newProtocolFee) external nonReentrant onlyOwner {
        if (newProtocolFee == protocolFee) revert ErrorsLib.AlreadySet();
        if (newProtocolFee > ConstantsLib.MAX_FEE) revert ErrorsLib.MaxFeeExceeded();
        if (newProtocolFee != 0 && protocolFeeRecipient == address(0)) revert ErrorsLib.ZeroProtocolFeeRecipient();

        // Accrue interest and fee using the previous fee set before changing it.
        _accrueInterest();

        // Safe "unchecked" cast because newFee <= MAX_FEE.
        protocolFee = uint96(newProtocolFee);

        emit EventsLib.SetProtocolFee(_msgSender(), newProtocolFee);
    }

    /// @inheritdoc IEulerEarnBase
    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external nonReentrant onlyOwner {
        if (newProtocolFeeRecipient == protocolFeeRecipient) revert ErrorsLib.AlreadySet();
        if (newProtocolFeeRecipient == address(0) && protocolFee != 0) revert ErrorsLib.ZeroProtocolFeeRecipient();

        // Accrue interest and fee to the previous fee recipient set before changing it.
        _accrueInterest();

        protocolFeeRecipient = newProtocolFeeRecipient;

        emit EventsLib.SetProtocolFeeRecipient(newProtocolFeeRecipient);
    }

    /// @inheritdoc IEulerEarnBase
    function submitGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == guardian) revert ErrorsLib.AlreadySet();
        if (pendingGuardian.validAt != 0) revert ErrorsLib.AlreadyPending();

        if (guardian == address(0)) {
            _setGuardian(newGuardian);
        } else {
            pendingGuardian.update(newGuardian, timelock);

            emit EventsLib.SubmitGuardian(newGuardian);
        }
    }

    /* ONLY CURATOR FUNCTIONS */

    /// @inheritdoc IEulerEarnBase
    function submitCap(IERC4626 id, uint256 newSupplyCap) external nonReentrant onlyCuratorRole {
        (bool shouldSetCap, uint136 normalizedCap) = CuratorLib.submitCap({
            config: config,
            pendingCap: pendingCap,
            id: id,
            newSupplyCap: newSupplyCap,
            asset: asset(),
            isStrategyAllowed: IEulerEarnFactory(creator).isStrategyAllowed(address(id)),
            timelock: timelock,
            msgSender: _msgSender()
        });

        if (shouldSetCap) _setCap(id, normalizedCap);
    }

    /// @inheritdoc IEulerEarnBase
    function submitMarketRemoval(IERC4626 id) external onlyCuratorRole {
        if (config[id].removableAt != 0) revert ErrorsLib.AlreadyPending();
        if (config[id].cap != 0) revert ErrorsLib.NonZeroCap();
        if (!config[id].enabled) revert ErrorsLib.MarketNotEnabled(id);
        if (pendingCap[id].validAt != 0) revert ErrorsLib.PendingCap(id);

        // Safe "unchecked" cast because timelock <= MAX_TIMELOCK.
        config[id].removableAt = uint64(block.timestamp + timelock);

        emit EventsLib.SubmitMarketRemoval(_msgSender(), id);
    }

    /* ONLY ALLOCATOR FUNCTIONS */

    /// @inheritdoc IEulerEarnBase
    function setSupplyQueue(IERC4626[] calldata newSupplyQueue) external onlyAllocatorRole {
        ReallocateLib.validateSupplyQueue(config, newSupplyQueue);

        supplyQueue = newSupplyQueue;

        emit EventsLib.SetSupplyQueue(_msgSender(), newSupplyQueue);
    }

    /// @inheritdoc IEulerEarnBase
    function updateWithdrawQueue(uint256[] calldata indexes) external onlyAllocatorRole {
        withdrawQueue = ReallocateLib.updateWithdrawQueue(config, pendingCap, withdrawQueue, indexes);

        emit EventsLib.SetWithdrawQueue(_msgSender(), withdrawQueue);
    }

    /// @inheritdoc IEulerEarnBase
    function reallocate(MarketAllocation[] calldata allocations) external nonReentrant onlyAllocatorRole {
        ReallocateLib.reallocate(config, allocations, _msgSender());
    }

    /* REVOKE FUNCTIONS */

    /// @inheritdoc IEulerEarnBase
    function revokePendingTimelock() external onlyGuardianRole {
        delete pendingTimelock;

        emit EventsLib.RevokePendingTimelock(_msgSender());
    }

    /// @inheritdoc IEulerEarnBase
    function revokePendingGuardian() external onlyGuardianRole {
        delete pendingGuardian;

        emit EventsLib.RevokePendingGuardian(_msgSender());
    }

    /// @inheritdoc IEulerEarnBase
    function revokePendingCap(IERC4626 id) external onlyCuratorOrGuardianRole {
        delete pendingCap[id];

        emit EventsLib.RevokePendingCap(_msgSender(), id);
    }

    /// @inheritdoc IEulerEarnBase
    function revokePendingMarketRemoval(IERC4626 id) external onlyCuratorOrGuardianRole {
        delete config[id].removableAt;

        emit EventsLib.RevokePendingMarketRemoval(_msgSender(), id);
    }

    /* EXTERNAL */

    /// @inheritdoc IEulerEarnBase
    function supplyQueueLength() external view returns (uint256) {
        return supplyQueue.length;
    }

    /// @inheritdoc IEulerEarnBase
    function withdrawQueueLength() external view returns (uint256) {
        return withdrawQueue.length;
    }

    /// @inheritdoc IEulerEarnBase
    function maxWithdrawFromStrategy(IERC4626 id) public view returns (uint256) {
        return UtilsLib.min(id.maxWithdraw(address(this)), expectedSupplyAssets(id));
    }

    /// @inheritdoc IEulerEarnBase
    function expectedSupplyAssets(IERC4626 id) public view returns (uint256) {
        return id.previewRedeem(config[id].balance);
    }

    /// @inheritdoc IEulerEarnBase
    function acceptTimelock() external afterTimelock(pendingTimelock.validAt) {
        _setTimelock(pendingTimelock.value);
    }

    /// @inheritdoc IEulerEarnBase
    function acceptGuardian() external afterTimelock(pendingGuardian.validAt) {
        _setGuardian(pendingGuardian.value);
    }

    /// @inheritdoc IEulerEarnBase
    function acceptCap(IERC4626 id) external afterTimelock(pendingCap[id].validAt) {
        if (!IEulerEarnFactory(creator).isStrategyAllowed(address(id))) revert ErrorsLib.UnauthorizedMarket(id);

        // Safe "unchecked" cast because pendingCap <= type(uint136).max.
        _setCap(id, uint136(pendingCap[id].value));
    }

    /* ERC4626 (PUBLIC) */

    /// @inheritdoc IERC4626
    /// @dev Warning: May be higher than the actual max deposit due to duplicate vaults in the supplyQueue.
    /// @dev If deposit would throw ZeroShares error, function returns 0.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 suppliable = _maxDeposit();

        return _convertToShares(suppliable, Math.Rounding.Floor) == 0 ? 0 : suppliable;
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be higher than the actual max mint due to duplicate vaults in the supplyQueue.
    function maxMint(address) public view override returns (uint256) {
        uint256 suppliable = _maxDeposit();

        return _convertToShares(suppliable, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be lower than the actual amount of assets that can be withdrawn by `owner` due to conversion
    /// roundings between shares and assets.
    function maxWithdraw(address owner) public view override returns (uint256 assets) {
        (assets,,) = _maxWithdraw(owner);
    }

    /// @inheritdoc IERC4626
    /// @dev Warning: May be lower than the actual amount of shares that can be redeemed by `owner` due to conversion
    /// roundings between shares and assets.
    function maxRedeem(address owner) public view override returns (uint256) {
        (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) = _maxWithdraw(owner);

        return _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        _accrueInterest();

        shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Floor);

        if (shares == 0) revert ErrorsLib.ZeroShares();

        _deposit(_msgSender(), receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        _accrueInterest();

        assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);

        _deposit(_msgSender(), receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        _accrueInterest();

        // Do not call expensive `maxWithdraw` and optimistically withdraw assets.

        shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeem(shares, receiver, owner);
    }

    /// @inheritdoc IERC4626
    /// @dev totalAssets is the sum of the vault's assets on the strategy vaults plus the lost assets (see corresponding
    /// docs in IEulerEarn.sol).
    function totalAssets() public view override returns (uint256) {
        (, uint256 newTotalAssets,) = _accruedFeeAndAssets();

        return newTotalAssets;
    }

    /* ERC4626 (INTERNAL) */

    /// @dev Returns the maximum amount of asset (`assets`) that the `owner` can withdraw from the vault, as well as the
    /// new vault's total supply (`newTotalSupply`) and total assets (`newTotalAssets`).
    function _maxWithdraw(address owner)
        internal
        view
        returns (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets)
    {
        uint256 feeShares;
        (feeShares, newTotalAssets,) = _accruedFeeAndAssets();
        newTotalSupply = totalSupply() + feeShares;

        assets = _convertToAssetsWithTotals(balanceOf(owner), newTotalSupply, newTotalAssets, Math.Rounding.Floor);
        assets -= _simulateWithdrawStrategy(assets);
    }

    /// @dev Returns the maximum amount of assets that the Earn vault can supply to the strategy vaults.
    function _maxDeposit() internal view returns (uint256 totalSuppliable) {
        for (uint256 i; i < supplyQueue.length; ++i) {
            IERC4626 id = supplyQueue[i];

            uint256 supplyCap = config[id].cap;
            if (supplyCap == 0) continue;

            uint256 supplyAssets = expectedSupplyAssets(id);

            totalSuppliable += UtilsLib.min(supplyCap.zeroFloorSub(supplyAssets), id.maxDeposit(address(this)));
        }
    }

    /// @inheritdoc ERC4626
    /// @dev The accrual of performance fees is taken into account in the conversion.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets,) = _accruedFeeAndAssets();

        return _convertToSharesWithTotals(assets, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    /// @inheritdoc ERC4626
    /// @dev The accrual of performance fees is taken into account in the conversion.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets,) = _accruedFeeAndAssets();

        return _convertToAssetsWithTotals(shares, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    /// @dev Returns the amount of shares that the vault would exchange for the amount of `assets` provided.
    /// @dev It assumes that the arguments `newTotalSupply` and `newTotalAssets` are up to date.
    function _convertToSharesWithTotals(
        uint256 assets,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) internal pure returns (uint256) {
        return assets.mulDiv(
            newTotalSupply + ConstantsLib.VIRTUAL_AMOUNT, newTotalAssets + ConstantsLib.VIRTUAL_AMOUNT, rounding
        );
    }

    /// @dev Returns the amount of assets that the vault would exchange for the amount of `shares` provided.
    /// @dev It assumes that the arguments `newTotalSupply` and `newTotalAssets` are up to date.
    function _convertToAssetsWithTotals(
        uint256 shares,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) internal pure returns (uint256) {
        return shares.mulDiv(
            newTotalAssets + ConstantsLib.VIRTUAL_AMOUNT, newTotalSupply + ConstantsLib.VIRTUAL_AMOUNT, rounding
        );
    }

    /// @inheritdoc ERC4626
    /// @dev Used in mint or deposit to deposit the underlying asset to strategy vaults.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        IERC20(asset()).safeTransferFromWithPermit2(caller, address(this), assets, permit2Address);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);

        StrategyLib.supplyStrategy(config, supplyQueue, assets);

        // `lastTotalAssets + assets` may be a little above `totalAssets()`.
        // This can lead to a small accrual of `lostAssets` at the next interaction.
        _updateLastTotalAssets(lastTotalAssets + assets);
    }

    /// @inheritdoc ERC4626
    /// @dev Used in redeem or withdraw to withdraw the underlying asset from the strategy vaults.
    /// @dev Depending on 3 cases, reverts when withdrawing "too much" with:
    /// 1. NotEnoughLiquidity when withdrawing more than available liquidity.
    /// 2. ERC20InsufficientAllowance when withdrawing more than `caller`'s allowance.
    /// 3. ERC20InsufficientBalance when withdrawing more than `owner`'s balance.
    /// @dev The function prevents sending assets to addresses which are known to be EVC sub-accounts
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        // assets sent to EVC sub-accounts would be lost, as the private key for a sub-account is not known
        address evcOwner = evc.getAccountOwner(receiver);
        if (evcOwner != address(0) && evcOwner != receiver) {
            revert ErrorsLib.BadAssetReceiver();
        }

        // `lastTotalAssets - assets` may be a little above `totalAssets()`.
        // This can lead to a small accrual of `lostAssets` at the next interaction.
        // clamp at 0 so the error raised is the more informative NotEnoughLiquidity.
        _updateLastTotalAssets(lastTotalAssets.zeroFloorSub(assets));

        StrategyLib.withdrawStrategy(config, withdrawQueue, assets);

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _redeem(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        _accrueInterest();

        // Do not call expensive `maxRedeem` and optimistically redeem shares.

        assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Floor);

        // Since losses are not realized, exchange rate is never < 1 and zero assets check is not needed.

        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /* INTERNAL */

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view virtual override(EVCUtil, Context) returns (address) {
        return EVCUtil._msgSender();
    }

    /// @dev Reverts if `newTimelock` is not within the bounds.
    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > ConstantsLib.MAX_TIMELOCK) revert ErrorsLib.AboveMaxTimelock();
        if (newTimelock < ConstantsLib.POST_INITIALIZATION_MIN_TIMELOCK) revert ErrorsLib.BelowMinTimelock();
    }

    /// @dev Sets `timelock` to `newTimelock`.
    function _setTimelock(uint256 newTimelock) internal {
        timelock = newTimelock;

        emit EventsLib.SetTimelock(_msgSender(), newTimelock);

        delete pendingTimelock;
    }

    /// @dev Sets `guardian` to `newGuardian`.
    function _setGuardian(address newGuardian) internal {
        guardian = newGuardian;

        emit EventsLib.SetGuardian(_msgSender(), newGuardian);

        delete pendingGuardian;
    }

    /// @dev Sets the cap of the vault to `supplyCap`.
    function _setCap(IERC4626 id, uint136 supplyCap) internal {
        uint256 assetsToAdd = CuratorLib.setCap({
            config: config,
            pendingCap: pendingCap,
            withdrawQueue: withdrawQueue,
            id: id,
            supplyCap: supplyCap,
            asset: asset(),
            msgSender: _msgSender()
        });

        // Update lastTotalAssets if market was newly enabled
        if (assetsToAdd > 0) {
            _updateLastTotalAssets(lastTotalAssets + assetsToAdd);
        }
    }

    /* LIQUIDITY ALLOCATION */

    /// @dev Simulates a withdraw of `assets` from the strategy vaults.
    /// @return The remaining assets to be withdrawn.
    function _simulateWithdrawStrategy(uint256 assets) internal view returns (uint256) {
        for (uint256 i; i < withdrawQueue.length; ++i) {
            IERC4626 id = withdrawQueue[i];

            assets = assets.zeroFloorSub(maxWithdrawFromStrategy(id));

            if (assets == 0) break;
        }

        return assets;
    }

    /* FEE MANAGEMENT */

    /// @dev Updates `lastTotalAssets` to `updatedTotalAssets`.
    function _updateLastTotalAssets(uint256 updatedTotalAssets) internal {
        lastTotalAssets = updatedTotalAssets;

        emit EventsLib.UpdateLastTotalAssets(updatedTotalAssets);
    }

    /// @dev Accrues `lastTotalAssets`, `lostAssets` and mints the fee shares to the fee recipient.
    function _accrueInterest() internal {
        (uint256 feeShares, uint256 newTotalAssets, uint256 newLostAssets) = _accruedFeeAndAssets();

        _updateLastTotalAssets(newTotalAssets);
        lostAssets = newLostAssets;
        emit EventsLib.UpdateLostAssets(newLostAssets);

        uint256 protocolFeeShares = 0;
        if (feeShares != 0) {
            if (protocolFee != 0) {
                // It is acknowledged that `protocolFeeShares` will only be calculated if a `fee` is set
                // and it may be rounded down to 0 if `feeShares * protocolFee < WAD`.
                protocolFeeShares = feeShares.mulDiv(protocolFee, WAD);
                // The protocol fee shares are subtracted from the fee shares to be minted to the fee recipient.
                feeShares -= protocolFeeShares;
                if (protocolFeeShares != 0) _mint(protocolFeeRecipient, protocolFeeShares);
            }
            _mint(feeRecipient, feeShares);
        }

        emit EventsLib.AccrueInterest(newTotalAssets, feeShares, protocolFeeShares);
    }

    /// @dev Computes and returns the `feeShares` to mint, the new `totalAssets` and the new `lostAssets`.
    /// @return feeShares the shares to mint to `feeRecipient`.
    /// @return newTotalAssets the new `totalAssets`.
    /// @return newLostAssets the new lostAssets.
    function _accruedFeeAndAssets()
        internal
        view
        returns (uint256 feeShares, uint256 newTotalAssets, uint256 newLostAssets)
    {
        // The assets that the Earn vault has on the strategy vaults.
        uint256 realTotalAssets;
        for (uint256 i; i < withdrawQueue.length; ++i) {
            IERC4626 id = withdrawQueue[i];
            realTotalAssets += expectedSupplyAssets(id);
        }

        uint256 lastTotalAssetsCached = lastTotalAssets;
        if (realTotalAssets < lastTotalAssetsCached - lostAssets) {
            // If the vault lost some assets (realTotalAssets decreased), lostAssets is increased.
            newLostAssets = lastTotalAssetsCached - realTotalAssets;
        } else {
            // If it did not, lostAssets stays the same.
            newLostAssets = lostAssets;
        }

        newTotalAssets = realTotalAssets + newLostAssets;
        uint256 totalInterest = newTotalAssets - lastTotalAssetsCached;
        if (totalInterest != 0 && fee != 0) {
            // It is acknowledged that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
            uint256 feeAssets = totalInterest.mulDiv(fee, WAD);
            // The fee assets is subtracted from the total assets in this calculation to compensate for the fact
            // that total assets is already increased by the total interest (including the fee assets).
            feeShares =
                _convertToSharesWithTotals(feeAssets, totalSupply(), newTotalAssets - feeAssets, Math.Rounding.Floor);
        }
    }

    /// @dev Checks curator role, reverting otherwise.
    function _checkCuratorRole() internal view {
        address msgSender = _msgSenderOnlyEVCAccountOwner();
        if (msgSender != curator && msgSender != owner()) revert ErrorsLib.NotCuratorRole();
    }

    /// @dev Checks allocator role, reverting otherwise.
    function _checkAllocatorRole() internal view {
        address msgSender = _msgSenderOnlyEVCAccountOwner();
        if (!isAllocator[msgSender] && msgSender != curator && msgSender != owner()) {
            revert ErrorsLib.NotAllocatorRole();
        }
    }

    /// @dev Checks guardian role, reverting otherwise.
    function _checkGuardianRole() internal view {
        address msgSender = _msgSenderOnlyEVCAccountOwner();
        if (msgSender != owner() && msgSender != guardian) revert ErrorsLib.NotGuardianRole();
    }

    /// @dev Checks curator or guardian role, reverting otherwise.
    function _checkCuratorOrGuardianRole() internal view {
        address msgSender = _msgSenderOnlyEVCAccountOwner();
        if (msgSender != guardian && msgSender != curator && msgSender != owner()) {
            revert ErrorsLib.NotCuratorNorGuardianRole();
        }
    }

    /// @dev Checks timelock completion for a pending value.
    function _checkAfterTimelock(uint256 validAt) internal view {
        if (validAt == 0) revert ErrorsLib.NoPendingValue();
        if (block.timestamp < validAt) revert ErrorsLib.TimelockNotElapsed();
    }
}
