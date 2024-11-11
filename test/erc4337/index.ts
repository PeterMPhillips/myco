import { Provider, ZeroHash, concat, toBeHex, zeroPadValue } from "ethers";
import { EntryPoint, IAccount__factory } from "../../typechain-types";
import { PackedUserOperationStruct } from "../../typechain-types/@account-abstraction/contracts/core/EntryPoint";

export async function packUserOp(
    provider: Provider,
    entryPoint: EntryPoint,
    sender: string,
    callData: string,
    initCode?: string,
    callGasLimit?: number | bigint,
    verificationGasLimit?: number | bigint,
  ) {
    if (!callGasLimit) {
      callGasLimit = await provider.estimateGas({
        from: await entryPoint.getAddress(),
        to: sender,
        data: callData
      });
    }
  
    const accountGasLimits = packAccountGasLimits(verificationGasLimit || 350000, callGasLimit);
    const gasFees = packAccountGasLimits(1e9, 1);
  
    const packedUserOp: PackedUserOperationStruct = {
      sender,
      nonce: await entryPoint.getNonce(sender, 0),
      initCode: initCode || '0x',
      callData,
      accountGasLimits,
      gasFees,
      preVerificationGas: 21000,
      paymasterAndData: '0x',
      signature: '0x', // we aren't verifying signature but instead verifying semaphore proofs
    };
  
    if (!verificationGasLimit) {
      verificationGasLimit = await provider.estimateGas({
        from: await entryPoint.getAddress(),
        to: sender,
        data: IAccount__factory.createInterface().encodeFunctionData('validateUserOp', [packedUserOp, ZeroHash, 1])
      }) + 50000n; // pad gas
      packedUserOp.accountGasLimits = packAccountGasLimits(verificationGasLimit, callGasLimit);
    }
    return packedUserOp;
}
  
export function packAccountGasLimits (verificationGasLimit: number | bigint, callGasLimit: number | bigint): string {
    return concat([
        zeroPadValue(toBeHex(verificationGasLimit), 16),
        zeroPadValue(toBeHex(callGasLimit), 16)
    ])
}
  
export function packInitCode (factory: string, factoryData: string): string {
    return concat([
        factory,
        factoryData
    ])
}
  
export function packPaymasterData (paymaster: string, paymasterVerificationGasLimit: number | bigint, postOpGasLimit: number | bigint, paymasterData: string): string {
    return concat([
        paymaster,
        zeroPadValue(toBeHex(paymasterVerificationGasLimit), 16),
        zeroPadValue(toBeHex(postOpGasLimit), 16), paymasterData
    ])
}