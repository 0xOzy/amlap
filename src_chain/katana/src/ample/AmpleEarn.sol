// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {EulerEarn, EventsLib, ErrorsLib, ConstantsLib, Math, SafeCast, UtilsLib} from "../EulerEarn.sol";
import {WAD} from "../libraries/UtilsLib.sol";

import {
    IAmpleEarn,
    PayoutPool,
    DesignatedRecipientMerkleLeaf,
    VRFProofDetails,
    ONE_HUNDRED_PERCENT_FEE
} from "./interfaces/IAmpleEarn.sol";
import {AmpleErrorsLib} from "./libraries/AmpleErrorsLib.sol";
import {AmpleEventsLib} from "./libraries/AmpleEventsLib.sol";
import {AmplePayoutLib} from "./libraries/AmplePayoutLib.sol";
import {AmpleEarnReserve, IAmpleEarnReserve} from "./AmpleEarnReserve.sol";

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

/// @title AmpleEarn
/// @author Ample Money. Forked with gratitude from Euler Labs.
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice A protocol to redistribute yield to designated recipients.
contract AmpleEarn is EulerEarn, IAmpleEarn {
    using Math for uint256;
    using UtilsLib for uint256;
    using SafeCast for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarn
    string public constant VERSION = "2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarn
    address public immutable PAYOUT_RESERVE;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarn
    mapping(address account => bool isPayoutManager) public isPayoutManager;

    /// @inheritdoc IAmpleEarn
    mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool;

    /// @inheritdoc IAmpleEarn
    uint256 public totalPayoutsClaimed;

    /// @inheritdoc IAmpleEarn
    uint256 public totalPayoutsReserved;

    /// @inheritdoc IAmpleEarn
    uint256 public currentPayoutId;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Initializes the contract.
    /// @param owner The owner of the contract.
    /// @param evc The EVC address.
    /// @param permit2 The address of the Permit2 contract.
    /// @param initialTimelock The initial timelock.
    /// @param _asset The address of the underlying asset.
    /// @param __name The name of the Earn vault.
    /// @param __symbol The symbol of the Earn vault.
    /// @param _protocolFee The protocol fee.
    /// @param _protocolFeeRecipient The protocol fee recipient.
    /// @dev We pass "" as name and symbol to the ERC20 because these are overriden in this contract.
    /// This means that the contract deviates slightly from the ERC2612 standard.
    constructor(
        address owner,
        address evc,
        address permit2,
        uint256 initialTimelock,
        address _asset,
        string memory __name,
        string memory __symbol,
        uint96 _protocolFee,
        address _protocolFeeRecipient
    ) EulerEarn(owner, evc, permit2, initialTimelock, _asset, __name, __symbol) {
        PAYOUT_RESERVE = address(new AmpleEarnReserve(this));

        feeRecipient = PAYOUT_RESERVE;
        emit EventsLib.SetFeeRecipient(PAYOUT_RESERVE);

        fee = ONE_HUNDRED_PERCENT_FEE;
        emit EventsLib.SetFee(_msgSender(), fee);

        protocolFeeRecipient = _protocolFeeRecipient;
        emit EventsLib.SetProtocolFeeRecipient(_protocolFeeRecipient);

        if (_protocolFee != 0) {
            if (_protocolFee > ConstantsLib.MAX_FEE) revert ErrorsLib.MaxFeeExceeded();
            if (_protocolFeeRecipient == address(0)) revert ErrorsLib.ZeroProtocolFeeRecipient();

            protocolFee = uint96(_protocolFee);
            emit EventsLib.SetProtocolFee(_msgSender(), _protocolFee);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ONLY OWNER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarn
    function cancelPayout(uint256 payoutId) external onlyOwner {
        PayoutPool memory pool = payoutPool[payoutId];
        if (payoutId >= currentPayoutId) revert AmpleErrorsLib.PayoutIdInvalid();
        if (pool.canceled) revert AmpleErrorsLib.PayoutCanceled();
        if (pool.claimCount == pool.designatedRecipientsCount && pool.remainingPayoutAmount == 0) {
            revert AmpleErrorsLib.PayoutClaimed();
        }

        payoutPool[payoutId].canceled = true;
        totalPayoutsReserved -= pool.remainingPayoutAmount;

        emit AmpleEventsLib.CancelPayout(payoutId, pool.remainingPayoutAmount);
    }

    /// @inheritdoc IAmpleEarn
    function setIsPayoutManager(address newPayoutManager, bool newIsPayoutManager) external onlyOwner {
        if (isPayoutManager[newPayoutManager] == newIsPayoutManager) revert AmpleErrorsLib.AlreadySet();

        isPayoutManager[newPayoutManager] = newIsPayoutManager;

        emit AmpleEventsLib.SetIsPayoutManager(newPayoutManager, newIsPayoutManager);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ONLY PAYOUT MANAGER FUNCTIONS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarn
    function setMerkleRoots(
        uint256 totalTickets,
        uint8 designatedRecipientsCount,
        bytes32 designatedRecipientsRoot,
        bytes32 participantsRoot,
        uint256 accruedInterestInPayoutReserve,
        VRFProofDetails calldata vrfProofDetails
    ) external nonReentrant returns (uint256 payoutId) {
        // Use _msgSender() to allow operator-authenticated calls (e.g., through a router)
        address msgSender = _msgSender();
        if (!isPayoutManager[msgSender] && msgSender != owner()) revert AmpleErrorsLib.NotPayoutManagerRole();

        _accrueInterest();

        // Validate that the provided accrued interest does not exceed the actual available balance
        uint256 accruedInterestInPayoutReserveActual = balanceOf(PAYOUT_RESERVE) - totalPayoutsReserved;
        if (accruedInterestInPayoutReserve > accruedInterestInPayoutReserveActual) {
            revert AmpleErrorsLib.InsufficientAccruedInterest(
                accruedInterestInPayoutReserve, accruedInterestInPayoutReserveActual
            );
        }

        payoutId = currentPayoutId;

        // Delegate validation, pool state, and payout reserve state updates to library
        AmplePayoutLib.setMerkleRoots({
            payoutPool: payoutPool[payoutId],
            accruedInterest: accruedInterestInPayoutReserve,
            totalTickets: totalTickets,
            vrfProofDetails: vrfProofDetails,
            participantsRoot: participantsRoot,
            designatedRecipientsRoot: designatedRecipientsRoot,
            designatedRecipientsCount: designatedRecipientsCount
        });

        // Update global state
        totalPayoutsReserved += accruedInterestInPayoutReserve;

        unchecked {
            ++currentPayoutId;
        }

        emit AmpleEventsLib.SetMerkleRoots(
            payoutId,
            participantsRoot,
            designatedRecipientsRoot,
            designatedRecipientsCount,
            totalTickets,
            accruedInterestInPayoutReserve
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    AMPLE VAULT (PUBLIC)                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmpleEarn
    function claimPayout(
        uint256 payoutId,
        DesignatedRecipientMerkleLeaf calldata designatedRecipientLeaf,
        bytes32[] calldata designatedRecipientProof,
        bool claimInUnderlying
    ) external nonReentrant {
        if (payoutPool[payoutId].canceled) {
            revert AmpleErrorsLib.PayoutCanceled();
        }

        address recipient = designatedRecipientLeaf.user;

        if (claimInUnderlying && recipient == PAYOUT_RESERVE) {
            revert AmpleErrorsLib.PayoutReserveCannotClaimUnderlying();
        }

        // Delegate validation, pool state, and payout reserve state updates to library.
        // The merkle proof is the sole authorization — anyone can claim on behalf of a designated recipient.
        AmplePayoutLib.claimPayout({
            payoutPool: payoutPool[payoutId],
            designatedRecipientLeaf: designatedRecipientLeaf,
            designatedRecipientProof: designatedRecipientProof
        });

        uint256 payoutAmount = designatedRecipientLeaf.payoutAmount;

        // Update global state
        totalPayoutsClaimed += payoutAmount;
        totalPayoutsReserved -= payoutAmount;

        emit AmpleEventsLib.ClaimPayout(payoutId, recipient, payoutAmount, claimInUnderlying);

        if (claimInUnderlying) {
            // Approve _msgSender() (the caller) to spend PAYOUT_RESERVE's shares, then redeem to recipient.
            // _redeem calls _withdraw(_msgSender(), recipient, PAYOUT_RESERVE, ...) which checks
            // allowance of PAYOUT_RESERVE for _msgSender(), not for `recipient`.
            _approve(PAYOUT_RESERVE, _msgSender(), payoutAmount);
            _redeem(payoutAmount, recipient, PAYOUT_RESERVE);
        } else {
            // Transfer vault shares directly from the reserve to the designated recipient.
            IAmpleEarnReserve(PAYOUT_RESERVE).safeTransferPayout(recipient, payoutAmount);
        }
    }

    /// @inheritdoc IAmpleEarn
    function getCurrentPayoutAmount() external view returns (uint256 payoutAmount) {
        // Early return if there are no deposits
        if (totalSupply() == 0) return 0;

        // Get the total fee shares that would be minted if we accrued interest now
        (uint256 feeShares,,) = _accruedFeeAndAssets();

        uint256 currentShares = balanceOf(PAYOUT_RESERVE);

        // Calculate how many fee shares go to the payout reserve (after protocol fee deduction)
        // This mirrors the logic in _accrueInterest()
        uint256 payoutReserveFeeShares = feeShares;
        if (protocolFee != 0) {
            uint256 protocolFeeShares = feeShares.mulDiv(protocolFee, WAD);
            payoutReserveFeeShares = feeShares - protocolFeeShares;
        }

        // After minting payoutReserveFeeShares to payoutReserve, its total shares would be:
        uint256 futureShares = currentShares + payoutReserveFeeShares;

        // Calculate the accrued interest in shares (matching setMerkleRoots calculation)
        // reservedPayouts is in shares, so we compare shares to shares
        if (futureShares > totalPayoutsReserved) {
            payoutAmount = futureShares - totalPayoutsReserved;
        } else {
            payoutAmount = 0;
        }
    }

    /// @inheritdoc IAmpleEarn
    function isPayoutClaimed(uint256 payoutId, uint8 designatedRecipientIndex) external view returns (bool isClaimed) {
        PayoutPool storage pool = payoutPool[payoutId];
        if (designatedRecipientIndex >= pool.designatedRecipientsCount) {
            revert AmpleErrorsLib.DesignatedRecipientInvalid();
        }

        // Check if the designated recipient bit is set in the claim mask
        return (pool.claimMask & (uint256(1) << designatedRecipientIndex)) != 0;
    }
}
