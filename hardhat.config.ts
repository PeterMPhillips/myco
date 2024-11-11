import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "hardhat-dependency-compiler";

const config: HardhatUserConfig = {
  solidity: "0.8.23",
  dependencyCompiler: {
    paths: [
      "@account-abstraction/contracts/core/EntryPoint.sol",
      "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol",
      "@semaphore-protocol/contracts/Semaphore.sol",
      "poseidon-solidity/PoseidonT3.sol"
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    }
  }
};

export default config;