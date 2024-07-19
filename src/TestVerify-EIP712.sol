// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestVerifyEIP712 is EIP712, Ownable {
    using ECDSA for bytes32;

    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address buyer,uint256 deadline)");

    constructor() EIP712("NFTMarketPermit", "1") Ownable(msg.sender) {}

    function verifyPermitSignature(bytes calldata signature, address buyer, uint256 deadline)
        public
        view
        returns (address)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, buyer, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        return signer;
        // return signer == owner(); // 检查签名者是否为合约所有者（管理员）
    }
}
