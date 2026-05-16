# External Dependencies

## Euler Earn (Core)
- ERC-4626 meta-vault: aggregates deposits into curated lending vaults
- EulerEarnFactory: deploys new Earn vaults
- Euler EVK: lending vaults (strategies)
- EVC: batch operations
- Docs: https://docs.euler.finance/developers/euler-earn/

## Oracle
- Chainlink price feeds (via Euler vaults)
- TWAP fallback (Euler oracle adapters)

## Libraries
- OpenZeppelin (Ownable, ERC-4626, SafeCast, EnumerableSet, etc.)
- Solmate (some math utils)
- LayerZero (cross-chain messaging)

## Integrations
- Permit2 (gasless approvals)
- EVC (Ethereum Vault Connector - batch calls)

## Risks
- Euler Earn strategy risk (bad debt in underlying vaults)
- LayerZero validator risk
- Oracle manipulation via low-liquidity Euler vaults
