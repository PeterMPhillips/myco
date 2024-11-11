import hre from "hardhat";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group"
import { generateProof } from "@semaphore-protocol/proof";
import { BaseContract, ContractTransactionReceipt, EventLog, Result, ZeroAddress, ZeroHash, parseEther } from "ethers";
import { Myco__factory } from "../typechain-types";
import { packInitCode, packUserOp } from "./erc4337";

const SALT = '0x0000000000000000000000000000000000000000000000000000000000000001'
const PERIOD = 1000;
const QUORUM = 500000000000000000n;
const APPROVAL = 500000000000000001n;

async function getEventArgs(receipt: ContractTransactionReceipt, eventName: string, contract?: BaseContract): Promise<Result | undefined>  {
  const contractAddress = await contract?.getAddress()
  const events = receipt?.logs
    .map(log => {
      if (contract && log.address === contractAddress) {
        const fragment = log.topics.length ? contract.interface.getEvent(log.topics[0]): null;
        if (fragment) {
            return new EventLog(log, contract.interface, fragment)
        } else {
            return log;
        }
      }
      return log;
    })
    .filter(log => 'fragment' in log)
    .map(log => log as EventLog)
  
  const event = events.find(log => log.fragment.name === eventName);
  return event?.args
}

describe("Myco", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContractsFixture() {
    // Contracts are deployed using the first signer/account by default
    const [signer] = await hre.ethers.getSigners()
    const identity = new Identity()

    const SemaphoreVerifier = await hre.ethers.getContractFactory("SemaphoreVerifier");
    const verifier = await SemaphoreVerifier.deploy();

    const PoseidonT3 = await hre.ethers.getContractFactory("PoseidonT3");
    const poseidon = await PoseidonT3.deploy();

    const Semaphore = await hre.ethers.getContractFactory("Semaphore", {
        signer,
        libraries: {
            PoseidonT3: await poseidon.getAddress()
        }
    });
    const semaphore = await Semaphore.deploy(await verifier.getAddress());

    const EntryPoint = await hre.ethers.getContractFactory("EntryPoint");
    const entryPoint = await EntryPoint.deploy();

    const MycoFactory = await hre.ethers.getContractFactory("MycoFactory", signer);
    const mycoFactory = await MycoFactory.deploy(await entryPoint.getAddress(), await semaphore.getAddress());

    const mycoAddress = await mycoFactory.calculateAddress(ZeroHash, [identity.commitment]);
    await mycoFactory.deploy(ZeroHash, PERIOD, QUORUM, APPROVAL, [identity.commitment]);
    const myco = await hre.ethers.getContractAt("Myco", mycoAddress, signer);

    await signer.sendTransaction({ value: parseEther('1'), to: mycoAddress});

    return { signer, identity, semaphore, entryPoint, mycoFactory, myco};
  }

  describe("Proposal", function () {
    it("Should deploy with ERC4337", async function () {
      const { signer, identity, entryPoint, mycoFactory } = await loadFixture(deployContractsFixture);
      
      const group = new Group([identity.commitment]);
      const scope = 0;
      const message = 1 //yes
      const proof = await generateProof(identity, group, message, scope);
      
      const sender = await mycoFactory.calculateAddress(SALT, [identity.commitment]);
      const callData = Myco__factory.createInterface().encodeFunctionData('propose', ['0x', { target: ZeroAddress, value: 0, data: '0x'}, proof]);

      const packedUserOp = await packUserOp(
        signer.provider,
        entryPoint,
        sender,
        callData,
        '0x',
        400000, // cannot estimate call before contract is deployed
        3600000 // deployment costs are in the verification gas limit
      );
      packedUserOp.initCode = packInitCode(
        await mycoFactory.getAddress(),
        mycoFactory.interface.encodeFunctionData('deploy', [
          SALT,
          PERIOD,
          QUORUM,
          APPROVAL,
          [identity.commitment]
        ]),
      );

      // send funds ahead of time
      await signer.sendTransaction({ value: parseEther('1'), to: sender});

      const tx = await entryPoint.handleOps([packedUserOp], signer.address);
      const receipt = await tx.wait();

      const myco = await hre.ethers.getContractAt('Myco', sender);
      const args = await getEventArgs(receipt!, 'Settled', myco);
      expect(args).to.not.be.undefined;
      expect(args![1]).to.be.true;

      const balance = await signer.provider.getBalance(sender);
      expect(balance).to.lessThan(parseEther('1'));
    });
  });

  describe("Proposal", function () {
    it("Should propose and settle", async function () {
      const { signer, identity, entryPoint, myco } = await loadFixture(deployContractsFixture);
      const group = new Group([identity.commitment]);
      const scope = await myco.nonce();
      const message = 1 //yes
      const proof = await generateProof(identity, group, message, scope);
      
      const sender = await myco.getAddress();
      const callData = myco.interface.encodeFunctionData('propose', ['0x', { target: ZeroAddress, value: 0, data: '0x'}, proof]);

      const packedUserOp = await packUserOp(signer.provider, entryPoint, sender, callData);

      const tx = await entryPoint.handleOps([packedUserOp], signer.address);
      const receipt = await tx.wait();
      const args = await getEventArgs(receipt!, 'Settled', myco);
      expect(args).to.not.be.undefined;
      expect(args![1]).to.be.true;

      const balance = await signer.provider.getBalance(sender);
      expect(balance).to.lessThan(parseEther('1'));
    });

    it("Should fail to propose and settle", async function () {
      const { signer, entryPoint, myco } = await loadFixture(deployContractsFixture);
      
      // identity has not been added to contracts
      const identity = new Identity();

      const group = new Group([identity.commitment]);
      const scope = await myco.nonce();
      const message = 1 //yes
      const proof = await generateProof(identity, group, message, scope);
      
      const sender = await myco.getAddress();
      const callData = myco.interface.encodeFunctionData('propose', ['0x', { target: ZeroAddress, value: 0, data: '0x'}, proof]);

      const packedUserOp = await packUserOp(signer.provider, entryPoint, sender, callData, '0x', 450000, 350000);

      await expect(
        entryPoint.handleOps([packedUserOp], signer.address)
      ).to.be.revertedWithCustomError(entryPoint, 'FailedOpWithRevert');
    });

    it("Should add member and settle + second propose, vote and settle", async function () {
      const { signer, identity, entryPoint, myco } = await loadFixture(deployContractsFixture);
      const group = new Group([identity.commitment]);

      const newMember = new Identity();

      // propose new member
      let scope = await myco.nonce();
      let message = 1 //yes
      let proof = await generateProof(identity, group, message, scope);
      
      const sender = await myco.getAddress();
      let callData = myco.interface.encodeFunctionData('propose', [
        '0x', 
        { 
          target: sender, 
          value: 0,
          data: myco.interface.encodeFunctionData('addMember', [newMember.commitment])
        },
        proof
      ]);

      let packedUserOp = await packUserOp(signer.provider, entryPoint, sender, callData);
      
      let tx = await entryPoint.handleOps([packedUserOp], signer.address);
      let receipt = await tx.wait();
      const settleArgs = await getEventArgs(receipt!, 'Settled', myco);
      expect(settleArgs).to.not.be.undefined;
      expect(settleArgs![1]).to.be.true;
      const callArgs = await getEventArgs(receipt!, 'CallExecuted', myco);
      expect(callArgs).to.not.be.undefined;

      // member added, update off-chain group instance
      group.addMember(newMember.commitment);

      scope = await myco.nonce();
      message = 1 //yes
      proof = await generateProof(newMember, group, message, scope);

      callData = myco.interface.encodeFunctionData('propose', ['0x', { target: ZeroAddress, value: 0, data: '0x'}, proof]);
      packedUserOp = await packUserOp(signer.provider, entryPoint, sender, callData);
      tx = await entryPoint.handleOps([packedUserOp], signer.address);
      receipt = await tx.wait();
      const newProposalArgs = await getEventArgs(receipt!, 'NewProposal', myco);
      expect(newProposalArgs).to.not.be.undefined;

      // vote against
      message = 0 //no
      proof = await generateProof(identity, group, message, scope); // vote as original member

      callData = myco.interface.encodeFunctionData('vote', [proof]);
      packedUserOp = await packUserOp(signer.provider, entryPoint, sender, callData);
      tx = await entryPoint.handleOps([packedUserOp], signer.address);
      receipt = await tx.wait();
      const voteArgs = await getEventArgs(receipt!, 'Vote', myco);
      expect(voteArgs).to.not.be.undefined;
    });
  });
});
