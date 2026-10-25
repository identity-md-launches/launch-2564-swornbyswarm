// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SwornToken} from "../src/SwornToken.sol";

/// @title Deploy script for SwornToken
/// @notice Reference only. On IMD the ProjectFactory deploys the token from its bytecode through
/// `launchCustom`; this script exists so the deployment can be rehearsed on a local chain and so
/// the tests can exercise the exact deployment path (`deploy()`) without any environment variables.
contract DeploySwornToken is Script {
    /// @notice Deploys the token. The caller of this function becomes the holder of the whole supply.
    /// @dev No configuration: the token takes no constructor arguments.
    function deploy() public returns (SwornToken token) {
        token = new SwornToken();
    }

    /// @notice Broadcast entry point for a manual rehearsal (`forge script ... --broadcast`).
    /// @dev Uses the broadcaster forge is given on the command line. Reads no environment variables.
    function run() external returns (SwornToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
