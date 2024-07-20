// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarketPermit} from "../src/NFTMarketPermit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Permit is ERC20, ERC20Permit {
    constructor() ERC20("TestPermitToken", "TPTK") ERC20Permit("TestPermitToken") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC721 is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract NFTMarketPermitTest is Test {
    NFTMarketPermit public market;
    MockERC20Permit public token;
    MockERC721 public nft;

    address public owner;
    uint256 public ownerPK;
    address public seller;
    uint256 public sellerPK;
    address public buyer;
    uint256 public buyerPK;

    uint256 public tokenId;
    uint256 public nftPrice;
    uint256 public deadline;

    // EIP-2612 规范规定的类型哈希值
    bytes32 public eip2612PermitTypeHash =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // 事件：当 NFT 被上架时触发
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    // 事件：当 NFT 被购买时触发
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    // 事件：当 NFT 被取消时触发
    event NFTcancled(uint256 indexed tokenId, address indexed owner);

    function setUp() public {
        (owner, ownerPK) = makeAddrAndKey("owner");
        (seller, sellerPK) = makeAddrAndKey("seller");
        (buyer, buyerPK) = makeAddrAndKey("buyer");

        token = new MockERC20Permit();
        nft = new MockERC721();

        vm.prank(owner); // prank 只会影响下一笔交易 NFTMarketPermit 合约的 msg.sender 就被设置成为了 owner
        market = new NFTMarketPermit(address(token), address(nft));

        deadline = block.timestamp + 1 days;

        // 给seller用户mint一个NFT,设置的tokenId为1
        nft.mint(seller, 1);
        tokenId = 1;

        // 设置NFT价格
        nftPrice = 10 ether;
        // 给买家一些代币
        token.mint(buyer, 10000 ether);
    }

    // 可以成功上架NFT
    function testNFTOwnerCanList() public {
        // 切换为seller用户
        vm.startPrank(seller);

        // 授权market合约托管用户的NFT
        nft.approve(address(market), tokenId);

        vm.expectEmit();
        emit NFTListed(tokenId, seller, nftPrice); // 期望的事件
        market.list(tokenId, nftPrice);
        // 停止mock用户
        vm.stopPrank();

        // 测试上架信息
        (address sellPerson, uint256 price) = market.listings(tokenId);
        assertEq(sellPerson, seller, "Seller should be the user");
        assertEq(price, nftPrice, "Listing price should match");
    }

    // 购买NFT
    function testNFTOwnerCancelList() public {
        // 切换为这个mock用户
        vm.startPrank(buyer);

        vm.expectRevert("Not the owner");
        market.cancelList(tokenId);

        vm.stopPrank();

        // 切换为这个mock用户
        vm.startPrank(seller);

        // 授权market托管用户的NFT
        nft.approve(address(market), tokenId);

        // List the NFT
        market.list(tokenId, nftPrice);

        vm.expectEmit();
        emit NFTListed(tokenId, seller, nftPrice); // 期望的事件
        market.list(tokenId, nftPrice);

        // 测试上架信息
        (address sellPerson, uint256 price) = market.listings(tokenId);
        assertEq(sellPerson, seller, "Seller should be the user");
        assertEq(price, nftPrice, "Listing price should match");

        // 测试下架
        vm.expectEmit();
        emit NFTcancled(tokenId, seller); // 期望的事件
        market.cancelList(tokenId);

        (sellPerson, price) = market.listings(tokenId);

        console.log(sellPerson);
        assertEq(sellPerson, address(0), "Seller should be address(0)");
        assertEq(price, 0, "Listing price should be 0");
        vm.stopPrank();
    }

    // function testPermitBuyNFT() public {
    //     (address sellerUser,) = makeAddrAndKey("seller");
    //     (address buyerUser,) = makeAddrAndKey("buyer");

    //     // 给用户mint一个NFT
    //     uint256 tokenId = nft.mint(sellerUser);
    //     uint256 deadline = block.timestamp + 1 hours;

    //     // 切换为这个mock用户
    //     vm.startPrank(sellerUser);

    //     // 授权market托管用户的NFT
    //     nft.approve(address(market), tokenId);

    //     // List the NFT
    //     uint256 listingPrice = 10 * (10 ** 18);
    //     market.list(tokenId, listingPrice);
    //     vm.stopPrank();
    // }
}
