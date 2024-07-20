// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VerifyEIP712 is EIP712, Ownable {
    string private constant SIGNING_DOMAIN = "NFTMarketPermit";
    string private constant SIGNATURE_VERSION = "1";

    bytes32 constant PERMIT_BUY_NFT_WL_TYPEHASH = keccak256("PermitBuyNFTWL(address buyer,uint256 deadline)");

    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) Ownable(msg.sender) {}

    function verifyPermitSignature(bytes calldata signature, address buyer, uint256 deadline)
        public
        view
        returns (address)
    {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(PERMIT_BUY_NFT_WL_TYPEHASH, buyer, deadline)));

        address recoveredSigner = ECDSA.recover(digest, signature);
        require(recoveredSigner == owner(), "signer should be owner");
        require(buyer == msg.sender, "buyer should be msg.sender");
        require(block.timestamp <= deadline, "deadline should not be passed");

        return recoveredSigner;
    }
}
