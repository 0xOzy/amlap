// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {Ownable2Step, Ownable} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import {IAmplePerspective} from "./interfaces/IAmplePerspective.sol";

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

/// @title AmplePerspective
/// @author Ample Money
/// @custom:contact security@ample.money
/// @notice A minimal perspective contract for verifying allowed strategies in AmpleEarn vaults.
contract AmplePerspective is Ownable2Step, IAmplePerspective {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Enumerable set of vault addresses to their verification status.
    EnumerableSet.AddressSet private _verified;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the perspective with an owner.
    /// @param _owner The owner of the perspective contract.
    constructor(address _owner) Ownable(_owner) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EXTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmplePerspective
    function name() external pure returns (string memory) {
        return "Ample Earn Factory Perspective";
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ONLY OWNER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmplePerspective
    function verify(address vault) external onlyOwner {
        if (vault == address(0) || vault.code.length == 0 || vault == address(this)) {
            revert InvalidVault(vault);
        }

        if (!_verified.add(vault)) revert AlreadyVerified(vault);

        emit Verified(vault);
    }

    /// @inheritdoc IAmplePerspective
    function unverify(address vault) external onlyOwner {
        if (!_verified.remove(vault)) revert NotVerified(vault);

        emit Unverified(vault);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmplePerspective
    function isVerified(address vault) public view returns (bool) {
        return _verified.contains(vault);
    }

    /// @inheritdoc IAmplePerspective
    function verifiedLength() public view returns (uint256) {
        return _verified.length();
    }

    /// @inheritdoc IAmplePerspective
    function verifiedArray() public view returns (address[] memory) {
        return _verified.values();
    }
}
