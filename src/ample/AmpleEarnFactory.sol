// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IPerspective} from "../interfaces/IPerspective.sol";

import {EventsLib} from "../libraries/EventsLib.sol";
import {ErrorsLib} from "../libraries/ErrorsLib.sol";

import {Ownable2Step, Ownable} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {Context} from "openzeppelin-contracts/utils/Context.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

import {AmpleEventsLib} from "./libraries/AmpleEventsLib.sol";
import {IAmpleEarnFactory, IAmpleEarn} from "./interfaces/IAmpleEarnFactory.sol";
import {AmpleEarn} from "./AmpleEarn.sol";

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

/// @title AmpleEarnFactory
/// @author Ample Money. Forked with gratitude from Euler Labs.
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice This contract allows to create AmpleEarn vaults, and to index them easily.
contract AmpleEarnFactory is Ownable2Step, EVCUtil, IAmpleEarnFactory {
    /* IMMUTABLES */

    /// @inheritdoc IAmpleEarnFactory
    address public immutable permit2Address;

    /* STORAGE */

    /// @inheritdoc IAmpleEarnFactory
    mapping(address => bool) public isVault;

    /// @dev The list of all the vaults created by the factory.
    address[] public vaultList;

    /// @dev The perspective contract that is used to verify the strategies.
    IPerspective internal perspective;

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param _owner The owner of the factory contract.
    /// @param _evc The address of the EVC contract.
    /// @param _permit2 The address of the Permit2 contract.
    /// @param _perspective The address of the supported perspective contract.
    constructor(address _owner, address _evc, address _permit2, address _perspective) Ownable(_owner) EVCUtil(_evc) {
        if (_perspective == address(0)) revert ErrorsLib.ZeroAddress();

        permit2Address = _permit2;
        perspective = IPerspective(_perspective);
    }

    /* EXTERNAL */

    /// @inheritdoc IAmpleEarnFactory
    function supportedPerspective() external view returns (address) {
        return address(perspective);
    }

    /// @inheritdoc IAmpleEarnFactory
    function getVaultListLength() external view returns (uint256) {
        return vaultList.length;
    }

    /// @inheritdoc IAmpleEarnFactory
    function getVaultListSlice(uint256 start, uint256 end) external view returns (address[] memory list) {
        if (end == type(uint256).max) end = vaultList.length;
        if (end < start || end > vaultList.length) revert ErrorsLib.BadQuery();

        list = new address[](end - start);
        for (uint256 i; i < end - start; ++i) {
            list[i] = vaultList[start + i];
        }
    }

    /// @inheritdoc IAmpleEarnFactory
    function isStrategyAllowed(address id) external view returns (bool) {
        return perspective.isVerified(id) || isVault[id];
    }

    /// @inheritdoc IAmpleEarnFactory
    function setPerspective(address _perspective) public onlyEVCAccountOwner onlyOwner {
        if (_perspective == address(0)) revert ErrorsLib.ZeroAddress();

        perspective = IPerspective(_perspective);

        emit EventsLib.SetPerspective(_perspective);
    }

    /// @inheritdoc IAmpleEarnFactory
    function createAmpleEarn(
        address initialOwner,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol,
        uint96 protocolFee,
        address protocolFeeRecipient,
        bytes32 salt
    ) external onlyOwner returns (IAmpleEarn ampleEarn) {
        ampleEarn = IAmpleEarn(
            address(
                new AmpleEarn{salt: salt}(
                    initialOwner,
                    address(evc),
                    permit2Address,
                    initialTimelock,
                    asset,
                    name,
                    symbol,
                    protocolFee,
                    protocolFeeRecipient
                )
            )
        );

        isVault[address(ampleEarn)] = true;

        vaultList.push(address(ampleEarn));

        emit AmpleEventsLib.CreateAmpleEarn({
            ampleEarn: address(ampleEarn),
            caller: _msgSender(),
            initialOwner: initialOwner,
            initialTimelock: initialTimelock,
            asset: asset,
            name: name,
            symbol: symbol,
            protocolFee: protocolFee,
            protocolFeeRecipient: protocolFeeRecipient,
            salt: salt
        });
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view virtual override(EVCUtil, Context) returns (address) {
        return EVCUtil._msgSender();
    }
}
