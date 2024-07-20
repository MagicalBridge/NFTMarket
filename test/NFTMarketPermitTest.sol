// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarketPermit} from "../src/NFTMarketPermit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Permit is ERC20, ERC20Permit {
    constructor() ERC20("TestPermitToken", "TPTK") ERC20Permit("TestPermitToken") {
        _mint(msg.sender, 100 * 10 ** 18);
    }
}

contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;

    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _safeMint(to, tokenId);
        _tokenIdCounter++;
        return tokenId;
    }
}

contract NFTMarketPermitTest is Test {
    NFTMarketPermit public market;
    MockERC20Permit public token;
    MockERC721 public nft;

    // 事件：当 NFT 被上架时触发
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    // 事件：当 NFT 被购买时触发
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    // 事件：当 NFT 被取消时触发
    event NFTcancled(uint256 indexed tokenId, address indexed owner);

    function setUp() public {
        token = new MockERC20Permit();
        nft = new MockERC721();
        market = new NFTMarketPermit(address(token), address(nft));
    }

    // 可以成功上架NFT
    function testNFTOwnerCanList() public {
        (address sellerUser,) = makeAddrAndKey("seller");

        // 给用户mint一个NFT
        uint256 tokenId = nft.mint(sellerUser);

        // 切换为这个mock用户
        vm.startPrank(sellerUser);

        // 授权market托管用户的NFT
        nft.approve(address(market), tokenId);

        // List the NFT
        uint256 listingPrice = 100 * (10 ** 18);
        vm.expectEmit();
        emit NFTListed(tokenId, sellerUser, listingPrice); // 期望的事件
        market.list(tokenId, listingPrice);
        // 停止mock用户
        vm.stopPrank();

        // 测试上架信息
        (address sellPerson, uint256 price) = market.listings(tokenId);
        assertEq(sellPerson, sellerUser, "Seller should be the user");
        assertEq(price, listingPrice, "Listing price should match");
    }

    // 购买NFT
    function testNFTOwnerCancelList() public {
        (address sellerUser,) = makeAddrAndKey("seller");
        (address buyerUser,) = makeAddrAndKey("buyer");

        // 给用户mint一个NFT
        uint256 tokenId = nft.mint(sellerUser);

        // 切换为这个mock用户
        vm.startPrank(buyerUser);

        vm.expectRevert("Not the owner");
        market.cancelList(tokenId);

        vm.stopPrank();

        // 切换为这个mock用户
        vm.startPrank(sellerUser);

        // 授权market托管用户的NFT
        nft.approve(address(market), tokenId);

        // List the NFT
        uint256 listingPrice = 100 * (10 ** 18);
        market.list(tokenId, listingPrice);

        vm.expectEmit();
        emit NFTListed(tokenId, sellerUser, listingPrice); // 期望的事件
        market.list(tokenId, listingPrice);

        // 测试上架信息
        (address sellPerson, uint256 price) = market.listings(tokenId);
        assertEq(sellPerson, sellerUser, "Seller should be the user");
        assertEq(price, listingPrice, "Listing price should match");

        // 测试下架
        vm.expectEmit();
        emit NFTcancled(tokenId, sellerUser); // 期望的事件
        market.cancelList(tokenId);

        (sellPerson, price) = market.listings(tokenId);

        console.log(sellPerson);
        assertEq(sellPerson, address(0), "Seller should be address(0)");
        assertEq(price, 0, "Listing price should be 0");

        // 停止mock用户
        vm.stopPrank();
    }

    function testPermitBuyNFT() public {
        (address sellerUser,) = makeAddrAndKey("seller");
        (address buyerUser,) = makeAddrAndKey("buyer");

        // 给用户mint一个NFT
        uint256 tokenId = nft.mint(sellerUser);
        uint256 deadline = block.timestamp + 1 hours;

        // 切换为这个mock用户
        vm.startPrank(sellerUser);

        // 授权market托管用户的NFT
        nft.approve(address(market), tokenId);

        // List the NFT
        uint256 listingPrice = 100 * (10 ** 18);
        market.list(tokenId, listingPrice);
        vm.stopPrank();

        // Create PermitWL
        NFTMarketPermit.PermitWL memory permitWL = NFTMarketPermit.PermitWL({buyer: buyerUser, deadline: deadline});
    }
}
