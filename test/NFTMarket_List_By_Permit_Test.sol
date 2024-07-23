// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarket_List_By_Permit} from "../src/NFTMarket_List_By_Permit.sol";
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

contract NFTMarket_List_By_Permit_Test is Test {
    NFTMarket_List_By_Permit public market;
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

    // 事件：当 NFT 被购买时触发
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);

    function setUp() public {
        (owner, ownerPK) = makeAddrAndKey("owner");
        (seller, sellerPK) = makeAddrAndKey("seller");
        (buyer, buyerPK) = makeAddrAndKey("buyer");

        token = new MockERC20Permit();
        nft = new MockERC721();

        vm.prank(owner); // prank 只会影响下一笔交易 NFTMarketPermit 合约的 msg.sender 就被设置成为了 owner
        market = new NFTMarket_List_By_Permit(address(token), address(nft));

        deadline = block.timestamp + 1 days;

        // 给seller用户mint一个NFT,设置的tokenId为1
        nft.mint(seller, 1);
        tokenId = 1;

        // 设置NFT价格
        nftPrice = 10 ether;
        // 给买家一些代币
        token.mint(buyer, 10000 ether);
    }

    function testBuyNFTByListPermit() public {
        // 计算用户上架NFT的离线签名，卖家的前置操作
        bytes memory sellerListNFTSignature = _getListNFTSignature();
        // 计算ERC2612的离线签名
        bytes memory eip2612Signature = _getEIP2612Signature();

        // seller 用户
        vm.startPrank(seller);
        // seller用户授权market合约托管nft
        nft.approve(address(market), tokenId);
        vm.stopPrank();

        // buyer用户
        vm.prank(buyer);

        market.buyNFTByPermitList(
            NFTMarket_List_By_Permit.PermitData(tokenId, deadline),
            eip2612Signature,
            NFTMarket_List_By_Permit.PermitNFTList(seller, tokenId, nftPrice, deadline, address(token), address(nft)),
            sellerListNFTSignature
        );

        assertEq(nft.ownerOf(1), buyer);
    }

    function _getEIP2612Signature() private view returns (bytes memory) {
        bytes32 eip2612Digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                ERC20Permit(token).DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(eip2612PermitTypeHash, buyer, address(market), nftPrice, token.nonces(buyer), deadline)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPK, eip2612Digest);
        bytes memory eip2612Signature = abi.encodePacked(r, s, v);
        return eip2612Signature;
    }

    function _getListNFTSignature() private view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        market.getLimitOrderTypeHash(),
                        seller,
                        tokenId,
                        nftPrice,
                        deadline,
                        address(token),
                        address(nft)
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, digest);
        bytes memory sellerListNFTSignature = abi.encodePacked(r, s, v);
        return sellerListNFTSignature;
    }
}
