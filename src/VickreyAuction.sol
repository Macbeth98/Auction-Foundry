// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

contract VickreyAuction {
    error VA_CANNOT_CREATE_AUCTION_IN_THE_PAST();
    error VA_DEFINE_BID_REVEAL_PERIOD();
    error VA_RESERVED_PRICE_CANNOT_BE_ZERO();
    error VA__AUCTION_EXISTS(uint32 startTime, uint32 endTime);
    error VA__AUCTION_EXISTS_NOT_ENDED();
    error VA__AUCTION_DOES_NOT_EXIST();

    error VA__BID_PERIOD_NOT_STARTED(uint32 startTime);
    error VA__BID_PERIOD_IS_OVER(uint32 endTime);
    error VA__BID_COLLATERAL_CANNOT_BE_ZERO();
    error VA__BID_COMMITMENT_CANNOT_BE_EMPTY();

    error VA__REVEAL_PERIOD_NOT_STARTED(uint32 startTime);
    error VA__REVEAL_PERIOD_IS_OVER(uint32 endTime);
    error VA__REVEAL_BID_COMMITMENT_VERIFICATION_FAILED();
    error VA__REVEAL_BID_ALREADY_REVEALED();

    error VA__AUCTION_HAS_UNREVEALED_BIDS_AND_IS_IN_REVEAL_PERIOD(
        uint32 endTime
    );
    error VA__END_AUCTION_ONLY_BY_SELLER();

    error VA__WITHDRAW_COLLATERAL_BID_NOT_REVEALED();
    error VA__WITHDRAW_COLLATERAL_BID_IS_HIGHEST_BIDDER();
    error VA__WITHDRAW_COLLATERAL_IS_ZERO();

    /// @param seller The address selling the auctioned asset.
    /// @param startTime The unix timestamp at which bidding can start.
    /// @param endOfBiddingPeriod The unix timestamp after which bids can no
    ///        longer be placed.
    /// @param endOfRevealPeriod The unix timestamp after which commitments can
    ///        no longer be opened.
    /// @param numUnrevealedBids The number of bid commitments that have not
    ///        yet been opened.
    /// @param highestBid The value of the highest bid revealed so far, or
    ///        the reserve price if no bids have exceeded it.
    /// @param secondHighestBid The value of the second-highest bid revealed
    ///        so far, or the reserve price if no two bids have exceeded it.
    /// @param highestBidder The bidder that placed the highest bid.
    /// @param index Auctions selling the same asset (i.e. tokenContract-tokenId
    ///        pair) share the same storage. This value is incremented for
    ///        each new auction of a particular asset.
    struct Auction {
        address seller;
        uint32 startTime;
        uint32 endOfBiddingPeriod;
        uint32 endOfRevealPeriod;
        uint64 numUnrevealedBids;
        uint96 highestBid;
        uint96 secondHighestBid;
        address highestBidder;
        uint64 index;
    }

    /// @dev Representation of a bid in storage. Occupies one slot
    /// @param commitment The hash commitment of a bid value
    /// @param collateral The amount of collateral backing the bid
    struct Bid {
        bytes20 commitment;
        uint96 collateral;
    }

    bytes20 private constant BID_REVEALED = bytes20("Bid Revealed");

    /// @notice A mapping storing auction itemId and state
    mapping(uint256 => Auction) public auctions;

    /// @notice A mapping storing bid commitments and records of collateral,
    ///         indexed by item ID, auction index,
    ///         and bidder address. If the commitment is `bytes20(0)`, either
    ///         no commitment was made or the commitment was opened.
    mapping(uint256 => mapping(uint64 => mapping(address => Bid))) // item ID // Auction index // Bidder
        public bids;

    /** EVENTS */
    event AuctionCreated(
        uint256 indexed itemId,
        address indexed seller,
        uint32 startTime,
        uint32 endTime,
        uint96 reservePrice
    );

    event BidCommitted(
        uint256 indexed itemId,
        address indexed bidder,
        uint96 collateral
    );

    event BidRevealed(
        uint256 indexed itemId,
        address indexed bidder,
        uint96 bidValue
    );

    /// @notice Creates an auction for the given physical asset with the given
    ///         auction parameters.
    /// @param itemId The physical asset being auctioned.
    /// @param startTime The unix timestamp at which bidding can start.
    /// @param bidPeriod The duration of the bidding period, in seconds.
    /// @param revealPeriod The duration of the commitment reveal period,
    ///        in seconds.
    /// @param reservePrice The minimum price that the asset will be sold for.
    ///        If no bids exceed this price, the asset is returned to `seller`.
    function createAuction(
        uint256 itemId,
        uint32 startTime,
        uint32 bidPeriod,
        uint32 revealPeriod,
        uint96 reservePrice
    ) external {
        if (startTime < block.timestamp) {
            revert VA_CANNOT_CREATE_AUCTION_IN_THE_PAST();
        }

        if (bidPeriod == 0 || revealPeriod == 0) {
            revert VA_DEFINE_BID_REVEAL_PERIOD();
        }

        if (reservePrice == 0) {
            revert VA_RESERVED_PRICE_CANNOT_BE_ZERO();
        }

        Auction memory checkAuction = auctions[itemId];
        uint64 index = 1;

        if (checkAuction.index > 0) {
            if (checkAuction.endOfRevealPeriod > block.timestamp) {
                revert VA__AUCTION_EXISTS(
                    checkAuction.startTime,
                    checkAuction.endOfRevealPeriod
                );
            }

            if (checkAuction.startTime > 0) {
                revert VA__AUCTION_EXISTS_NOT_ENDED();
            }

            index = checkAuction.index + 1;
        }

        Auction memory auction = Auction({
            seller: msg.sender,
            startTime: startTime,
            endOfBiddingPeriod: startTime + bidPeriod,
            endOfRevealPeriod: startTime + bidPeriod + revealPeriod,
            numUnrevealedBids: 0,
            highestBid: reservePrice,
            secondHighestBid: reservePrice,
            highestBidder: address(0),
            index: index
        });
        auctions[itemId] = auction;

        emit AuctionCreated(
            itemId,
            msg.sender,
            startTime,
            auction.endOfRevealPeriod,
            reservePrice
        );
    }

    /// @notice Commits to a bid on an item being auctioned. If a bid was
    ///         previously committed to, overwrites the previous commitment.
    ///         Value attached to this call is used as collateral for the bid.
    /// @param itemId The item ID of the asset being auctioned.
    /// @param commitment The commitment to the bid, computed as
    ///        `bytes20(keccak256(abi.encode(nonce, bidValue, tokenContract, tokenId, auctionIndex)))`.
    function commitBid(uint256 itemId, bytes20 commitment) external payable {
        Auction memory auction = auctions[itemId];
        if (auction.startTime == 0) {
            revert VA__AUCTION_DOES_NOT_EXIST();
        }

        if (block.timestamp < auction.startTime) {
            revert VA__BID_PERIOD_NOT_STARTED(auction.startTime);
        }

        if (block.timestamp > auction.endOfBiddingPeriod) {
            revert VA__BID_PERIOD_IS_OVER(auction.endOfBiddingPeriod);
        }

        if (msg.value == 0) {
            revert VA__BID_COLLATERAL_CANNOT_BE_ZERO();
        }

        if (commitment == bytes20(0)) {
            revert VA__BID_COMMITMENT_CANNOT_BE_EMPTY();
        }

        uint96 collateral = uint96(msg.value);

        Bid memory bid = bids[itemId][auction.index][msg.sender];
        if (bid.commitment != bytes20(0)) {
            auction.numUnrevealedBids -= 1;
            collateral += bid.collateral;
        }

        bids[itemId][auction.index][msg.sender] = Bid({
            commitment: commitment,
            collateral: collateral
        });
        auction.numUnrevealedBids += 1;
        auctions[itemId] = auction;

        emit BidCommitted(itemId, msg.sender, collateral);
    }

    /// @notice Reveals the value of a bid that was previously committed to.
    /// @param itemId The item ID of the asset being auctioned.
    /// @param bidValue The value of the bid.
    /// @param nonce The random input used to obfuscate the commitment.
    function revealBid(
        uint256 itemId,
        uint96 bidValue,
        bytes32 nonce
    ) external {
        Auction memory auction = auctions[itemId];
        if (auction.startTime == 0) {
            revert VA__AUCTION_DOES_NOT_EXIST();
        }

        if (block.timestamp < auction.endOfBiddingPeriod) {
            revert VA__REVEAL_PERIOD_NOT_STARTED(auction.endOfBiddingPeriod);
        }

        if (block.timestamp > auction.endOfRevealPeriod) {
            revert VA__REVEAL_PERIOD_IS_OVER(auction.endOfRevealPeriod);
        }

        Bid memory bid = bids[itemId][auction.index][msg.sender];

        if (bid.commitment == BID_REVEALED) {
            revert VA__REVEAL_BID_ALREADY_REVEALED();
        }

        bytes20 commitment = bytes20(
            keccak256(abi.encode(nonce, bidValue, auction.index))
        );

        if (commitment != bid.commitment) {
            revert VA__REVEAL_BID_COMMITMENT_VERIFICATION_FAILED();
        }

        if (bid.collateral >= bidValue) {
            if (bidValue > auction.highestBid) {
                auction.secondHighestBid = auction.highestBid;
                auction.highestBid = bidValue;
                auction.highestBidder = msg.sender;
            } else if (bidValue > auction.secondHighestBid) {
                auction.secondHighestBid = bidValue;
            }
        }

        auction.numUnrevealedBids -= 1;
        bids[itemId][auction.index][msg.sender] = Bid({
            commitment: BID_REVEALED,
            collateral: bid.collateral
        });
        auctions[itemId] = auction;

        emit BidRevealed(itemId, msg.sender, bidValue);
    }

    /// @notice Ends an active auction. Can only end an auction if the bid reveal
    ///         phase is over, or if all bids have been revealed. Disburses the auction
    ///         proceeds to the seller. Transfers the auctioned asset to the winning
    ///         bidder and returns any excess collateral. If no bidder exceeded the
    ///         auction's reserve price, returns the asset to the seller.
    /// @param itemId The item ID of the asset auctioned.
    function endAuction(uint256 itemId) external returns (address assetOwner) {
        Auction memory auction = auctions[itemId];
        if (auction.startTime == 0) {
            revert VA__AUCTION_DOES_NOT_EXIST();
        }

        if (auction.seller != msg.sender) {
            revert VA__END_AUCTION_ONLY_BY_SELLER();
        }

        if (block.timestamp < auction.endOfBiddingPeriod) {
            revert VA__REVEAL_PERIOD_NOT_STARTED(auction.endOfBiddingPeriod);
        }

        if (block.timestamp < auction.endOfRevealPeriod) {
            if (auction.numUnrevealedBids > 0) {
                revert VA__AUCTION_HAS_UNREVEALED_BIDS_AND_IS_IN_REVEAL_PERIOD(
                    auction.endOfRevealPeriod
                );
            }

            auction.endOfRevealPeriod = uint32(block.timestamp);
        }

        if (auction.highestBidder == address(0)) {
            assetOwner = auction.seller;
            auction.startTime = 0;
            auctions[itemId] = auction; // set the auction to be ended
            return assetOwner;
        }

        Bid memory bid = bids[itemId][auction.index][auction.highestBidder];

        uint96 excessCollateral = 0;

        if (bid.collateral > auction.highestBid) {
            // If the collateral is more than the highest bid, then the excess collateral is returned to the highest bidder
            excessCollateral = bid.collateral - auction.highestBid;
        }

        // Set the state, before transferring the assets to the highest bidder
        bids[itemId][auction.index][auction.highestBidder] = Bid({
            commitment: BID_REVEALED,
            collateral: 0
        });

        auction.startTime = 0;
        auctions[itemId] = auction; // set the auction to be ended

        // transfer asset to highest bidder
        assetOwner = auction.highestBidder;

        // transfer collateral to seller. We are ensured through reveal Bid that the Highest Bidder has atleast the Bid Value as the collateral.
        payable(auction.seller).transfer(auction.highestBid);

        if (excessCollateral > 0) {
            payable(auction.highestBidder).transfer(excessCollateral);
        }

        return assetOwner;
    }

    /// @notice Withdraws collateral. Bidder must have opened their bid commitment
    ///         and cannot be in the running to win the auction.
    /// @param itemId The item ID of the asset that was auctioned.
    /// @param auctionIndex The index of the auction that was being bid on.
    function withdrawCollateral(uint256 itemId, uint64 auctionIndex) external {
        Auction memory auction = auctions[itemId];

        Bid memory bid = bids[itemId][auctionIndex][msg.sender];

        if (bid.commitment != BID_REVEALED) {
            revert VA__WITHDRAW_COLLATERAL_BID_NOT_REVEALED();
        }

        if (auction.highestBidder == msg.sender) {
            revert VA__WITHDRAW_COLLATERAL_BID_IS_HIGHEST_BIDDER();
        }

        uint96 collateral = bid.collateral;

        if (collateral == 0) {
            revert VA__WITHDRAW_COLLATERAL_IS_ZERO();
        }

        bids[itemId][auctionIndex][msg.sender] = Bid({
            commitment: BID_REVEALED,
            collateral: 0
        });

        payable(msg.sender).transfer(collateral);
    }

    /// @notice Gets the parameters and state of an auction in storage.
    /// @param itemId The item ID of the asset auctioned.
    function getAuction(
        uint256 itemId
    ) external view returns (Auction memory auction) {
        auction = auctions[itemId];
    }
}
