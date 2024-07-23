// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarket_List_By_Permit is EIP712, Ownable {
    using ECDSA for bytes32;

    IERC20 public immutable tokenContract;
    IERC20Permit public immutable tokenContractPermit;
    IERC721 public immutable nftContract;

    struct PermitData {
        uint256 tokenId;
        uint256 deadline;
    }

    struct PermitNFTList {
        address maker;
        uint256 tokenId;
        uint256 price;
        uint256 deadline;
        address payToken;
        address nft;
    }

    string private constant SIGNING_DOMAIN = "NFTMarketListByPermit";
    string private constant SIGNATURE_VERSION = "1";

    bytes32 private constant LIMIT_ORDER_TYPE_HASH = keccak256(
        "LimitOrder(address maker,uint256 tokenId,uint256 price,uint256 deadline,address payToken,address nft)"
    );

    constructor(address _tokenAddress, address _nftAddress)
        EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION)
        Ownable(msg.sender)
    {
        require(_tokenAddress != address(0), "Token contract address cannot be zero.");
        require(_nftAddress != address(0), "NFT contract address cannot be zero.");
        tokenContract = IERC20(_tokenAddress);
        tokenContractPermit = IERC20Permit(_tokenAddress);
        nftContract = IERC721(_nftAddress);
    }

    function buyNFTByPermitList(
        PermitData calldata permitData,
        bytes calldata permitERC20signature,
        PermitNFTList calldata permitNFTList,
        bytes calldata permitNFTListSignature
    ) external {
        // verify permitNFTList signature is valid
        verifyPermitNFTListSignature(
            permitNFTListSignature,
            permitNFTList.maker,
            permitNFTList.tokenId,
            permitNFTList.price,
            permitNFTList.deadline,
            permitNFTList.payToken,
            permitNFTList.nft
        );

        executePermitAndTransfer(permitData, permitNFTList, permitERC20signature);
        emit NFTSold(permitData.tokenId, permitNFTList.maker, msg.sender, permitNFTList.price);
    }

    function verifyPermitNFTListSignature(
        bytes calldata permitNFTListsignature,
        address maker,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        address payToken,
        address nft
    ) public view returns (address) {
        require(block.timestamp <= deadline, "deadline should not be passed");

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(LIMIT_ORDER_TYPE_HASH, maker, tokenId, price, deadline, payToken, nft))
        );

        address recoveredSigner = ECDSA.recover(digest, permitNFTListsignature);

        require(recoveredSigner == owner(), "signer should be owner");

        return recoveredSigner;
    }

    function executePermitAndTransfer(
        PermitData calldata permitData,
        PermitNFTList memory permitNFTList,
        bytes calldata signature
    ) public {
        require(signature.length == 65, "Invalid signature length");

        (uint8 v, bytes32 r, bytes32 s) = parseSignature(signature);

        try tokenContractPermit.permit(msg.sender, address(this), permitNFTList.price, permitData.deadline, v, r, s) {
            // Permit successful, proceed with transfer
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Permit failed: ", reason)));
        } catch {
            revert("Permit failed");
        }

        require(tokenContract.transferFrom(msg.sender, permitNFTList.maker, permitNFTList.price), "Transfer failed");

        nftContract.safeTransferFrom(permitNFTList.maker, msg.sender, permitData.tokenId);
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

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    function getLimitOrderTypeHash() public pure returns (bytes32) {
        return LIMIT_ORDER_TYPE_HASH;
    }

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event SignVerify(address indexed signer, address indexed owner, address indexed buyer);
    event NFTcancled(uint256 indexed tokenId, address indexed owner);
}
