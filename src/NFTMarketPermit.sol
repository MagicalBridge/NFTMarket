// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract NFTMarketPermit is EIP712 {
    using ECDSA for bytes32;

    // 定义 ERC20 代币和 ERC721 NFT 合约的接口
    IERC20 public immutable tokenContract;
    IERC721 public immutable nftContract;

    // 列出 NFT 的结构体，包含卖家的地址和价格
    struct Listing {
        address seller;
        uint256 price;
    }

    // tokenId 到 Listing 结构体的映射，用于存储所有上架的 NFT
    mapping(uint256 => Listing) public listings;

    // 事件：当 NFT 被上架时触发
    event NFTListed(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price
    );
    // 事件：当 NFT 被售出时触发
    event NFTSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("PermitBuy(uint256 tokenId,uint256 price,uint256 deadline)");

    // 构造函数，初始化合约时设置 ERC20 代币合约和 ERC721 NFT 合约的地址
    constructor(
        address _tokenAddress,
        address _nftAddress
    ) EIP712("NFTMarketPermit", "1") {
        require(
            _tokenAddress != address(0),
            "Token contract address cannot be zero."
        );
        require(
            _nftAddress != address(0),
            "NFT contract address cannot be zero."
        );
        tokenContract = IERC20(_tokenAddress);
        nftContract = IERC721(_nftAddress);
    }

    // 上架函数，允许 NFT 持有者将 NFT 上架并设置价格
    function list(uint256 _tokenId, uint256 _price) external {
        // 确保调用者是 NFT 的持有者
        require(
            nftContract.ownerOf(_tokenId) == msg.sender,
            "ERC721: transfer of token that is not own"
        );
        // 确保市场合约被授权转移该 NFT
        require(
            nftContract.getApproved(_tokenId) == address(this),
            "ERC721: transfer caller is not owner nor approved"
        );

        // 将 NFT 信息添加到 listings 映射中
        listings[_tokenId] = Listing(msg.sender, _price);

        // 触发 NFTListed 事件
        emit NFTListed(_tokenId, msg.sender, _price);
    }

    // 基于EIP712标准设计购买流程，项目方为白名单用户生成签名，用户可以传递签名信息来购买NFT
    function permitBuyNFT(
        uint256 _tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata _permit
    ) external {
        Listing memory listing = listings[_tokenId];
        require(listing.seller != address(0), "NFT not listed for sale");

        // 验证买家的签名
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, _tokenId, listing.price, deadline)
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(v, r, s);
        require(signer == msg.sender, "Invalid signature");
        require(block.timestamp <= deadline, "Permit expired");

        // 删除列表并发出事件
        delete listings[_tokenId];

        // 使用 ERC2612 标准转移代币
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = abi.decode(
            _permit,
            (uint8, bytes32, bytes32)
        );
        IERC20Permit(address(tokenContract)).permit(
            msg.sender,
            address(this),
            listing.price,
            deadline,
            permitV,
            permitR,
            permitS
        );

        // 转移代币和 NFT
        require(
            tokenContract.transferFrom(
                msg.sender,
                listing.seller,
                listing.price
            ),
            "Token transfer failed"
        );
        nftContract.safeTransferFrom(listing.seller, msg.sender, _tokenId);

        emit NFTSold(_tokenId, listing.seller, msg.sender, listing.price);
    }
}
