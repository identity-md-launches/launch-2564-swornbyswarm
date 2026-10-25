// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title swornbyswarm (SWORN)
/// @notice A plain, fixed-supply ERC-20. The whole supply of 1,000,000,000 SWORN (18 decimals) is
/// minted once, in the constructor, to the deployer. There is no owner, no mint path, no pause,
/// no blocklist, no tax and no burn hook: every transfer moves exactly the amount asked for.
/// @dev Deployed by the IMD ProjectFactory, so `msg.sender` at construction is the factory, which
/// then pays the supply out (swarm share, pool seed, requester remainder). The contract takes no
/// constructor arguments and makes no external calls, so it deploys on an empty chain.
///
/// Project links:
///   X:       x.com/swornbyswarm
///   Website: swornbyswarm.sites.imd.fun
contract SwornToken is ERC20 {
    /// @notice ERC-20 name.
    string public constant TOKEN_NAME = "swornbyswarm";

    /// @notice ERC-20 symbol.
    string public constant TOKEN_SYMBOL = "SWORN";

    /// @notice Number of decimals, the ERC-20 default.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice Whole supply in minor units: 1,000,000,000 * 10^18. Minted once; nothing can mint more.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice The project's X (Twitter) page, as given in the brief.
    string public constant X_URL = "x.com/swornbyswarm";

    /// @notice The project's website, as given in the brief.
    string public constant WEBSITE_URL = "swornbyswarm.sites.imd.fun";

    /// @notice Emitted once, at deployment, with the address that received the whole supply.
    event SupplyMinted(address indexed to, uint256 amount);

    /// @notice Mints the whole fixed supply to the deployer (`msg.sender`).
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}
