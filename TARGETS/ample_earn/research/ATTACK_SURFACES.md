# Attack Surfaces — Ample Earn

## High Risk
- **ERC-4626 donation attacks**: share inflation via direct token transfers
- **Cross-chain replay**: payoutId reuse across chains
- **Prize distribution timing**: MEV front-running winner selection
- **LayerZero message validation**: `OnlyPeer` / `NoPeer` error handling

## Medium Risk
- **Proxy upgrade (Monad)**: Owner can change implementation
- **Strategy cap timelock**: Guardian can cancel but curator may front-run
- **Performance fee calculation**: fee-on-transfer tokens
- **Permit2 integration**: signature replay

## Low Risk
- **EVC batch failure**: partial execution of batch operations
- **Oracle staleness**: delayed Chainlink updates in low-activity periods

## Notes
- AmplePerspective extends Euler Earn — inherits its attack surface
- CrossChainRouter uses LayerZero OApp — inherits LayerZero risks
- Multiple chains → deterministic addresses → potential cross-chain confusion
