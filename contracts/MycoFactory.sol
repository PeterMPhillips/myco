// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Myco } from "./Myco.sol";

contract MycoFactory {
    address public immutable entryPoint;
    address public immutable semaphore;

    constructor(address entryPoint_, address semaphore_) {
        entryPoint = entryPoint_;
        semaphore = semaphore_;
    }

    function deploy(
        bytes32 salt,
        uint256 period,
        uint256 quorum,
        uint256 approval,
        uint256[] calldata identityCommitments
    ) public payable returns (address){
        Myco group = new Myco{salt: salt}(entryPoint, semaphore, identityCommitments);
        group.initialize(period, quorum, approval);
        if (msg.value > 0) {
            (bool success, ) = address(group).call{value: msg.value}("");
            if (!success) {
                revert Factory__TransferFailed();
            }
        }
        return address(group);
    }

    function calculateAddress(bytes32 salt, uint256[] calldata identityCommitments)
        public
        view
        returns (address)
    {
        bytes memory bytecode = abi.encodePacked(
            type(Myco).creationCode,
            abi.encode(entryPoint, semaphore, identityCommitments)
        );
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), salt, keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    error Factory__TransferFailed();
}