// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "./IRoyaltyRegistry.sol";
import "./specs/INiftyGateway.sol";
import "./specs/IFoundation.sol";
import "./specs/IDigitalax.sol";
import "./specs/IArtBlocks.sol";

/**
 * @dev Registry to lookup royalty configurations
 */
contract RoyaltyRegistry is ERC165, OwnableUpgradeable, IRoyaltyRegistry {
    using AddressUpgradeable for address;

    // Override addresses
    mapping (address => address) private _overrides;

    function initialize() public initializer {
        __Ownable_init_unchained();
    }

    function importNiftyAddresses(address[] memory _legacyNiftyAddresses) public {
        //Ensure user is a valid sender from Nifty Registry.
        require(INiftyRegistry(0x6e53130dDfF21E3BC963Ee902005223b9A202106).isValidNiftySender(msg.sender), "NiftyLegacyRegistry: invalid msg.sender");
        for (uint256 i = 0; i < _legacyNiftyAddresses.length; i++) {
            //Ensure the token address is a legacy address
            require(INiftyLegacyRegistry(0x44447A4E82ed33E42Ed53Fe0d2254B5D42b13fD0).isLegacyAddress(_legacyNiftyAddresses[i]), "Address is not a legacy address.");
            //Add this legacy registry address as the override for this token address
            _overrides[_legacyNiftyAddresses[i]] = 0x44447A4E82ed33E42Ed53Fe0d2254B5D42b13fD0;
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IRoyaltyRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IRegistry-getRoyaltyLookupAddress}.
     */
    function getRoyaltyLookupAddress(address tokenAddress) external view override returns(address) {
        address override_ = _overrides[tokenAddress];
        if (override_ != address(0)) return override_;
        return tokenAddress;
    }

    /**
     * @dev See {IRegistry-setRoyaltyLookupAddress}.
     */
    function setRoyaltyLookupAddress(address tokenAddress, address royaltyLookupAddress) public override {
        require(tokenAddress.isContract() && (royaltyLookupAddress.isContract() || royaltyLookupAddress == address(0)), "Invalid input");
        require(overrideAllowed(tokenAddress), "Permission denied");
        _overrides[tokenAddress] = royaltyLookupAddress;
        emit RoyaltyOverride(_msgSender(), tokenAddress, royaltyLookupAddress);
    }

    /**
     * @dev See {IRegistry-overrideAllowed}.
     */
    function overrideAllowed(address tokenAddress) public view override returns(bool) {
        if (owner() == _msgSender()) return true;

        if (ERC165Checker.supportsInterface(tokenAddress, type(IAdminControl).interfaceId)
            && IAdminControl(tokenAddress).isAdmin(_msgSender())) {
            return true;
        }

        try OwnableUpgradeable(tokenAddress).owner() returns (address owner) {
            if (owner == _msgSender()) return true;

            if (owner.isContract()) {
              try OwnableUpgradeable(owner).owner() returns (address passThroughOwner) {
                  if (passThroughOwner == _msgSender()) return true;
              } catch {}
            }
        } catch {}

        try IAccessControlUpgradeable(tokenAddress).hasRole(0x00, _msgSender()) returns (bool hasRole) {
            if (hasRole) return true;
        } catch {}

        // Nifty Gateway overrides
        try INiftyBuilderInstance(tokenAddress).niftyRegistryContract() returns (address niftyRegistry) {
            try INiftyRegistry(niftyRegistry).isValidNiftySender(_msgSender()) returns (bool valid) {
                return valid;
            } catch {}
        } catch {}

        // OpenSea overrides
        // Tokens already support Ownable

        // Foundation overrides
        try IFoundationTreasuryNode(tokenAddress).getFoundationTreasury() returns (address payable foundationTreasury) {
            try IFoundationTreasury(foundationTreasury).isAdmin(_msgSender()) returns (bool isAdmin) {
                return isAdmin;
            } catch {}
        } catch {}

        // DIGITALAX overrides
        try IDigitalax(tokenAddress).accessControls() returns (address externalAccessControls){
            try IDigitalaxAccessControls(externalAccessControls).hasAdminRole(_msgSender()) returns (bool hasRole) {
                if (hasRole) return true;
            } catch {}
        } catch {}

        // Art Blocks overrides
        try IArtBlocks(tokenAddress).admin() returns (address admin) {
            if (admin == _msgSender()) return true;
        } catch {}

        // Superrare overrides
        // Tokens and registry already support Ownable

        // Rarible overrides
        // Tokens already support Ownable

        return false;
    }

}
