// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "./ERC721.sol";

contract LouisERC721 is ERC721 {
    constructor() ERC721("LouisNFT", "LOUIS_NFT") {}

    function mint(uint256 tokenId) public payable {
        _mint(msg.sender, tokenId);
    }
}
