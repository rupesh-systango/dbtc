//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library ECDSALib {
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        // Check the signature length
        require(signature.length == 65, "Invalid signature length");

        // Split the signature into components
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // EIP-2: Homestead
        if (v < 27) {
            v += 27;
        }

        // EIP-155: Replay attack protection
        if (v != 27 && v != 28) {
            revert("Invalid signature recovery id");
        }

        return ecrecover(hash, v, r, s);
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}