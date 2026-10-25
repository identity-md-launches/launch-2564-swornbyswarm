// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornToken} from "src/SwornToken.sol";

/// @notice A closed set of holders drives the real public API; no token storage is patched.
/// @dev Ghosts describe the requested operations, never copy the token's observed results.
/// Self-transfers and owner == spender are deliberately allowed. The deployer is also an actor.
contract SwornTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 5;

    SwornToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = address(this);
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        actors[4] = makeAddr("invariant dave");
        token = new SwornToken();
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        expectedBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            _transfer(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
        // Seed a ring of finite approvals so delegated calls are useful from the first step.
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            _approve(actors[i], actors[(i + 1) % ACTOR_COUNT], SUPPLY / 10);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), bound(amountSeed, 0, expectedBalance[from]));
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance[from]);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 kind) external {
        uint256 amount;
        if (kind % 4 == 1) amount = type(uint256).max;
        else if (kind % 4 == 2) amount = type(uint256).max - 1;
        else if (kind % 4 == 3) amount = bound(amountSeed, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
    }

    function revokeAndAttemptPull(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _approve(owner, spender, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function rejectOverdraft(uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        _reject(
            owner,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
        );
    }

    function rejectDelegatedOverdraft(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
        );
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 allowedSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = bound(allowedSeed, 0, SUPPLY);
        _approve(owner, spender, allowed);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), allowed + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        bytes memory errorData = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            address spender = _actor(spenderSeed);
            _approve(owner, spender, amount);
            _reject(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), errorData);
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), errorData);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Expected failures are caught explicitly. Unexpected errors and assertion failures
    /// must fail the campaign (fail_on_revert = true). Ghosts remain unchanged on failure,
    /// so the invariants also verify that rejected calls did not consume allowances or balances.
    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected revert data");
    }
}

/// @notice Conservation, authorization and transfer liveness over random call sequences.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SwornTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SwornTokenHandler private handler;
    SwornToken private token;

    function setUp() public {
        handler = new SwornTokenHandler();
        token = handler.token();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.revokeAndAttemptPull.selector;
        selectors[5] = handler.rejectOverdraft.selector;
        selectors[6] = handler.rejectDelegatedOverdraft.selector;
        selectors[7] = handler.rejectOverAllowance.selector;
        selectors[8] = handler.rejectZeroRecipient.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev The fixed supply promise and the closed actor set make this an exact identity.
    function invariant_supplyIsFixedAndBalancesConserved() public view {
        uint256 totalBalances;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            totalBalances += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after deployment");
        assertEq(totalBalances, SUPPLY, "tokens were created, lost, taxed or sent outside the actors");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(token)), 0, "token retained an unexpected fee");
    }

    /// @dev Conservation alone would miss taking value from the wrong holder.
    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            assertEq(
                token.balanceOf(actor), handler.expectedBalance(actor), "holder balance differs from requested moves"
            );
        }
    }

    /// @dev All pairs are checked, including untouched pairs and self-approvals.
    function invariant_allowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance changed without authorization or was consumed incorrectly"
                );
            }
        }
    }

    /// @dev After every campaign run, each holder can still move its entire balance.
    /// Approvals, revocations and rejected calls must never freeze a holder's tokens.
    function afterInvariant() public {
        for (uint256 i = 1; i < handler.ACTOR_COUNT(); ++i) {
            handler.transferAll(i, 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_supplyIsFixedAndBalancesConserved();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allowancesMatchApprovalsAndSpending();
    }

    /// @dev Deterministic sequence pins nonzero successful spends, revocation and every rejection
    /// handler, independent of which selectors a particular random campaign happens to choose.
    function test_handlerSequenceExercisesSuccessAndFailurePaths() public {
        handler.transfer(0, 1, 1);
        handler.approve(1, 2, 10, 3);
        handler.transferFrom(1, 2, 3, 10);
        handler.approve(1, 2, 0, 1);
        handler.transferFrom(1, 2, 1, 1);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
        handler.revokeAndAttemptPull(1, 2, 3);
        handler.rejectOverdraft(1, 1, type(uint256).max);
        handler.rejectDelegatedOverdraft(1, 2, 3, type(uint256).max, false);
        handler.rejectDelegatedOverdraft(1, 2, 3, type(uint256).max, true);
        handler.rejectOverAllowance(1, 2, 3, 1);
        handler.rejectZeroRecipient(1, 2, 1, false);
        handler.rejectZeroRecipient(1, 2, 1, true);
        handler.rejectZeroSpender(1, type(uint256).max);
        invariant_supplyIsFixedAndBalancesConserved();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allowancesMatchApprovalsAndSpending();
        afterInvariant();
    }
}
