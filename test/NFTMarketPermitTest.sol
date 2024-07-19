// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarketPermit} from "../src/NFTMarketPermit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Permit is ERC20, ERC20Permit {
    constructor() ERC20("TestToken", "TTK") ERC20Permit("TestToken") {
        _mint(msg.sender, 1000000 * 10 ** 18);
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

    address public seller = address(1);
    address public buyer = address(2);

    // 事件：当 NFT 被上架时触发
    event NFTListed(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price
    );
    event NFTSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );

    function setUp() public {
        token = new MockERC20Permit();
        nft = new MockERC721();
        market = new NFTMarketPermit(address(token), address(nft));
    }

    // 测试构造函数
    function testContractAddresses() public view {
        assertEq(
            address(market.tokenContract()),
            address(token),
            "Token contract address mismatch"
        );
        assertEq(
            address(market.nftContract()),
            address(nft),
            "NFT contract address mismatch"
        );
    }

    // 可以成功上架NFT
    function testNFTOwnerCanList() public {
        address user = address(0x01);

        // 给用户mint一个NFT
        uint256 tokenId = nft.mint(user);

        // 切换为这个mock用户
        vm.startPrank(user);

        // 授权market托管用户的NFT
        nft.approve(address(market), tokenId);

        // List the NFT
        uint256 listingPrice = 100 * (10 ** 18);
        vm.expectEmit();
        emit NFTListed(tokenId, user, listingPrice); // 期望的事件
        market.list(tokenId, listingPrice);
        // 停止mock用户
        vm.stopPrank();

        // 测试上架信息
        (address sellPerson, uint256 price) = market.listings(tokenId);
        assertEq(sellPerson, user, "Seller should be the user");
        assertEq(price, listingPrice, "Listing price should match");
    }

    // 购买NFT
    function testPermitBuyNFT() public {
        uint256 price = 100 * 10 ** 18;
        uint256 tokenId = 1;
        uint256 deadline = block.timestamp + 1 hours;

        // 列出NFT
        vm.prank(seller);
        market.list(tokenId, price);

        // 创建PermitData
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            buyer,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    market.getDomainSeparator(),
                    keccak256(
                        abi.encode(
                            market.getPermitBuyNFTTypeHash(),
                            tokenId,
                            price,
                            deadline
                        )
                    )
                )
            )
        );

        NFTMarketPermit.PermitData memory permitData = NFTMarketPermit
            .PermitData({
                tokenId: tokenId,
                deadline: deadline,
                v: v,
                r: r,
                s: s
            });

        // 生成用于ERC20的permit签名
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(
            buyer,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            // token.PERMIT_TYPEHASH(),
                            buyer,
                            address(market),
                            price,
                            deadline,
                            0 // nonce
                        )
                    )
                )
            )
        );

        bytes memory permit = abi.encode(permitV, permitR, permitS);

        // 通过Permit购买NFT
        vm.prank(buyer);
        market.permitBuyNFT(permitData, permit);

        // 检查NFT所有权转移
        assertEq(nft.ownerOf(tokenId), buyer);

        // 检查卖家收到代币
        assertEq(token.balanceOf(seller), 1000 * 10 ** 18 + price);

        // 检查买家代币减少
        assertEq(token.balanceOf(buyer), 1000 * 10 ** 18 - price);
    }
}
