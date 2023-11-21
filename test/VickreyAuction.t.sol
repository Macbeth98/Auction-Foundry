// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {VickreyAuction} from "../src/VickreyAuction.sol";

contract VickreyAuctionTest is Test {
    bytes20 private constant BID_REVEALED = bytes20("Bid Revealed");

    VickreyAuction public vAuction;

    struct AuctionParams {
        uint256 itemId;
        uint32 startTime;
        uint32 bidPeriod;
        uint32 revealPeriod;
        uint96 reservePrice;
    }

    AuctionParams public auctionParams;

    address public constant SELLER = address(0xa1);
    address public constant BUYER1 = address(0xb1);
    address public constant BUYER2 = address(0xb2);

    function setUp() public {
        vAuction = new VickreyAuction();
        auctionParams = AuctionParams({
            itemId: 1,
            startTime: uint32(block.timestamp),
            bidPeriod: 60 * 5,
            revealPeriod: 60 * 5,
            reservePrice: 1
        });

        vm.deal(SELLER, 10 ether);
        vm.deal(BUYER1, 10 ether);
        vm.deal(BUYER2, 10 ether);
    }

    function createAuction(address seller) internal {
        vm.prank(seller);
        vAuction.createAuction(
            auctionParams.itemId,
            auctionParams.startTime,
            auctionParams.bidPeriod,
            auctionParams.revealPeriod,
            auctionParams.reservePrice
        );
    }

    function getCommitment(
        bytes32 nonce,
        uint96 bidValue,
        uint64 auctionIndex
    ) public pure returns (bytes20) {
        return bytes20(keccak256(abi.encode(nonce, bidValue, auctionIndex)));
    }

    function testCreateAuction() public {
        createAuction(SELLER);
        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        assertEq(auction.seller, SELLER);
        assertEq(auction.startTime, auctionParams.startTime);
        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod
        );
        assertEq(
            auction.endOfRevealPeriod,
            auctionParams.startTime +
                auctionParams.bidPeriod +
                auctionParams.revealPeriod
        );
        assertEq(auction.highestBid, auctionParams.reservePrice);
        assertEq(auction.secondHighestBid, auctionParams.reservePrice);
        assertEq(auction.highestBidder, address(0));
        assertEq(auction.index, 1);
        assertEq(auction.numUnrevealedBids, 0);
        assertEq(auction.highestBid, auctionParams.reservePrice);
        assertEq(auction.secondHighestBid, auctionParams.reservePrice);
    }

    function testCreateAuctionCanBeDoneForTheSameItemWhenPreviousAuctionIsDone()
        public
    {
        createAuction(SELLER);

        skip(
            auctionParams.startTime +
                auctionParams.bidPeriod +
                auctionParams.revealPeriod +
                1
        );

        auctionParams.startTime = uint32(block.timestamp);

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);
        assertEq(owner, SELLER, "owner is not seller");

        createAuction(SELLER);
        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        assertEq(auction.seller, SELLER);
        assertEq(auction.startTime, auctionParams.startTime);
        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod
        );
        assertEq(
            auction.endOfRevealPeriod,
            auctionParams.startTime +
                auctionParams.bidPeriod +
                auctionParams.revealPeriod
        );
        assertEq(auction.highestBid, auctionParams.reservePrice);
        assertEq(auction.secondHighestBid, auctionParams.reservePrice);
        assertEq(auction.highestBidder, address(0));
        assertEq(auction.index, 2);
    }

    function testCreationAuctionCannotBeDoneForTheSameItemBeforeTheEndOfPreviousAuction()
        public
    {
        createAuction(SELLER);
        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.VA__AUCTION_EXISTS.selector,
                auction.startTime,
                auction.endOfRevealPeriod
            )
        );
        createAuction(SELLER);
    }

    function testCreateAcutionCannotBeDoneForTheSameItemWithoutEndingEvenIfTheRevealPeriodIsDone()
        public
    {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        assertEq(
            auction.endOfRevealPeriod,
            auctionParams.startTime +
                auctionParams.bidPeriod +
                auctionParams.revealPeriod,
            "endOfRevealPeriod is not correct"
        );

        skip(auctionParams.bidPeriod + auctionParams.revealPeriod + 1);

        assertEq(block.timestamp > auction.endOfRevealPeriod, true);

        auctionParams.startTime = uint32(block.timestamp);

        vm.expectRevert(VickreyAuction.VA__AUCTION_EXISTS_NOT_ENDED.selector);
        createAuction(SELLER);
    }

    function testCreateAuctionCannotBeCreatedInThePast() public {
        skip(120);
        auctionParams.startTime = uint32(block.timestamp) - 100;
        vm.expectRevert(
            VickreyAuction.VA_CANNOT_CREATE_AUCTION_IN_THE_PAST.selector
        );
        createAuction(SELLER);
    }

    function testCreateAuctionCannotBeCreatedWithZeroBidPeriod() public {
        auctionParams.bidPeriod = 0;
        vm.expectRevert(VickreyAuction.VA_DEFINE_BID_REVEAL_PERIOD.selector);
        createAuction(SELLER);
    }

    function testCreateAuctionCannotBeCreatedWithZeroRevealPeriod() public {
        auctionParams.revealPeriod = 0;
        vm.expectRevert(VickreyAuction.VA_DEFINE_BID_REVEAL_PERIOD.selector);
        createAuction(SELLER);
    }

    function testCreateAuctionCannotBeCreatedWithZeroReservePrice() public {
        auctionParams.reservePrice = 0;
        vm.expectRevert(
            VickreyAuction.VA_RESERVED_PRICE_CANNOT_BE_ZERO.selector
        );
        createAuction(SELLER);
    }

    function testCommitBidCannotBeDoneBeforeAuctionStartTime() public {
        auctionParams.startTime = uint32(block.timestamp) + 100;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        assertEq(auction.seller, SELLER, "seller is not correct");
        assertEq(
            auction.startTime,
            auctionParams.startTime,
            "startTime is not correct"
        );
        assertEq(
            auction.startTime > block.timestamp,
            true,
            "startTime is not in the future"
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.VA__BID_PERIOD_NOT_STARTED.selector,
                auctionParams.startTime
            )
        );
        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);
    }

    function testCommitBidCannotBeDoneForNonExistentAuction() public {
        vm.expectRevert(VickreyAuction.VA__AUCTION_DOES_NOT_EXIST.selector);
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, 0);
        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);
    }

    function testCommitBidCannotBeDoneWhenBidPeriodIsDone() public {
        auctionParams.bidPeriod = 1;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        assertEq(auction.seller, SELLER, "seller is not correct");
        assertEq(
            auction.startTime,
            auctionParams.startTime,
            "startTime is not correct"
        );
        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod,
            "endOfBiddingPeriod is not correct"
        );
        assertEq(1, block.timestamp, "block.timestamp is not correct");
        assertEq(
            auction.startTime >= block.timestamp,
            true,
            "startTime is not in the future"
        );

        skip(2);

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        console2.log("acution.endOfBiddingPeriod", auction.endOfBiddingPeriod);

        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.VA__BID_PERIOD_IS_OVER.selector,
                auction.endOfBiddingPeriod
            )
        );
        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);
    }

    function testCommitBidCannotBeDoneWithZeroCollateral() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 0;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.expectRevert(
            VickreyAuction.VA__BID_COLLATERAL_CANNOT_BE_ZERO.selector
        );
        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);
    }

    function testCommitBidCommitmentCannotBeEmpty() public {
        createAuction(SELLER);

        bytes20 commitment = bytes20(0);

        vm.expectRevert(
            VickreyAuction.VA__BID_COMMITMENT_CANNOT_BE_EMPTY.selector
        );
        vm.prank(BUYER1);
        vAuction.commitBid{value: 1}(auctionParams.itemId, commitment);
    }

    function testCommitBidSuccess() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);
        console2.log("commitment");
        console2.logBytes20(commitment);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        console2.log("bidCommitment");
        console2.logBytes20(bidCommitment);

        assertEq(bidCommitment, commitment, "commitment is not correct");
        assertEq(bidCollateral, bidValue, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");
    }

    function testCommitBidRewriteBid() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        assertEq(bidCommitment, commitment, "commitment is not correct");
        assertEq(bidCollateral, bidValue, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");

        uint96 bidValue2 = 10;
        bytes20 commitment2 = getCommitment(nonce, bidValue2, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue2}(auctionParams.itemId, commitment2);

        (bytes20 bidCommitment2, uint96 bidCollateral2) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        assertEq(bidCommitment2, commitment2, "commitment is not correct");
        assertEq(
            bidCollateral2,
            bidValue2 + bidValue,
            "collateral is not correct"
        );

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");
    }

    function testRevealBidCannotBeDoneOnNonExistentAuction() public {
        vm.expectRevert(VickreyAuction.VA__AUCTION_DOES_NOT_EXIST.selector);
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        getCommitment(nonce, bidValue, 0);
        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);
    }

    // Also, the end of BIdding Period.
    function testRevealBidCannotbeDoneBeforeTheStartOfRevealPeriod() public {
        auctionParams.bidPeriod = 1;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod,
            "endOfBiddingPeriod is not correct"
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.VA__REVEAL_PERIOD_NOT_STARTED.selector,
                auction.endOfBiddingPeriod
            )
        );
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);
    }

    function testRevealBidCannotBeDoneAfterRevealPeriodIsOver() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 1;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod,
            "endOfBiddingPeriod is not correct"
        );

        assertEq(
            auction.endOfRevealPeriod,
            auctionParams.startTime +
                auctionParams.bidPeriod +
                auctionParams.revealPeriod,
            "endOfRevealPeriod is not correct"
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(3);

        assertEq(block.timestamp, 4, "block.timestamp is not correct");

        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.VA__REVEAL_PERIOD_IS_OVER.selector,
                auction.endOfRevealPeriod
            )
        );
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);
    }

    function testRevealBidCannotBeDoneWithIncorrectNonceOrBidValue() public {
        console2.log("block.timestamp: Before create Auction", block.timestamp);
        createAuction(SELLER);
        console2.log("block.timestamp: After create Auction", block.timestamp);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        bytes32 nonce2 = bytes32("1234");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        console2.log("block.timestamp: After commitBid", block.timestamp);
        console2.log("Bid commitment");
        console2.logBytes20(commitment);

        skip(auctionParams.bidPeriod + 1);

        vm.expectRevert(
            VickreyAuction
                .VA__REVEAL_BID_COMMITMENT_VERIFICATION_FAILED
                .selector
        );
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce2);

        vm.expectRevert(
            VickreyAuction
                .VA__REVEAL_BID_COMMITMENT_VERIFICATION_FAILED
                .selector
        );
        vAuction.revealBid(auctionParams.itemId, bidValue + 1, nonce);
    }

    function testRevealBidCannotBeDoneTwice() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auctionParams.bidPeriod + 1);

        vm.startPrank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        assertEq(bidCommitment, BID_REVEALED, "commitment is not correct");
        assertEq(bidCollateral, bidValue, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");

        vm.expectRevert(
            VickreyAuction.VA__REVEAL_BID_ALREADY_REVEALED.selector
        );
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);
        vm.stopPrank();
    }

    function testRevealBidWithHighestBid() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auctionParams.bidPeriod + 1);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        assertEq(bidCommitment, BID_REVEALED, "commitment is not correct");
        assertEq(bidCollateral, bidValue, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(auction.highestBid, bidValue, "highestBid is not correct");
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
        assertEq(auction.highestBidder, BUYER1, "highestBidder is not correct");
    }

    function testRevealBidWithSecondHighestBid21() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;

        bytes32 nonce1 = bytes32("123");
        uint96 bidValue1 = auctionParams.reservePrice + 2;
        bytes20 commitment1 = getCommitment(nonce1, bidValue1, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue1}(auctionParams.itemId, commitment1);

        bytes32 nonce2 = bytes32("1234");
        uint96 bidValue2 = auctionParams.reservePrice + 1;
        bytes20 commitment2 = getCommitment(nonce2, bidValue2, auctionIndex);

        vm.prank(BUYER2);
        vAuction.commitBid{value: bidValue2}(auctionParams.itemId, commitment2);

        skip(auctionParams.bidPeriod + 1);

        vm.prank(BUYER2);
        vAuction.revealBid(auctionParams.itemId, bidValue2, nonce2);

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");
        assertEq(auction.highestBid, bidValue2, "highestBid is not correct");
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
        assertEq(auction.highestBidder, BUYER2, "highestBidder is not correct");

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue1, nonce1);

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(auction.highestBid, bidValue1, "highestBid is not correct");
        assertEq(
            auction.secondHighestBid,
            bidValue2,
            "secondHighestBid is not correct"
        );
        assertEq(auction.highestBidder, BUYER1, "highestBidder is not correct");
        assertEq(
            auction.secondHighestBid,
            bidValue2,
            "secondHighestBid is not correct"
        );
    }

    function testRevealBidWithSecondHighestBid12() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        uint64 auctionIndex = auction.index;

        bytes32 nonce1 = bytes32("123");
        uint96 bidValue1 = auctionParams.reservePrice + 2;
        bytes20 commitment1 = getCommitment(nonce1, bidValue1, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue1}(auctionParams.itemId, commitment1);

        bytes32 nonce2 = bytes32("1234");
        uint96 bidValue2 = auctionParams.reservePrice + 1;
        bytes20 commitment2 = getCommitment(nonce2, bidValue2, auctionIndex);

        vm.prank(BUYER2);
        vAuction.commitBid{value: bidValue2}(auctionParams.itemId, commitment2);

        skip(auctionParams.bidPeriod + 1);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue1, nonce1);

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");
        assertEq(auction.highestBid, bidValue1, "highestBid is not correct");
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
        assertEq(auction.highestBidder, BUYER1, "highestBidder is not correct");

        vm.prank(BUYER2);
        vAuction.revealBid(auctionParams.itemId, bidValue2, nonce2);

        auction = vAuction.getAuction(auctionParams.itemId);

        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(auction.highestBid, bidValue1, "highestBid is not correct");
        assertEq(
            auction.secondHighestBid,
            bidValue2,
            "secondHighestBid is not correct"
        );
    }

    function testRevealBidWithHighestBidButLessCollateral() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 5;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue - 1}(
            auctionParams.itemId,
            commitment
        );

        skip(auction.endOfBiddingPeriod + 1);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        assertEq(bidCommitment, BID_REVEALED, "commitment is not correct");
        assertEq(bidCollateral, bidValue - 1, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(
            auction.highestBid,
            auctionParams.reservePrice,
            "highestBid is not correct"
        );
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
    }

    function testEndAuctionWithNonExistentAuction() public {
        vm.expectRevert(VickreyAuction.VA__AUCTION_DOES_NOT_EXIST.selector);
        vAuction.endAuction(auctionParams.itemId);
    }

    function testEndAuctionCanNotBeDoneOtherThanSeller() public {
        createAuction(SELLER);

        vm.prank(BUYER1);
        vm.expectRevert(VickreyAuction.VA__END_AUCTION_ONLY_BY_SELLER.selector);
        vAuction.endAuction(auctionParams.itemId);
    }

    function testEndAuctionBeforeTheStartOfRevealPeriod() public {
        auctionParams.bidPeriod = 1;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod,
            "endOfBiddingPeriod is not correct"
        );

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.VA__REVEAL_PERIOD_NOT_STARTED.selector,
                auction.endOfBiddingPeriod
            )
        );
        vAuction.endAuction(auctionParams.itemId);
    }

    function testEndAuctionBeforeRevealPeriodIsOverWithUnRevealedBids() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 2;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        assertEq(
            auction.endOfBiddingPeriod,
            auctionParams.startTime + auctionParams.bidPeriod,
            "endOfBiddingPeriod is not correct"
        );
        assertEq(
            auction.endOfRevealPeriod,
            auctionParams.startTime +
                auctionParams.bidPeriod +
                auctionParams.revealPeriod,
            "endOfRevealPeriod is not correct"
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");

        uint32 timestamp = uint32(block.timestamp);

        skip(auction.endOfBiddingPeriod);
        assertEq(
            block.timestamp,
            timestamp + auction.endOfBiddingPeriod,
            "block.timestamp is not correct"
        );
        assertEq(
            block.timestamp < auction.endOfRevealPeriod,
            true,
            "block.timestamp is not less than endOfRevealPeriod"
        );

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction
                    .VA__AUCTION_HAS_UNREVEALED_BIDS_AND_IS_IN_REVEAL_PERIOD
                    .selector,
                auction.endOfRevealPeriod
            )
        );
        vAuction.endAuction(auctionParams.itemId);
    }

    // End an auction With No Unrevealed Bids Even Before reveal Period
    function testEndAuctionBeforeRevealPeriodWithNoUnRevealedBids() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 2;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auction.endOfBiddingPeriod);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(
            auction.endOfRevealPeriod,
            auctionParams.startTime + 3,
            "endOfRevealPeriod is not correct"
        );

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);
        assertEq(owner, BUYER1, "owner is not buyer1");

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(
            auction.endOfRevealPeriod,
            block.timestamp,
            "endOfRevealPeriod after endAuction is not correct"
        );
        assertEq(
            auction.startTime,
            0,
            "startTime after endAuction is not correct"
        );
    }

    // ENd an auction With Unrevealed Bids
    function testEndAuctionAfterRevealPeriodWithUnRevealedBids() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 2;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auction.endOfRevealPeriod);

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);

        assertEq(owner, SELLER, "owner is not seller");

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");
        assertEq(
            auction.highestBid,
            auctionParams.reservePrice,
            "highestBid is not correct"
        );
        assertEq(
            auction.startTime,
            0,
            "startTime after endAuction is not correct"
        );
    }

    function testEndAuctionWithNoBids() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");

        skip(auction.endOfBiddingPeriod);

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);

        assertEq(owner, SELLER, "owner is not seller");

        auction = vAuction.getAuction(auctionParams.itemId); // auction is not updated after endAuction

        assertEq(
            auction.startTime,
            0,
            "startTime after endAuction is not correct"
        );
    }

    function testEndAuctionWithNoHighestBid() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 2;
        auctionParams.reservePrice = 2;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce1 = bytes32("123");
        uint96 bidValue1 = auctionParams.reservePrice;
        bytes20 commitment1 = getCommitment(nonce1, bidValue1, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue1}(auctionParams.itemId, commitment1);

        bytes32 nonce2 = bytes32("1234");
        uint96 bidValue2 = auctionParams.reservePrice - 1;
        bytes20 commitment2 = getCommitment(nonce2, bidValue2, auctionIndex);

        vm.prank(BUYER2);
        vAuction.commitBid{value: bidValue2}(auctionParams.itemId, commitment2);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 2, "numUnrevealedBids is not 1");

        skip(auction.endOfBiddingPeriod);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue1, nonce1);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");
        assertEq(
            auction.highestBid,
            auctionParams.reservePrice,
            "highestBid is not correct"
        );
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
        assertEq(
            auction.highestBidder,
            address(0),
            "highestBidder is not correct"
        );

        vm.prank(BUYER2);
        vAuction.revealBid(auctionParams.itemId, bidValue2, nonce2);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(
            auction.highestBid,
            auctionParams.reservePrice,
            "highestBid is not correct"
        );
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
        assertEq(
            auction.highestBidder,
            address(0),
            "highestBidder is not correct"
        );

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);

        assertEq(owner, SELLER, "owner is not seller");

        auction = vAuction.getAuction(auctionParams.itemId); // auction is not updated after endAuction

        assertEq(
            auction.startTime,
            0,
            "startTime after endAuction is not correct"
        );
    }

    function testEndAuctionWithHighestBid() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 2;
        auctionParams.reservePrice = 2;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 1, "numUnrevealedBids is not 1");

        skip(auction.endOfBiddingPeriod);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        auction = vAuction.getAuction(auctionParams.itemId);
        assertEq(auction.numUnrevealedBids, 0, "numUnrevealedBids is not 0");
        assertEq(auction.highestBid, bidValue, "highestBid is not correct");
        assertEq(
            auction.secondHighestBid,
            auctionParams.reservePrice,
            "secondHighestBid is not correct"
        );
        assertEq(auction.highestBidder, BUYER1, "highestBidder is not correct");

        skip(auction.endOfRevealPeriod);

        uint256 sellerBalance = address(SELLER).balance;
        uint256 vAuctionBalance = address(vAuction).balance;

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);
        assertEq(owner, BUYER1, "owner is not buyer1");
        assertEq(
            address(SELLER).balance,
            sellerBalance + bidValue,
            "seller balance is not correct"
        );
        assertEq(
            address(vAuction).balance,
            vAuctionBalance - bidValue,
            "vAuction balance is not correct"
        );

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );
        assertEq(bidCommitment, BID_REVEALED, "commitment is not correct");
        assertEq(bidCollateral, 0, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId); // auction is not updated after endAuction

        assertEq(
            auction.startTime,
            0,
            "startTime after endAuction is not correct"
        );
    }

    function testEndAuctionWithHighestBidExcessCollateral() public {
        auctionParams.bidPeriod = 1;
        auctionParams.revealPeriod = 2;
        auctionParams.reservePrice = 2;
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue + 1}(
            auctionParams.itemId,
            commitment
        );

        skip(auction.endOfBiddingPeriod);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        skip(auction.endOfRevealPeriod);

        uint256 sellerBalance = address(SELLER).balance;
        uint256 buyer1Balance = address(BUYER1).balance;

        vm.prank(SELLER);
        address owner = vAuction.endAuction(auctionParams.itemId);

        assertEq(owner, BUYER1, "owner is not buyer1");
        assertEq(
            address(SELLER).balance,
            sellerBalance + bidValue,
            "seller balance is not correct"
        );
        assertEq(
            address(BUYER1).balance,
            buyer1Balance + 1,
            "Excess was not transferred: Buyer1 balance is not correct"
        );

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex,
            BUYER1
        );

        assertEq(bidCommitment, BID_REVEALED, "commitment is not correct");
        assertEq(bidCollateral, 0, "collateral is not correct");

        auction = vAuction.getAuction(auctionParams.itemId); // auction is not updated after endAuction

        assertEq(
            auction.startTime,
            0,
            "startTime after endAuction is not correct"
        );
    }

    function testWithdrawCollateralCannotBeDoneWithoutCommitingBid() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        vm.expectRevert(
            VickreyAuction.VA__WITHDRAW_COLLATERAL_BID_NOT_REVEALED.selector
        );
        vAuction.withdrawCollateral(auctionParams.itemId, auction.index);
    }

    function testWithdrawCollateralCannotBeDoneWithoutRevealingBid() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );
        uint64 auctionIndex = auction.index;

        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);
        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auction.endOfBiddingPeriod);

        vm.prank(BUYER1);
        vm.expectRevert(
            VickreyAuction.VA__WITHDRAW_COLLATERAL_BID_NOT_REVEALED.selector
        );
        vAuction.withdrawCollateral(auctionParams.itemId, auctionIndex);
    }

    function testWithdrawCollateralCannotBeDoneWithHighestBidder() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice + 1;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);
        vm.prank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auction.endOfBiddingPeriod);

        vm.prank(BUYER1);
        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        vm.prank(BUYER1);
        vm.expectRevert(
            VickreyAuction
                .VA__WITHDRAW_COLLATERAL_BID_IS_HIGHEST_BIDDER
                .selector
        );
        vAuction.withdrawCollateral(auctionParams.itemId, auctionIndex);
    }

    function testWithdrawCollateralCannotBeDoneTwice() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex);

        vm.startPrank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auction.endOfBiddingPeriod);

        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        vAuction.withdrawCollateral(auctionParams.itemId, auctionIndex);

        vm.expectRevert(
            VickreyAuction.VA__WITHDRAW_COLLATERAL_IS_ZERO.selector
        );
        vAuction.withdrawCollateral(auctionParams.itemId, auctionIndex);
    }

    function testWithdrawCollateral() public {
        createAuction(SELLER);

        VickreyAuction.Auction memory auction = vAuction.getAuction(
            auctionParams.itemId
        );

        uint64 auctionIndex1 = auction.index;
        bytes32 nonce = bytes32("123");
        uint96 bidValue = auctionParams.reservePrice;
        bytes20 commitment = getCommitment(nonce, bidValue, auctionIndex1);

        vm.startPrank(BUYER1);
        vAuction.commitBid{value: bidValue}(auctionParams.itemId, commitment);

        skip(auction.endOfBiddingPeriod);

        vAuction.revealBid(auctionParams.itemId, bidValue, nonce);

        uint256 buyer1Balance = address(BUYER1).balance;
        uint256 vAuctionBalance = address(vAuction).balance;

        vAuction.withdrawCollateral(auctionParams.itemId, auctionIndex1);
        assertEq(
            address(BUYER1).balance,
            buyer1Balance + bidValue,
            "buyer1 balance is not correct"
        );
        assertEq(
            address(vAuction).balance,
            vAuctionBalance - bidValue,
            "vAuction balance is not correct"
        );

        (bytes20 bidCommitment, uint96 bidCollateral) = vAuction.bids(
            auctionParams.itemId,
            auctionIndex1,
            BUYER1
        );
        assertEq(bidCommitment, BID_REVEALED, "commitment is not correct");
        assertEq(bidCollateral, 0, "collateral is not correct");
    }
}
