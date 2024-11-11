// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SemaphoreVoting, ISemaphore } from "./SemaphoreVoting.sol";
import { IAccount, PackedUserOperation } from "@account-abstraction/contracts/interfaces/IAccount.sol";
import { IEntryPoint } from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract Myco is SemaphoreVoting, IAccount {
    IEntryPoint public immutable entryPoint;
    
    constructor(
        address entryPoint_,
        address semaphore_,
        uint256[] memory identityCommitments_
    ) SemaphoreVoting(semaphore_) {
        entryPoint = IEntryPoint(entryPoint_);
        semaphore.addMembers(groupId, identityCommitments_);
        totalMembers += identityCommitments_.length;
    }

    // use initialize to set values via factory and support deterministic addresses
    function initialize(uint256 period_, uint256 quorum_, uint256 approval_) public initializer {
        _initialize(period_, quorum_, approval_);
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32, // hash not needed since we aren't verifying signature
        uint256 missingAccountFunds
    ) external authorized returns (uint256 validationData) {
        // validate data. support propose, vote, settle methods
        bytes4 sig = bytes4(userOp.callData[:4]);
        if (sig == this.vote.selector) {
            ISemaphore.SemaphoreProof memory proof = abi.decode(userOp.callData[4:], (ISemaphore.SemaphoreProof));
            validationData = semaphore.verifyProof(groupId, proof) ? 0 : 1;
        } else if (sig == this.propose.selector) {
            (, , ISemaphore.SemaphoreProof memory proof) = abi.decode(userOp.callData[4:], (bytes, Call, ISemaphore.SemaphoreProof));
            validationData = semaphore.verifyProof(groupId, proof) ? 0 : 1;
        } else if (sig == this.settle.selector) {
            uint256 id = abi.decode(userOp.callData[4:], (uint256));
            validationData = _verifySettle(id) ? 0 : 1;
        } else {
            validationData = 1;
        }

        if (missingAccountFunds != 0) {
            _execute(msg.sender, missingAccountFunds, "");
            //ignore failure (its EntryPoint's job to verify, not account.)
        }
    }

    function _isAuthorized(address account) internal view override returns (bool) {
        // only entry point is authorized
        return account == address(entryPoint);
    }

    function _isAdmin(address account) internal view override returns (bool) {
        // self administer membership through voting
        return account == address(this);
    }

    function _verifyCall(address, Call calldata) internal pure override returns (bool) {
        // all calls are available to group
        return true;
    }

    function _verifySettle(uint256 id) internal view returns (bool) {
        // verify the period has passed or sufficient approval to settle early
        Proposal memory proposal = proposals[id];
        // todo: check for validCall?
        if (uint256(proposal.start) + period < block.timestamp){
            if (uint256(proposal.yes) + 1e18 / totalMembers >= approval) {
                return true;
            }
            return false;
        }
        return true;
    }
}