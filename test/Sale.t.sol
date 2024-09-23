// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Sale.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

contract MockToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("MockToken", "MTK") {
        _mint(msg.sender, initialSupply);
    }
}

contract SaleTest is Test {
    PublicSale public sale;
    MockToken public token;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant TO_SELL = 1_000_000 * 1e18;
    uint256 public constant SOFT_CAP = 100 ether;
    uint256 public constant HARD_CAP = 200 ether;
    uint256 public constant DURATION = 7 days;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        token = new MockToken(INITIAL_SUPPLY);

        sale = new PublicSale(address(token), TO_SELL, SOFT_CAP, HARD_CAP, DURATION);

        token.transfer(address(sale), INITIAL_SUPPLY);

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
    }
    
    /// @notice Tests the initial state of the PublicSale contract after deployment
    /// @dev Verifies correct token address, soft cap, hard cap, sale end time, and initial state
    function testInitialState() public {
        assertEq(sale.TOKEN(), address(token));
        assertEq(sale.SOFT_CAP(), SOFT_CAP);
        assertEq(sale.HARD_CAP(), HARD_CAP);
        assertEq(sale.SALE_END(), block.timestamp + DURATION);
        assertEq(sale.totalRaised(), 0);
        assertFalse(sale.saleEnded());
    }

    /// @notice Tests the contribution functionality of the PublicSale contract
    /// @dev Verifies that a user can contribute ETH and that the contract state updates correctly
    function testContribute() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 50 ether}("");
        assertTrue(success);

        // Contribution is the raised amount
        assertEq(sale.totalRaised(), 50 ether);
        // User's contribution has been added
        assertEq(getContribution(user1), 50 ether);
    }

    /// @notice Tests that contributions fail after the sale end time
    /// @dev Attempts to contribute after the sale duration and expects the transaction to revert
    function testFailContributeFailsAfterEndTime() public {
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(user1);
        vm.expectRevert();
        (bool success, ) = address(sale).call{value: 50 ether}("");
        // User couldn't contribute after sale ended
        assertFalse(success);
    }

    /// @notice Tests the endSale function of the PublicSale contract
    /// @dev Verifies that the sale can be ended after the duration has passed
    function testEndSale() public {
        vm.warp(block.timestamp + DURATION);
        sale.endSale();
        // Sale is ended
        assertTrue(sale.saleEnded());
    }

    /// @notice Tests that ending the sale fails before the end time
    /// @dev Attempts to end the sale before the duration has passed and expects it to revert
    function testFailSaleFailsBeforeEndTime() public {
        vm.warp(block.timestamp + DURATION - 1);
        // Reverts because sale is not ended
        vm.expectRevert();
        sale.endSale();
    }

    /// @notice Tests the refund claim process when the soft cap is not reached
    /// @dev Simulates contributions below the soft cap and verifies correct refunds after sale ends
    /// @param contribution1 Fuzzy input for the first user's contribution
    /// @param contribution2 Fuzzy input for the second user's contribution
    function testClaimRefundWhenSoftCapNotReached(uint256 contribution1, uint256 contribution2) public {
        // Ensure the total contribution is less than SOFT_CAP
        uint256 maxTotalContribution = SOFT_CAP - 2; // Subtract 2 to ensure room for both contributions
    
        // Bound contribution1 between 1 and maxTotalContribution - 1
        contribution1 = bound(contribution1, 1, maxTotalContribution - 1);
    
        // Bound contribution2 between 1 and the remaining amount
        contribution2 = bound(contribution2, 1, maxTotalContribution - contribution1);

        // Ensure contributions don't exceed user balances
        contribution1 = bound(contribution1, 1, user1.balance);
        contribution2 = bound(contribution2, 1, user2.balance);
        
        vm.prank(user1);
        (bool success1, ) = address(sale).call{value: contribution1}("");
        assertTrue(success1);

        vm.prank(user2);
        (bool success2, ) = address(sale).call{value: contribution2}("");
        assertTrue(success2);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        vm.prank(user1);
        sale.claim();

        vm.prank(user2);
        sale.claim();

        // User1 got refunded of their ETH
        assertEq(user1.balance, user1BalanceBefore + contribution1);
        // User1 has claimed
        assertTrue(getHasClaimed(user1));
        // User2 got refunded of their ETH
        assertEq(user2.balance, user2BalanceBefore + contribution2);
        // User2 has claimed
        assertTrue(getHasClaimed(user2));
    }

    /// @notice Tests the token claim process when the soft cap is reached
    /// @dev Simulates contributions between soft cap and hard cap and verifies correct token distribution
    /// @param contribution1 Fuzzy input for the first user's contribution
    /// @param contribution2 Fuzzy input for the second user's contribution
    function testClaimTokensWhenSoftCapReached(uint256 contribution1, uint256 contribution2) public {
        // Ensure the total contribution is between SOFT_CAP and HARD_CAP
        uint256 maxTotalContribution = HARD_CAP;

        // Bound contribution1 between SOFT_CAP and maxTotalContribution - 1
        contribution1 = bound(contribution1, SOFT_CAP, maxTotalContribution - 1);

        // Bound contribution2 between 1 and the remaining amount
        contribution2 = bound(contribution2, 1, maxTotalContribution - contribution1);

        // Ensure contributions don't exceed user balances
        contribution1 = bound(contribution1, SOFT_CAP, user1.balance);
        contribution2 = bound(contribution2, 1, user2.balance);

        vm.prank(user1);
        (bool success1, ) = address(sale).call{value: contribution1}("");
        assertTrue(success1);

        vm.prank(user2);
        (bool success2, ) = address(sale).call{value: contribution2}("");
        assertTrue(success2);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        vm.prank(user1);
        sale.claim();

        vm.prank(user2);
        sale.claim();

        // User1 received their share of tokens (allow for small rounding error)
        uint256 expectedTokens1 = (contribution1 * sale.TO_SELL()) / sale.totalRaised();
        uint256 actualTokens1 = token.balanceOf(user1);
        assertApproxEqAbs(actualTokens1, expectedTokens1, 1e6);

        // User1's ETH balance is unchanged
        assertEq(user1.balance, user1BalanceBefore);
        // User1 has claimed
        assertTrue(getHasClaimed(user1));

        // User2 received their share of tokens (allow for small rounding error)
        uint256 expectedTokens2 = (contribution2 * sale.TO_SELL()) / sale.totalRaised();
        uint256 actualTokens2 = token.balanceOf(user2);
        assertApproxEqAbs(actualTokens2, expectedTokens2, 1e6);

        // User2's ETH balance is unchanged
        assertEq(user2.balance, user2BalanceBefore);
        // User2 has claimed
        assertTrue(getHasClaimed(user2));

        // Sale contract has no tokens left (or very small amount due to rounding)
        assertLe(token.balanceOf(address(sale)), 1e9);
    }

    /// @notice Tests the claim process when the sale is oversubscribed
    /// @dev Simulates contributions exceeding the hard cap and verifies correct token and ETH distribution
    /// @param totalContribution Fuzzy input for the total contribution amount
    /// @param split Fuzzy input to determine the split of contributions between two users
    function testClaimTokensAndRefundWhenOversubscribed(uint256 totalContribution, uint256 split) public {
        // Define the minimum and maximum total contributions
        uint256 minTotalContribution = HARD_CAP + 3;
        uint256 maxTotalContribution = (HARD_CAP * 2) - 1;

        // Bound totalContribution between minTotalContribution and maxTotalContribution
        totalContribution = bound(totalContribution, minTotalContribution, maxTotalContribution);

        // Bound split between 1 and 9999 (representing 0.01% to 99.99%)
        split = bound(split, 1, 9999);

        // Calculate contributions based on split percentage
        uint256 contribution1 = (totalContribution * split) / 10000;
        uint256 contribution2 = totalContribution - contribution1;

        // Ensure contributions are at least 1 wei and do not exceed user balances
        contribution1 = bound(contribution1, 1, user1.balance);
        contribution2 = bound(contribution2, 1, user2.balance);

        // Ensure totalContribution matches the sum of contributions
        vm.assume(contribution1 + contribution2 == totalContribution);

        console.log("contribution1", contribution1 / 1e15);
        console.log("contribution2", contribution2 / 1e15);
        console.log("totalContribution", totalContribution / 1e15);
        console.log("HARD_CAP", HARD_CAP / 1e15);

        // Assertions to verify our conditions
        assertTrue(totalContribution < HARD_CAP * 2, "Total contribution should be less than HARD_CAP * 2");
        assertTrue(totalContribution > HARD_CAP + 2, "Total contribution should be greater than HARD_CAP + 2");
        assertTrue(contribution1 <= user1.balance, "Contribution1 should not exceed user1 balance");
        assertTrue(contribution2 <= user2.balance, "Contribution2 should not exceed user2 balance");

        vm.prank(user1);
        (bool success1, ) = address(sale).call{value: contribution1}("");
        assertTrue(success1);

        vm.prank(user2);
        (bool success2, ) = address(sale).call{value: contribution2}("");
        assertTrue(success2);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        vm.prank(user1);
        sale.claim();

        vm.prank(user2);
        sale.claim();

        uint256 totalRefund = totalContribution - HARD_CAP;

        // User1 received their share of tokens (allow for small rounding error)
        uint256 expectedTokens1 = (contribution1 * sale.TO_SELL()) / totalContribution;
        uint256 actualTokens1 = token.balanceOf(user1);
        assertApproxEqAbs(actualTokens1, expectedTokens1, 1e6);

        // User1 has been refunded their excess ETH
        uint256 expectedRefund1 = (contribution1 * totalRefund) / totalContribution;
        assertApproxEqAbs(user1.balance, user1BalanceBefore + expectedRefund1, 1e6);

        // User2 received their share of tokens (allow for small rounding error)
        uint256 expectedTokens2 = (contribution2 * sale.TO_SELL()) / totalContribution;
        uint256 actualTokens2 = token.balanceOf(user2);
        assertApproxEqAbs(actualTokens2, expectedTokens2, 1e6);

        // User2 has been refunded their excess ETH
        uint256 expectedRefund2 = (contribution2 * totalRefund) / totalContribution;
        assertApproxEqAbs(user2.balance, user2BalanceBefore + expectedRefund2, 1e6);

        // Sale contract has no tokens left (or very small amount due to rounding)
        assertLe(token.balanceOf(address(sale)), 1e9);

        // Both users have claimed
        assertTrue(getHasClaimed(user1));
        assertTrue(getHasClaimed(user2));

        // Total tokens distributed should equal TO_SELL (allow for small rounding error)
        assertApproxEqAbs(actualTokens1 + actualTokens2, sale.TO_SELL(), 1e6);

        // Total ETH in contract should equal HARD_CAP (allow for small rounding error)
        assertApproxEqAbs(address(sale).balance, HARD_CAP, 1e6);
    }

    /// @notice Tests that users cannot claim twice
    /// @dev Simulates a contribution, claim, and then attempts a second claim which should fail
    function testCannotClaimTwice() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 5 ether}("");
        assertTrue(success, "Contribution failed");

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        // Claim first time
        sale.claim();

        vm.prank(user1);
        // Claim second time and fail
        vm.expectRevert();
        sale.claim();
    }

    /// @notice Tests that non-contributors cannot claim
    /// @dev Attempts to claim without contributing and expects it to revert
    function testCannotClaimIfNotContributed() public {
        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        // Cannot claim if not contributed
        vm.expectRevert();
        sale.claim();
    }






    // ***** UTILS *****
    function getContribution(address addr) public view returns (uint256) {
        bytes32 CONTRIB_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, addr)
            mstore(add(ptr, 0x20), 2)
            CONTRIB_SLOT := keccak256(ptr, 0x40)
        }
        return uint256(vm.load(address(sale), CONTRIB_SLOT));
    }

    function getHasClaimed(address addr) public view returns (bool) {
        bytes32 HAS_CLAIMED_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, addr)
            mstore(add(ptr, 0x20), 3)
            HAS_CLAIMED_SLOT := keccak256(ptr, 0x40)
        }
        return vm.load(address(sale), HAS_CLAIMED_SLOT) != bytes32(0);
    }

    receive() external payable {}
}
