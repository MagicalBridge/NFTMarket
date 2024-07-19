// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketPermit is EIP712, Ownable {
    using ECDSA for bytes32;

    IERC20 public immutable tokenContract;
    IERC20Permit public immutable tokenContractPermit;
    IERC721 public immutable nftContract;

    struct Listing {
        address seller;
        uint256 price;
    }

    struct PermitData {
        uint256 tokenId;
        uint256 deadline;
    }

    mapping(uint256 => Listing) public listings;

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event SignVerify(address indexed signer, address indexed owner, address indexed buyer);

    // bytes32 private constant PERMIT_BUY_NFT_TYPEHASH = "PermitBuyNFTWL(address owner, address buyer)";

    constructor(address _tokenAddress, address _nftAddress) EIP712("NFTMarketPermit", "1") Ownable(msg.sender) {
        require(_tokenAddress != address(0), "Token contract address cannot be zero.");
        require(_nftAddress != address(0), "NFT contract address cannot be zero.");
        tokenContract = IERC20(_tokenAddress);
        tokenContractPermit = IERC20Permit(_tokenAddress);
        nftContract = IERC721(_nftAddress);
    }

    function list(uint256 _tokenId, uint256 _price) external {
        require(nftContract.ownerOf(_tokenId) == msg.sender, "Not the owner");
        require(nftContract.getApproved(_tokenId) == address(this), "Not approved");

        listings[_tokenId] = Listing(msg.sender, _price);
        emit NFTListed(_tokenId, msg.sender, _price);
    }

    function permitBuyNFT(PermitData calldata permitData, bytes calldata _permitWL, bytes calldata _permit) external {
        // 通过tokenId获取到 NFT的 seller 和 售卖价格
        Listing memory listing = listings[permitData.tokenId];
        require(listing.seller != address(0), "NFT not listed");

        verifyPermitSignature(permitData, _permitWL, msg.sender);
        executePermitAndTransfer(permitData, listing, _permit);

        delete listings[permitData.tokenId];
        emit NFTSold(permitData.tokenId, listing.seller, msg.sender, listing.price);
    }

    function verifyPermitSignature(PermitData calldata permitData, bytes calldata _permitWL, address buyer)
        public
        view
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(keccak256("PermitBuyNFTWL(address owner, address buyer)"), owner(), buyer))
        );

        address recoveredSigner = ECDSA.recover(digest, _permitWL);

        require(recoveredSigner == owner(), "signer should be owner");
        require(buyer == msg.sender, "buyer should be msg.sender");
        require(block.timestamp <= permitData.deadline, "Permit expired");
    }

    function executePermitAndTransfer(PermitData calldata permitData, Listing memory listing, bytes calldata _permit)
        public
    {
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = abi.decode(_permit, (uint8, bytes32, bytes32));
        tokenContractPermit.permit(
            msg.sender, address(this), listing.price, permitData.deadline, permitV, permitR, permitS
        );

        require(tokenContract.transferFrom(msg.sender, listing.seller, listing.price), "Transfer failed");
        nftContract.safeTransferFrom(listing.seller, msg.sender, permitData.tokenId);
    }
}
