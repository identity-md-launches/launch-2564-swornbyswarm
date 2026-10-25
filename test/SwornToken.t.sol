// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornToken} from "../src/SwornToken.sol";
import {DeploySwornToken} from "../script/DeploySwornToken.s.sol";

/// @notice Stands in for the ProjectFactory: deploys the token so that `msg.sender` in the
/// constructor is a contract, exactly as at launch, and then pays the supply out on command.
contract FactoryStub {
    SwornToken public token;

    function deployToken() external returns (SwornToken) {
        token = new SwornToken();
        return token;
    }

    function pay(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract SwornTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    FactoryStub internal factory;
    SwornToken internal token;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL = address(0x9001);
    address internal constant REQUESTER = address(0xEE2aaA315cf7eD169f93148D30D24Af9318dBb66);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant STRANGER = address(0xBEEF);

    function setUp() public {
        factory = new FactoryStub();
        token = factory.deployToken();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "swornbyswarm");
        assertEq(token.symbol(), "SWORN");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "swornbyswarm");
        assertEq(token.TOKEN_SYMBOL(), "SWORN");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_projectLinks() public view {
        assertEq(token.X_URL(), "x.com/swornbyswarm");
        assertEq(token.WEBSITE_URL(), "swornbyswarm.sites.imd.fun");
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.balanceOf(address(factory)), SUPPLY, "deployer does not hold the whole supply");
        assertEq(token.balanceOf(address(this)), 0, "the test harness received tokens it should not have");
    }

    function test_constructorEmitsTransferAndSupplyMinted() public {
        address deployer = address(0xDE91);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), deployer, SUPPLY);
        vm.expectEmit(true, false, false, true);
        emit SwornToken.SupplyMinted(deployer, SUPPLY);
        vm.prank(deployer);
        SwornToken fresh = new SwornToken();
        assertEq(fresh.balanceOf(deployer), SUPPLY);
    }

    function test_deployScriptMintsToItsCaller() public {
        DeploySwornToken script = new DeploySwornToken();
        SwornToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY, "the script's caller is the deployer");
        assertEq(deployed.name(), "swornbyswarm");
        assertEq(deployed.symbol(), "SWORN");
    }

    // ---------------------------------------------------------------- launch flows

    /// @dev The factory pays the swarm share, seeds the pool and forwards the remainder. Every leg
    /// must arrive whole: nothing is taxed, burned or held back on any transfer.
    function test_launchFlowsArriveWhole() public {
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 7_000 / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(factory.pay(DISTRIBUTOR, swarm));
        assertTrue(factory.pay(POOL, pool));
        assertTrue(factory.pay(REQUESTER, remainder));

        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "swarm share arrived short");
        assertEq(token.balanceOf(POOL), pool, "pool seed arrived short");
        assertEq(token.balanceOf(REQUESTER), remainder, "remainder arrived short");
        assertEq(token.balanceOf(address(factory)), 0, "factory kept something back");
        assertEq(token.totalSupply(), SUPPLY, "launch flows changed the supply");

        // A claimant then receives the whole claim from the distributor.
        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(ALICE, swarm));
        assertEq(token.balanceOf(ALICE), swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
    }

    // ---------------------------------------------------------------- transfer: success

    function test_transferMovesExactAmountAndEmits() public {
        factory.pay(ALICE, 1_000 ether);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(ALICE, BOB, 400 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 400 ether));

        assertEq(token.balanceOf(ALICE), 600 ether);
        assertEq(token.balanceOf(BOB), 400 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        factory.pay(ALICE, 10 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(ALICE, 10 ether));
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_approveAndTransferFrom() public {
        factory.pay(ALICE, 100 ether);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(ALICE, BOB, 60 ether);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 60 ether));
        assertEq(token.allowance(ALICE, BOB), 60 ether);

        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, STRANGER, 45 ether));

        assertEq(token.balanceOf(ALICE), 55 ether);
        assertEq(token.balanceOf(STRANGER), 45 ether);
        assertEq(token.allowance(ALICE, BOB), 15 ether, "allowance not reduced by the spent amount");
    }

    function test_infiniteAllowanceIsNotReduced() public {
        factory.pay(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 40 ether));
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
        assertEq(token.balanceOf(BOB), 40 ether);
    }

    // ---------------------------------------------------------------- transfer: failure

    function test_transferRevertsOnInsufficientBalance() public {
        factory.pay(ALICE, 10 ether);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10 ether, 11 ether)
        );
        _reverted(token.transfer(BOB, 11 ether));
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromStrangerWithNothingReverts() public {
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, STRANGER, 0, 1));
        _reverted(token.transfer(BOB, 1));
    }

    function test_transferToZeroAddressReverts() public {
        factory.pay(ALICE, 1 ether);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        _reverted(token.transfer(address(0), 1 ether));
    }

    function test_approveZeroSpenderReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        factory.pay(ALICE, 100 ether);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1 ether));
        _reverted(token.transferFrom(ALICE, BOB, 1 ether));
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function test_transferFromAboveAllowanceReverts() public {
        factory.pay(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 10 ether, 11 ether)
        );
        _reverted(token.transferFrom(ALICE, BOB, 11 ether));
        assertEq(token.allowance(ALICE, BOB), 10 ether);
    }

    function test_transferFromAboveBalanceRevertsEvenWithAllowance() public {
        factory.pay(ALICE, 5 ether);
        vm.prank(ALICE);
        token.approve(BOB, 100 ether);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5 ether, 6 ether));
        _reverted(token.transferFrom(ALICE, BOB, 6 ether));
    }

    /// @dev Even the deployer cannot pull a holder's balance without an allowance.
    function test_deployerCannotPullFromHolder() public {
        factory.pay(ALICE, 50 ether);
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        _reverted(token.transferFrom(ALICE, address(factory), 1));
        assertEq(token.balanceOf(ALICE), 50 ether);
    }

    // ---------------------------------------------------------------- no privileged surface

    /// @dev Neither a stranger nor the deployer reaches any call that would grow the supply.
    function test_noCallIncreasesSupply() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], STRANGER, type(uint128).max);
            vm.prank(STRANGER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(factory));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(STRANGER), 0, signatures[i]);
        }
    }

    /// @dev No pause, blocklist, freeze or seizure exists: the holder keeps and can move its balance.
    function test_noCallMovesOrFreezesAHolder() public {
        factory.pay(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            vm.prank(address(factory));
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, true));
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.balanceOf(ALICE), held);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2));
        assertEq(token.balanceOf(BOB), held / 2);
    }

    function test_tokenRejectsEther() public {
        vm.deal(STRANGER, 1 ether);
        vm.prank(STRANGER);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token accepted ether");
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------- bytecode properties

    function test_runtimeFitsAndHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- helpers

    /// @dev Wraps a call that `vm.expectRevert` has armed. Forge turns the caught revert into an
    /// empty success return, so the decoded bool is false; the wrapper only exists so the linter
    /// sees the return value consumed.
    function _reverted(bool ok) internal pure {
        ok;
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(factory));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(factory.pay(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(factory)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, SUPPLY);
        factory.pay(ALICE, held);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, attempt));
        _reverted(token.transfer(BOB, attempt));
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spend) public {
        allowed = bound(allowed, 0, SUPPLY);
        spend = bound(spend, 0, SUPPLY);
        factory.pay(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        if (spend > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowed, spend)
            );
            _reverted(token.transferFrom(ALICE, STRANGER, spend));
        } else {
            assertTrue(token.transferFrom(ALICE, STRANGER, spend));
            assertEq(token.balanceOf(STRANGER), spend);
            assertEq(token.allowance(ALICE, BOB), allowed - spend);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
