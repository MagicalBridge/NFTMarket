// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract DecodeEIP712 {
    function executePermitAndTransfer(bytes calldata signature) public pure returns (uint8, bytes32, bytes32) {
        require(signature.length >= 65, "Invalid permit data length");

        (uint8 v, bytes32 r, bytes32 s) = parseSignature(signature);

        return (v, r, s);
    }

    function parseSignature(bytes memory signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature 'v' value");
    }
}
