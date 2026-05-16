# Attack Surfaces

## High Risk

- external calls before state updates
- custom accounting logic
- upgradeable proxy
- delayed oracle updates
- reward debt system

## Medium Risk

- emergency admin functions
- fee calculation logic
- liquidation incentives

## Notes

Vault uses custom ERC4626 implementation.

Oracle fallback logic requires deeper review.
