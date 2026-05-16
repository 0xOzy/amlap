// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IAmpleEarn} from "./IAmpleEarn.sol";

/// @title IAmpleEarnFactory
/// @author Ample Money. Forked with gratitude from Euler Labs.
/// @custom:contact security@euler.xyz
/// @custom:contact security@ample.money
/// @notice Interface of AmpleEarn's factory.
/// @dev This is an exact copy of IEulerEarnFactory without the createEulerEarn function.
interface IAmpleEarnFactory {
    /// @notice The address of the Permit2 contract.
    function permit2Address() external view returns (address);

    /// @notice The address of the supported perspective contract.
    function supportedPerspective() external view returns (address);

    /// @notice Whether a vault was created with the factory.
    function isVault(address target) external view returns (bool);

    /// @notice Fetch the length of the deployed proxies list
    /// @return The length of the proxy list array
    function getVaultListLength() external view returns (uint256);

    /// @notice Get a slice of the deployed proxies array
    /// @param start Start index of the slice
    /// @param end End index of the slice
    /// @return list An array containing the slice of the proxy list
    function getVaultListSlice(uint256 start, uint256 end) external view returns (address[] memory list);

    /// @notice Sets the perspective contract.
    /// @param _perspective The address of the new perspective contract.
    function setPerspective(address _perspective) external;

    /// @notice Whether a strategy is allowed to be used by the Earn vault.
    /// @dev Warning: Only allow trusted, correctly implemented ERC4626 strategies to be used by the Earn vault.
    /// @dev Warning: Allowed strategies must not be prone to the first-depositor attack.
    /// @dev Warning: To prevent exchange rate manipulation, it is recommended that the allowed strategies are not empty or have sufficient protection.
    function isStrategyAllowed(address id) external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EXTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Creates a new AmpleEarn vault.
    /// @param initialOwner The owner of the vault.
    /// @param initialTimelock The initial timelock of the vault.
    /// @param asset The address of the underlying asset.
    /// @param name The name of the vault.
    /// @param symbol The symbol of the vault.
    /// @param protocolFee The protocol fee.
    /// @param protocolFeeRecipient The protocol fee recipient.
    /// @param salt The salt to use for the AmpleEarn vault's CREATE2 address.
    function createAmpleEarn(
        address initialOwner,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol,
        uint96 protocolFee,
        address protocolFeeRecipient,
        bytes32 salt
    ) external returns (IAmpleEarn ampleEarn);
}
