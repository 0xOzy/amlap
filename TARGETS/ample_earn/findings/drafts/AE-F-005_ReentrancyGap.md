# AE-F-005: batchCrossChainClaimPayout Missing nonReentrant

## Severity

**🟠 MEDIUM**

## Summary

`AmpleEarnCrossChainRouter.batchCrossChainClaimPayout()` is an external-facing function that handles LayerZero message sending and native token refunds. It performs external calls (LayerZero endpoint + `.call{value}` to `msg.sender`) but is **not protected by `nonReentrant`**. The refund `.call{value}` at line 130 is a reentrancy vector if `msg.sender` is a contract.

## Root Cause

```solidity
// AmpleEarnCrossChainRouter.sol:89-133
function batchCrossChainClaimPayout(
    bytes[] calldata _claimData,
    MessagingFee calldata _fee
) external payable returns (MessagingReceipt[] memory receipts) {
    // ⚠️ NO nonReentrant modifier
    
    uint256 totalValueUsed;
    receipts = new MessagingReceipt[](_claimData.length);
    
    for (uint256 i; i < _claimData.length; ++i) {
        // ... LayerZero _lzSend() call ...
        totalValueUsed += fee.nativeFee;
    }
    
    // Refund excess — REENTRANCY VECTOR
    if (msg.value > totalValueUsed) {
        (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
        if (!success) revert TransferFailed();
    }
}
```

Compare with `_executeClaims()` (called in `_lzReceive()`) which IS protected:

```solidity
// AmpleEarnCrossChainRouter.sol:177 — Protected
function _executeClaims(...) internal nonReentrant {
```

## Attack Scenario

1. Attacker deploys `AttackerContract` with a `receive()` fallback that re-enters `batchCrossChainClaimPayout()`
2. Calls `batchCrossChainClaimPayout()` with valid claims for Chain A
3. Refund `.call{value}` triggers `AttackerContract.receive()`
4. Re-enters `batchCrossChainClaimPayout()` with claims for Chain B
5. Original LayerZero fee is reused or double-counted

## Preconditions

| # | Precondition | Status |
|---|---|---|
| P-01 | `msg.sender` must be a **contract** | Attacker deploys contract |
| P-02 | `msg.value > totalValueUsed` (refund occurs) | ⚠️ Variable — depends on fee estimation |
| P-03 | Re-entry path must be profitable | ⚠️ Need to verify double-counting of LayerZero fees |

## Mitigation

Add `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`:

```solidity
function batchCrossChainClaimPayout(
    bytes[] calldata _claimData,
    MessagingFee calldata _fee
) external payable nonReentrant returns (MessagingReceipt[] memory receipts) {
    // ... existing logic
}
```

## Confidence

**MEDIUM** — Exploit path exists architecturally, but profitability and execution constraints need fork test validation.

## Validation Status

| Item | Status |
|---|---|
| Source code analysis | ✅ **Verified** — `nonReentrant` absent on external function |
| Fork test | ⏳ **Pending** |
