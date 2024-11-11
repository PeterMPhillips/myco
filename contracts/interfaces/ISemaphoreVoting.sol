//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISemaphore } from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

interface ISemaphoreVoting {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }
    struct Proposal {
        uint64 start;
        uint64 yes;
        uint64 no;
        bool settled;
        bytes metadata;
        bytes call;
    }
    event NewProposal(uint256 indexed id, bytes metadata, Call call);
    event Vote(uint256 indexed id, uint256 indexed message);
    event Settled(uint256 indexed id, bool indexed passed);
    event CallExecuted(uint256 indexed id);
    event CallReverted(uint256 indexed id);
    error SemaphoreVoting__AlreadySettled();
    error SemaphoreVoting__VotingPeriodOver();
    error SemaphoreVoting__VotingPeriodNotOver();
    error SemaphoreVoting__OutOfScope();
    error SemaphoreVoting__InvalidVoteOption();
    error SemaphoreVoting__InvalidCall();
    error SemaphoreVoting__NotAuthorized();
    error SemaphoreVoting__Initialized();

    function nonce() external view returns (uint256);

    function period() external view returns (uint256);

    function quorum() external view returns (uint256);

    function approval() external view returns (uint256);

    function propose(bytes calldata metadata, Call calldata call, ISemaphore.SemaphoreProof calldata proof) external;

    function vote(ISemaphore.SemaphoreProof calldata proof) external;

    function settle(uint256 id) external;
}