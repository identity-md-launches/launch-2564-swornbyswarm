# swornbyswarm (SWORN)

A plain, fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum.

- **Name:** `swornbyswarm`
- **Symbol:** `SWORN`
- **Decimals:** 18
- **Total supply:** 1,000,000,000 SWORN = `1000000000000000000000000000` minor units, minted once in the
  constructor to the deployer (`msg.sender`). Nothing can mint afterwards.
- **Solidity contract name:** `SwornToken` (`src/SwornToken.sol`)
- **X:** x.com/swornbyswarm
- **Website:** swornbyswarm.sites.imd.fun

## What it does

`SwornToken` is OpenZeppelin's `ERC20` (v5.1.0, vendored) with the name, symbol, decimals and supply
fixed as constants and the whole supply minted to the deployer in the constructor. It adds nothing
else on purpose:

- no owner, admin, or role of any kind;
- no mint path after construction (supply can only ever shrink if a holder sends to a dead address);
- no pause, blocklist, freeze, lock, seizure or `burnFrom`;
- no tax, fee, reflection or burn on transfer: every transfer moves exactly the requested amount;
- no `selfdestruct`, `delegatecall` or proxy; no external calls in the constructor;
- no constructor arguments.

The two project links from the brief are exposed on chain as the string constants `X_URL` and
`WEBSITE_URL` so wallets and explorers can read them from the contract.

## Layout

```
foundry.toml                  solc 0.8.26 pinned, bytecode_hash = "none", optimizer on, no ffi / fs access
remappings.txt                forge-std/ and @openzeppelin/contracts/ point into lib/
src/SwornToken.sol            the token
script/DeploySwornToken.s.sol reference deploy script (deploy() is what the tests call)
test/SwornToken.t.sol         unit, failure, launch-flow, privilege-surface, bytecode and fuzz tests
lib/forge-std/                forge-std v1.9.7 (sources only, vendored as ordinary files)
lib/openzeppelin-contracts/   the ERC20 subset of OpenZeppelin Contracts v5.1.0 (ERC20, IERC20,
                              IERC20Metadata, Context, draft-IERC6093) plus its LICENSE
```

All dependencies are committed as ordinary files; there are no git submodules and the build needs
no network beyond the solc 0.8.26 binary that the verifier carries offline.

## Build and test

```
forge build
forge test
forge fmt --check
```

The fuzz tests were run with the verifier's seed:

```
FOUNDRY_FUZZ_SEED=0x9dd505c8b4a697aad8a5cfb223a07062917cbc703a23a9dcad85ed1ec30e49cc forge test
```

Tests read no environment variables, do not depend on the calling address, and pass in any order and in
parallel.

### What the tests cover

- metadata (`name`, `symbol`, `decimals`) and the exact supply constant;
- the whole supply is minted to the deployer, with `Transfer(0x0, deployer, supply)` and
  `SupplyMinted` emitted; the deploy script's `deploy()` behaves the same;
- the launch flows from the factory's point of view: 10% to the distributor, 70% to the pool, 20% to
  the requester, and a claim from the distributor, each arriving whole with supply unchanged;
- transfer and `transferFrom` success paths, allowance accounting, infinite allowance behaviour;
- failures: insufficient balance, zero-address receiver, zero-address spender, missing or insufficient
  allowance, balance shortfall despite allowance, and the deployer trying to pull from a holder;
- the privilege surface: twenty-two common mint/pause/blocklist/freeze/seize/upgrade selectors all
  revert for both a stranger and the deployer, with supply and holder balances unchanged;
- the token rejects ether; the runtime is under the EIP-170 limit and contains no reachable
  `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`;
- fuzz: transfers conserve supply, transfers above balance revert with the exact error, and
  `transferFrom` respects the allowance across the whole range.

## Deployment parameters

The token takes **no constructor arguments**. The IMD ProjectFactory deploys it through
`launchCustom`, so `msg.sender` in the constructor is the factory, which receives the entire supply
and pays it out.

| Manifest field       | Value                                               |
|----------------------|-----------------------------------------------------|
| `token.contract`     | `SwornToken`                                        |
| `token.name`         | `swornbyswarm`                                      |
| `token.symbol`       | `SWORN`                                             |
| `token.decimals`     | `18`                                                |
| `token.constructorArgs` | `[]`                                             |
| `token.totalSupply`  | `1000000000000000000000000000`                      |
| application contracts | none                                               |

Launch values decided by the launch (not by this repository): Ethereum (chain id 1), paired with
IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, pool fee 12500 (1.25%), tick spacing 60, and the
requester's economics (70% of supply to the pool at a 5,000 IMD opening cap, remainder to
`0xee2aaa315cf7ed169f93148d30d24af9318dbb66`). The manifest step writes `launch.json`; this
repository deliberately does not.

The reference script `script/DeploySwornToken.s.sol` exists for local rehearsal only. Its `run()`
reads no environment variables and uses whatever broadcaster forge is given on the command line.
It is not how the production deployment happens.

## Assumptions

- The brief asks for a plain token with a fixed supply and two public links; no transfer rules,
  taxes, burns, vesting or governance were requested, so none were added.
- "Minted once to the deployer" means `msg.sender` of the constructor. At launch that is the
  ProjectFactory, as the custom-token launch requires; there is no owner and nothing to transfer
  ownership of.
- Because transfers are untaxed, the factory, pool manager and distributor need no exemptions, so the
  constructor takes none of the optional launch addresses.
- The IMD swarm's 10% is taken by the factory from the minted supply; the token does not reserve or
  allocate anything itself.

## Operational responsibilities

- **Nobody holds admin power over the token.** There is no owner key to rotate, no pause switch, and
  no upgrade path. Once deployed the contract cannot be changed; a bug would require a new token.
- **The deployer holds the full supply at construction.** At launch this is the factory, which
  distributes it in the same transaction. Anyone rehearsing locally with the script holds the
  supply themselves and is responsible for it.
- **Holders are responsible for their own approvals.** Standard ERC-20 allowance rules apply; the
  token has no allowance-reset safeguards beyond OpenZeppelin's defaults.
- **Explorer verification** of the deployed source (`forge verify-contract` with the same solc
  0.8.26, optimizer 200 runs, `bytecode_hash = "none"`, `cbor_metadata = false`) is an open item for
  the launch deployer after deployment.
- **Security review.** Tests passing is not an audit. The contract is OpenZeppelin's ERC20 with
  constants, which keeps the surface minimal, but anything holding or routing other people's funds
  should still get an independent review before release. Slither was not available on this machine
  and was not run; the design avoids the detectors the verifier rejects (no `selfdestruct`, no
  `delegatecall`, no initializers, no shifts, no `abi.encodePacked`, and `transferFrom` moves only
  from the allowance the holder granted).

## After launch

Nothing to configure. The token has no owner-settable values.
