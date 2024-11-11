// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SemaphoreGroup, ISemaphore } from "./SemaphoreGroup.sol";
import { ISemaphoreVoting } from "./interfaces/ISemaphoreVoting.sol";

abstract contract SemaphoreVoting is SemaphoreGroup, ISemaphoreVoting {
    mapping(uint256 => Proposal) public proposals;

    uint256 public nonce; // Proposal count
    uint256 public period; // The total time each vote is open for
    uint256 public quorum; // The minimum percentage of members that must vote for the vote to pass
    uint256 public approval; // The minimum percentage of total votes that must vote yes for the vote to pass

    bool private initialized;

    uint256 private constant HUNDRED_PERCENT = 1e18;
    uint256 private constant FIFTY_PERCENT = 5e17;

    constructor(address semaphore_) SemaphoreGroup(semaphore_) {}
    
    function propose(bytes calldata metadata, Call calldata call, ISemaphore.SemaphoreProof calldata proof) external authorized {
        semaphore.validateProof(groupId, proof);

        if (proof.scope != nonce) revert SemaphoreVoting__OutOfScope();
        uint256 id = nonce;
        nonce++;

        if (!_verifyCall(msg.sender, call)) revert SemaphoreVoting__InvalidCall();

        bool voteYes = proof.message == 1;

        // set proposal in mapping
        proposals[id] = Proposal(
            uint64(block.timestamp), //todo: safely cast this (not that i'm worried about it)
            voteYes ? 1 : 0,
            voteYes ? 0 : 1,
            false,
            metadata,
            abi.encode(call)
        );

        emit NewProposal(id, metadata, call);

        // if there is only one member, we can immediately settle
        if (totalMembers == 1) {
            _settle(id);
        }
    }

    function vote(ISemaphore.SemaphoreProof calldata proof) external authorized {
        semaphore.validateProof(groupId, proof);

        if (proof.scope >= nonce) revert SemaphoreVoting__OutOfScope();
        if (proof.message > 1) revert SemaphoreVoting__InvalidVoteOption();

        Proposal storage proposal = proposals[proof.scope];
        if (uint256(proposal.start) + period <= block.timestamp) revert SemaphoreVoting__VotingPeriodOver();

        if (proof.message == 0) {
            proposal.no++;
        } else {
            proposal.yes++;
        }
        emit Vote(proof.scope, proof.message);
    }

    // todo: make this callable by anyone?
    function settle(uint256 id) external authorized {
        _settle(id);
    }

    function updatePeriod(uint256 newPeriod) external admin {
        _updatePeriod(newPeriod);
    }

    function updateQuorum(uint256 newQuorum) external admin {
        _updateQuorum(newQuorum);
    }

    function updateApproval(uint256 newApproval) external admin {
        _updateApproval(newApproval);
    }

    function _settle(uint256 id) internal {
        Proposal storage proposal = proposals[id];
        if (proposal.settled) revert SemaphoreVoting__AlreadySettled();

        // get the total number of votes
        uint256 totalVotes = uint256(proposal.yes) + uint256(proposal.no);

        bool passed;
        if (totalVotes == totalMembers || uint256(proposal.start) + period <= block.timestamp) {
            // if everyone has voted or voting period is over
            if (
                totalVotes >= totalMembers * quorum / 1e18 &&
                uint256(proposal.yes) * 1e18 / totalVotes >= approval
            ) {
                // total is above quorum and majority voted yes, execute
                passed = true;
            }
        } else {
            // voting period not over
            if (uint256(proposal.yes) + 1e18 / totalMembers >= approval) {
                // if a valid call and majority has voted yes, execute even though the voting period is not over
                passed = true;
            } else {
                // do not settle if voting period is not over
                revert SemaphoreVoting__VotingPeriodNotOver();
            }
        }
        proposal.settled = true;
        emit Settled(id, passed);

        Call memory call = abi.decode(proposal.call, (Call));
        if (passed && call.target != address(0)) {
            bool success = _execute(
                call.target,
                call.value,
                call.data
            );
            // todo: determine how we want to handle failures in the context of proposal settlement (if we bubble reverts then broken calls will never settle)
            if (success) {
                emit CallExecuted(id);
            } else {
                emit CallReverted(id);
            }
        }
    }

    function _updatePeriod(uint256 newPeriod) internal {
        if (newPeriod == 0) revert SemaphoreVoting__InvalidPeriod();
        if (newPeriod > 30 days) revert SemaphoreVoting__InvalidPeriod();
        period = newPeriod;
    }

    function _updateQuorum(uint256 newQuorum) internal {
        if (newQuorum > HUNDRED_PERCENT) revert SemaphoreVoting__InvalidQuorum();
        if (newQuorum == 0) revert SemaphoreVoting__InvalidQuorum();
        quorum = newQuorum;
    }

    function _updateApproval(uint256 newApproval) internal {
        if (newApproval > HUNDRED_PERCENT) revert SemaphoreVoting__InvalidApproval();
        if (newApproval <= FIFTY_PERCENT) revert SemaphoreVoting__InvalidApproval();
        approval = newApproval;
    }

    function _initialize(uint256 period_, uint256 quorum_, uint256 approval_) internal initializer {
        _updatePeriod(period_);
        _updateQuorum(quorum_);
        _updateApproval(approval_);
    }

    // could support advance rules for what calls can be executed from proposals
    function _verifyCall(address account, Call calldata call) internal virtual returns (bool);

    function _isAuthorized(address account) internal view virtual returns (bool);

    modifier authorized() {
        if (!_isAuthorized(msg.sender)) revert SemaphoreVoting__NotAuthorized();
        _;
    }

    modifier initializer() {
        if (initialized) revert SemaphoreVoting__Initialized();
        _;
        initialized = true;
    }

    error SemaphoreVoting__InvalidPeriod();
    error SemaphoreVoting__InvalidQuorum();
    error SemaphoreVoting__InvalidApproval();
}
