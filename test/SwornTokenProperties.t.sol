// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornToken} from "src/SwornToken.sol";

/// @notice Boundary and algebraic properties complementing the existing launch tests.
/// forge-config: default.fuzz.runs = 1000
contract SwornTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    SwornToken private token;
    address private deployer;
    address private holder;
    address private spender;
    address private recipient;

    function setUp() public {
        deployer = makeAddr("properties deployer");
        holder = makeAddr("properties holder");
        spender = makeAddr("properties spender");
        recipient = makeAddr("properties recipient");
        vm.prank(deployer);
        token = new SwornToken();
    }

    function test_oneWeiAndFullSupplyCanMoveAndReturn() public {
        _fund(1);
        assertEq(token.balanceOf(holder), 1);
        vm.prank(holder);
        assertTrue(token.transfer(deployer, 1));
        assertEq(token.balanceOf(deployer), SUPPLY);

        _fund(SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyDelegatedTransferExhaustsAllowance() public {
        _fund(SUPPLY);
        _approve(SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        _assertState(0, SUPPLY, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function test_approvalReplacementAndRevocationEmitAndTakeEffect() public {
        _fund(100);
        _approve(50);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(holder, spender, 7);
        _approve(7);
        _assertState(100, 0, 7);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(holder, spender, 0);
        _approve(0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        _assertState(100, 0, 0);
    }

    function test_infiniteAllowanceCanBeReplacedAndRevoked() public {
        _fund(10);
        _approve(type(uint256).max);
        _approve(7);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        _assertState(9, 1, 6);
        _approve(type(uint256).max);
        _approve(0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        _assertState(9, 1, 0);
    }

    function test_maximumFiniteAllowanceIsNotInfinite() public {
        _fund(1);
        _approve(type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        _assertState(0, 1, type(uint256).max - 2);
    }

    function test_allowancesAreScopedToBothOwnerAndSpender() public {
        _fund(100);
        _approve(30);
        _reject(
            recipient,
            abi.encodeCall(token.transferFrom, (holder, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, recipient, 0, 1)
        );
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (deployer, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        assertEq(token.allowance(spender, holder), 0);
        assertEq(token.allowance(holder, recipient), 0);
        _assertState(100, 0, 30);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingTokens() public {
        _fund(50);
        _approve(50);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, holder, 50);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, 50));
        _assertState(50, 0, 0);
    }

    function test_holderCallingTransferFromStillNeedsSelfApproval() public {
        _fund(1);
        _reject(
            holder,
            abi.encodeCall(token.transferFrom, (holder, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1)
        );
        vm.prank(holder);
        assertTrue(token.approve(holder, 1));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        _assertState(0, 1, 0);
    }

    function test_zeroTransfersEmitWithoutBalanceOrAllowance() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 0));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroRecipientRejectedEvenForZeroAmount() public {
        _reject(
            holder,
            abi.encodeCall(token.transfer, (address(0), 0)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, address(0), 0)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function test_zeroSpenderRejectedEvenForZeroApproval() public {
        _reject(
            holder,
            abi.encodeCall(token.approve, (address(0), 0)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function test_failedTransferFromToZeroRestoresFiniteAllowance() public {
        _fund(10);
        _approve(10);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, address(0), 10)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        _assertState(10, 0, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 10));
        _assertState(0, 10, 0);
    }

    function test_failedTransferFromAboveBalanceRestoresAllowanceAndCanBeRetried() public {
        _fund(5);
        _approve(6);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, 6)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 5, 6)
        );
        _fund(1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 6));
        _assertState(0, 6, 0);
    }

    function test_selfTransferCannotBypassBalanceCheck() public {
        _fund(1);
        _reject(
            holder,
            abi.encodeCall(token.transfer, (holder, 2)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2)
        );
        _approve(2);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, holder, 2)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2)
        );
    }

    function test_maximumTransferFailsWithoutArithmeticPanicOrStateChange() public {
        _fund(SUPPLY);
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max);
        _reject(holder, abi.encodeCall(token.transfer, (recipient, type(uint256).max)), errorData);
        _approve(type(uint256).max);
        _reject(spender, abi.encodeCall(token.transferFrom, (holder, recipient, type(uint256).max)), errorData);
        _assertState(SUPPLY, 0, type(uint256).max);
    }

    function testFuzz_transferRoundTripRestoresEveryBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        _fund(SUPPLY);
        _approve(type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(_stateDigest(), beforeState, "round trip created or lost value");
    }

    function testFuzz_splitDelegatedSpendingEqualsOneTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        _fund(SUPPLY);
        _approve(first + second);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        _assertState(SUPPLY - first, first, second);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, second));
        _assertState(SUPPLY - first - second, first + second, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function testFuzz_approvalReplacementIsIdempotent(uint256 original, uint256 replacement) public {
        _fund(SUPPLY);
        _approve(original);
        _approve(replacement);
        _assertState(SUPPLY, 0, replacement);
        bytes32 beforeState = _stateDigest();
        _approve(replacement);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_failedDelegatedOverdraftPreservesAllState(uint256 held, uint256 requested, bool infinite) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max);
        _fund(held);
        uint256 approval = infinite ? type(uint256).max : requested;
        _approve(approval);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, requested)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, held, requested)
        );
        _assertState(held, 0, approval);
    }

    function testFuzz_insufficientAllowancePreservesAllState(uint256 allowed, uint256 requested) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        requested = bound(requested, allowed + 1, SUPPLY);
        _fund(SUPPLY);
        _approve(allowed);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (holder, recipient, requested)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, requested)
        );
        _assertState(SUPPLY, 0, allowed);
    }

    function testFuzz_delegatedSelfTransferOnlyChangesFiniteAllowance(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        _fund(SUPPLY);
        _approve(allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        _assertState(SUPPLY, 0, allowed == type(uint256).max ? allowed : allowed - amount);
    }

    function testFuzz_infiniteAllowanceSurvivesRepeatedSpends(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        _fund(SUPPLY);
        _approve(type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        _assertState(SUPPLY - first, first, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, second));
        _assertState(SUPPLY - first - second, first + second, type(uint256).max);
    }

    function _fund(uint256 amount) private {
        vm.prank(deployer);
        assertTrue(token.transfer(holder, amount));
    }

    function _approve(uint256 amount) private {
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
    }

    function _assertState(uint256 held, uint256 received, uint256 allowed) private view {
        assertEq(token.balanceOf(holder), held);
        assertEq(token.balanceOf(recipient), received);
        assertEq(token.balanceOf(deployer), SUPPLY - held - received);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(holder, spender), allowed);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Check both the precise error and atomicity; a generic revert could hide a panic.
    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        bytes32 beforeState = _stateDigest();
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected revert data");
        assertEq(_stateDigest(), beforeState, "rejected operation changed state");
    }

    function _stateDigest() private view returns (bytes32) {
        address[5] memory accounts = [deployer, holder, spender, recipient, address(0)];
        bytes memory state = abi.encode(token.totalSupply());
        for (uint256 i; i < accounts.length; ++i) {
            state = abi.encode(state, token.balanceOf(accounts[i]));
            for (uint256 j; j < accounts.length; ++j) {
                state = abi.encode(state, token.allowance(accounts[i], accounts[j]));
            }
        }
        return keccak256(state);
    }
}
