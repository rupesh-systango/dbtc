// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ECDSALib.sol";

// Custom Error Messsage
error AddressAlreadyAdmin();
error AddressAlreadySigner();
error AddressIsZeroAddress();
error CallerIsNotAdmin();
error AddressNotAdmin();
error AddressNotSigner();
error SignatureExpired();
error TraderAddressMismatch();
error TradeAlreadyExits();
error InvalidSigner();
error TradeNotExpired();
error TradeNotFound();
error TradeNotCreatedOrResolved();
error TradeAlreadyClaimed();
error SameValueAsPrevious();

contract DBTI is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using ECDSALib for bytes32;

    // Access Control constants for available roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    // Constant for the zero address
    address internal constant ZERO_ADDRESS = address(0);

    // Enum to represent the status of a trade
    enum TradeStatus {
        CREATED,
        WON,
        LOST
    }

    // Struct to represent a trade
    struct Trade {
        address trader; // Address of the trade creator
        uint256 startTime; // Trade start time
        uint256 endTime; // Trade end time
        address token; // ERC-20 token address for trade fee
        uint256 amount; // Trade fee in ERC-20 token
        uint256 adminFee; // Admin fee
        uint256 reward; // Reward associated with the trade
        bool claimed; // Boolean to check if a trade is claimed or not
        TradeStatus status; // TradeStatus of the trade
    }

    // Mapping of token metadata wrt to token id
    mapping(uint256 => string) private _tokenUri;

    // Mapping to store trades based on a unique trade ID
    mapping(uint256 => Trade) public trades;

    // Counter to keep track of the number of trades placed
    uint256 public tradeCount;

    // Thershold Amount
    uint256 public thresholdAmount;

    // Treasury address which is responsible for all payouts
    address public treasuryAccount;

    // Event to emit when a new trade is placed
    event TradeCreated(uint256 tradeId, address trader);

    // Event to emit when a trade is resolved
    event TradeResolved(uint256[] tradeId);

    // Event to emit when a trade is claimed
    event RewardClaimed(uint256[] tradeId);

    // Events to emit when a new admin is added
    event AdminAdded(address adminAddress);

    // Events to emit when an admin is removed
    event AdminRemoved(address adminAddress);

    // Events to emit when a new signer is added
    event SignerAdded(address signerAddress);

    // Events to emit when a signer is removed
    event SignerRemoved(address signerAddress);

    event ThersholdAmountUpdated(uint256 amount);

    /**
     * @notice Modifier to restrict access to admin only
     */
    modifier isAdmin() {
        if (!hasRole(ADMIN_ROLE, _msgSender())) {
            revert CallerIsNotAdmin();
        }
        _;
    }

    /**
     * @notice Initializes the contract with essential parameters and sets up initial roles.
     * @dev This function is called only once during contract deployment.
     * @param _thresholdAmount The threshold amount to be considered valid.
     * @param _treasuryAccount The address where trade fees are transferred.
     * @param name The name of the ERC-721 token.
     * @param symbol The symbol of the ERC-721 token.
     * @param admin The address designated as the initial admin role.
     * @param signer The address designated as the initial signer role.
     */
    function initialize(
        uint256 _thresholdAmount,
        address _treasuryAccount,
        string memory name,
        string memory symbol,
        address admin,
        address signer
    ) public initializer {
        _requireNotEmptyString(name);
        _requireNotEmptyString(symbol);

        if (
            _treasuryAccount == ZERO_ADDRESS ||
            admin == ZERO_ADDRESS ||
            signer == ZERO_ADDRESS
        ) {
            revert AddressIsZeroAddress();
        }
        __ERC721_init(name, symbol);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __Context_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(SIGNER_ROLE, signer);
        thresholdAmount = _thresholdAmount;
        treasuryAccount = _treasuryAccount;
    }
    /**
     * @notice Retrieves the token URI associated with the specified token ID.
     * @dev The token URI is a metadata link for the token's visual representation.
     * @param tokenId The ID of the token whose URI is to be retrieved.
     * @return The URI string representing the metadata of the token.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _tokenUri[tokenId];
    }

    /**
     * @notice Function to place a new trade with encoded data and signature
     * @param encodedTradeData The encoded data with the trade details
     * @param signature The signature of the user request with trade data
     */
    function createTrade(
        bytes memory encodedTradeData,
        bytes memory signature,
        string memory tokenMetadata
    ) external whenNotPaused nonReentrant {
        // Decode trade data
        _requireNotEmptyString(tokenMetadata);
        (
            uint256 tradeId,
            address trader,
            uint256 startTime,
            uint256 endTime,
            address token,
            uint256 amount,
            uint256 adminFee,
            uint256 reward,
            uint256 expiry
        ) = abi.decode(
                encodedTradeData,
                (
                    uint256,
                    address,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    uint256,
                    uint256,
                    uint256
                )
            );

        {
            if (block.timestamp > expiry) {
                revert SignatureExpired();
            }
            if (_msgSender() != trader) {
                revert TraderAddressMismatch();
            }
            if (trades[tradeId].trader != ZERO_ADDRESS) {
                revert TradeAlreadyExits();
            }
            bytes32 tradeHash = keccak256(encodedTradeData);
            address signer = tradeHash.toEthSignedMessageHash().recover(
                signature
            );
            if (!(hasRole(SIGNER_ROLE, signer))) {
                revert InvalidSigner();
            }
        }
        tradeCount++;
        // Transfer trade fee in ERC-20 tokens to treasuryAccount

        {
            // Create a new trade with the provided details and set as unresolved
            Trade memory newTrade = Trade(
                trader,
                startTime,
                endTime,
                token,
                amount,
                adminFee,
                reward,
                false, // Claim status at time of trade creation will always be false
                TradeStatus.CREATED
            );
            trades[tradeId] = newTrade;
        }
        // Mints an NFT for the trade
        _tokenUri[tradeId] = tokenMetadata;
        _safeMint(trader, tradeId);

        require(
            IERC20(token).transferFrom(
                _msgSender(),
                treasuryAccount,
                (amount + adminFee)
            ),
            "Fee transfer failed"
        );

        // Emit an event to signal that a new trade has been placed
        emit TradeCreated(tradeId, trader);
    }

    /**
     * @notice Function to resolve a trade
     * @dev Only admin can call this function.
     * @param tradeId The tradeId to resolve
     */
    function resolveTrade(
        uint256[] memory tradeId
    ) external isAdmin nonReentrant whenNotPaused {
        for (uint8 i = 0; i < tradeId.length; i++) {
            if (block.timestamp <= trades[tradeId[i]].endTime) {
                revert TradeNotExpired();
            }
            if (trades[tradeId[i]].trader == ZERO_ADDRESS) {
                revert TradeNotFound();
            }
            if (trades[tradeId[i]].status != TradeStatus.CREATED) {
                revert TradeNotCreatedOrResolved();
            }
            trades[tradeId[i]].status = TradeStatus.LOST;
            trades[tradeId[i]].claimed = true;
        }
        emit TradeResolved(tradeId);
    }

    /**
     * @notice Allows the owner of specified trades to claim their rewards.
     * @dev The caller must provide a valid signature along with the encoded trade data.
     * @param encodedTradeData The encoded data containing trade IDs and expiry timestamp.
     * @param signature The signature of the user request with trade data.
     */
    function claimTrade(
        bytes memory encodedTradeData,
        bytes memory signature
    ) external whenNotPaused nonReentrant {
        // Decode trade data
        (uint256[] memory tradeId, uint256 expiry) = abi.decode(
            encodedTradeData,
            (uint256[], uint256)
        );
        {
            if (block.timestamp > expiry) {
                revert SignatureExpired();
            }
            bytes32 tradeHash = keccak256(encodedTradeData);
            address signer = tradeHash.toEthSignedMessageHash().recover(
                signature
            );
            if (!(hasRole(SIGNER_ROLE, signer))) {
                revert InvalidSigner();
            }
        }
        uint256 totalReward = 0;
        for (uint8 i = 0; i < tradeId.length; i++) {
            if (trades[tradeId[i]].trader == ZERO_ADDRESS) {
                revert TradeNotFound();
            }
            if (ownerOf(tradeId[i]) != _msgSender()) {
                revert TraderAddressMismatch();
            }
            if (block.timestamp <= trades[tradeId[i]].endTime) {
                revert TradeNotExpired();
            }
            if (trades[tradeId[i]].claimed) {
                revert TradeAlreadyClaimed();
            }
            totalReward += trades[tradeId[i]].reward;
            trades[tradeId[i]].claimed = true;
            trades[tradeId[i]].status = TradeStatus.WON;
        }
        require(
            IERC20(trades[tradeId[0]].token).transfer(
                _msgSender(),
                totalReward
            ),
            "Fee transfer failed"
        );
        emit RewardClaimed(tradeId);
    }

    /**
     * @notice Function to Update Threshold Amount
     * @dev Only admin can call this function.
     * @param amount The amount to update
     */
    function updateThresholdAmount(
        uint256 amount
    ) external isAdmin whenNotPaused {
        if (amount == thresholdAmount) {
            revert SameValueAsPrevious();
        }
        thresholdAmount = amount;
        emit ThersholdAmountUpdated(amount);
    }

    /**
     * @notice Function to withdraw any ERC-20 tokens sent to the contract
     * @dev Only admin can call this function.
     * @param token The token contract address to withdraw
     * @param amount The amount of tokens to withdraw
     */
    function withdrawTokens(
        address token,
        uint256 amount
    ) external isAdmin whenNotPaused nonReentrant {
        if (token == ZERO_ADDRESS) {
            revert AddressIsZeroAddress();
        }
        require(
            IERC20(token).transfer(_msgSender(), amount),
            "Token transfer failed"
        );
    }

    /**
     * @notice Function to get a list of trades eligible for resolving
     * @param tradeId The tradeId to check for resolution
     */
    function checkTradeForResolution(
        uint256 tradeId
    ) external view returns (bool){
        return
            trades[tradeId].status == TradeStatus.CREATED &&
            block.timestamp <= trades[tradeId].endTime;
    }

    /**
     * @notice Adds a new admin to the contract.
     * @dev Only admin can call this function.
     * @param newAdmin The address to be added as an admin.
     */
    function addAdmin(address newAdmin) external isAdmin whenNotPaused {
        if (hasRole(ADMIN_ROLE, newAdmin)) {
            revert AddressAlreadyAdmin();
        }
        if (newAdmin == ZERO_ADDRESS) {
            revert AddressIsZeroAddress();
        }
        grantRole(ADMIN_ROLE, newAdmin);
        emit AdminAdded(newAdmin);
    }

    /**
     * @dev Remove the admin address for the contract.
     * @dev Only admin can call this function.
     * @param adminAddress The admin address to be removed from the contract.
     */
    function removeAdmin(address adminAddress) external isAdmin whenNotPaused {
        if (!hasRole(ADMIN_ROLE, adminAddress)) {
            revert AddressNotAdmin();
        }
        revokeRole(ADMIN_ROLE, adminAddress);
        emit AdminRemoved(adminAddress);
    }

    /**
     * @notice Adds a new signer to the contract.
     * @dev Only admin can call this function.
     * @param newSigner The address to be added as an signer.
     */
    function addSigner(address newSigner) external isAdmin whenNotPaused {
        if (hasRole(SIGNER_ROLE, newSigner)) {
            revert AddressAlreadySigner();
        }
        if (newSigner == ZERO_ADDRESS) {
            revert AddressIsZeroAddress();
        }
        grantRole(SIGNER_ROLE, newSigner);
        emit SignerAdded(newSigner);
    }

    /**
     * @dev Remove the signer address for the contract.
     * @dev Only admin can call this function.
     * @param signerAddress The signer address to be removed from the contract.
     */
    function removeSigner(
        address signerAddress
    ) external isAdmin whenNotPaused {
        if (!hasRole(SIGNER_ROLE, signerAddress)) {
            revert AddressNotSigner();
        }
        revokeRole(SIGNER_ROLE, signerAddress);
        emit SignerRemoved(signerAddress);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Soul-bound NFT. By overiding this function NFT's can't be transferd from one address to another.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        require(
            auth == address(0) || to == address(0),
            "Token not transferable"
        );
        return super._update(to, tokenId, auth);
    }

    function _requireNotEmptyString(string memory str) internal pure {
        require(bytes(str).length > 0, "String must not be empty");
    }

    /**
     * @dev Pauses the contract, preventing certain functions from being executed.
     * @dev Only admin can call this function.
     */
    function pause() external isAdmin whenNotPaused {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing the execution of all functions.
     * @dev Only admin can call this function.
     */
    function unpause() external isAdmin whenPaused {
        _unpause();
    }
}
