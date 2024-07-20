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

    // struct PermitWL {
    //     address buyer;
    //     uint256 deadline;
    // }

    mapping(uint256 => Listing) public listings;

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event SignVerify(address indexed signer, address indexed owner, address indexed buyer);
    event NFTcancled(uint256 indexed tokenId, address indexed owner);

    bytes32 private constant WHITE_LIST_TYPE_HASH = keccak256("PermitBuyNFTWL(address buyer,uint256 deadline)");

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

    function cancelList(uint256 _tokenId) external {
        address seller = listings[_tokenId].seller;
        require(seller == msg.sender, "Not the owner");
        delete listings[_tokenId];
        emit NFTcancled(_tokenId, seller);
    }

    function permitBuyNFT(
        bytes calldata _permitWL,
        address buyer,
        uint256 deadline,
        PermitData calldata permitData,
        bytes calldata _permit
    ) external {
        Listing memory listing = listings[permitData.tokenId];
        require(listing.seller != address(0), "NFT not listed");

        verifyPermitSignature(_permitWL, buyer, deadline);
        executePermitAndTransfer(permitData, listing, _permit);

        delete listings[permitData.tokenId];
        emit NFTSold(permitData.tokenId, listing.seller, msg.sender, listing.price);
    }

    function verifyPermitSignature(bytes calldata signatureWL, address buyer, uint256 deadline)
        public
        view
        returns (address)
    {
        require(block.timestamp <= deadline, "deadline should not be passed");
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(WHITE_LIST_TYPE_HASH, buyer, deadline)));

        address recoveredSigner = ECDSA.recover(digest, signatureWL);
        require(recoveredSigner == owner(), "signer should be owner");
        require(buyer == msg.sender, "buyer should be msg.sender");
        return recoveredSigner;
    }

    function executePermitAndTransfer(PermitData calldata permitData, Listing memory listing, bytes calldata signature)
        public
    {
        require(signature.length == 65, "Invalid signature length");

        (uint8 v, bytes32 r, bytes32 s) = parseSignature(signature);

        try tokenContractPermit.permit(msg.sender, address(this), listing.price, permitData.deadline, v, r, s) {
            // Permit successful, proceed with transfer
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Permit failed: ", reason)));
        } catch {
            revert("Permit failed");
        }

        require(tokenContract.transferFrom(msg.sender, listing.seller, listing.price), "Transfer failed");
        nftContract.safeTransferFrom(listing.seller, msg.sender, permitData.tokenId);
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

    function getWhiteListTypeHash() public pure returns (bytes32) {
        return WHITE_LIST_TYPE_HASH;
    }
}
