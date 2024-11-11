// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISemaphore } from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

abstract contract SemaphoreGroup {
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;
    
    uint256 public totalMembers; // Member count
    
    constructor(address semaphore_) {
        semaphore = ISemaphore(semaphore_);
        groupId = semaphore.createGroup();
    }

    receive() external payable virtual {}

    function addMember(uint256 identityCommitment) external admin {
        semaphore.addMember(groupId, identityCommitment);
        totalMembers++;
    }

    function addMembers(uint256[] calldata identityCommitments) external admin {
        semaphore.addMembers(groupId, identityCommitments);
        totalMembers += identityCommitments.length;
    }

    function removeMember(uint256 identityCommitment, uint256[] calldata merkleProofSiblings) external admin {
        semaphore.removeMember(groupId, identityCommitment, merkleProofSiblings);
        totalMembers--;
    }

    function updateMember(
        uint256 oldIdentityCommitment,
        uint256 newIdentityCommitment,
        uint256[] calldata merkleProofSiblings
    ) external admin {
        semaphore.updateMember(groupId, oldIdentityCommitment, newIdentityCommitment, merkleProofSiblings);
    }

    function _execute(address target, uint256 value, bytes memory data) internal returns (bool success) {
        (success, ) = target.call{value: value}(data);
        // todo: should we return response data?
    }

    function _isAdmin(address account) internal view virtual returns (bool);

    modifier admin() {
        if (!_isAdmin(msg.sender)) revert SemaphoreGroup__NotAdmin();
        _;
    }

    error SemaphoreGroup__NotAdmin();
}