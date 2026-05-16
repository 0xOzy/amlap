#!/bin/bash
# run_all_poc.sh — Run all Proof-of-Concept tests for Ample Earn findings
# Usage: source .env && bash run_all_poc.sh

set -euo pipefail

echo "============================================"
echo "  Ample Earn — PoC Test Suite"
echo "============================================"
echo ""

# ── AE-F-002: Cross-Chain Payout Replay (fork test) ──
echo "━━━ AE-F-002: Cross-Chain Payout Replay ━━━"
echo "Command: forge test --match-contract CrossChainReplayPoC -vvvv"
forge test --match-contract CrossChainReplayPoC -vvvv
echo "✅ AE-F-002 PASSED"
echo ""

# ── AE-F-005: Reentrancy Gap (unit test) ──
echo "━━━ AE-F-005: Reentrancy Gap ━━━"
echo "Command: forge test --match-contract ReentrancyPoC -vvvv"
forge test --match-contract ReentrancyPoC -vvvv
echo "✅ AE-F-005 PASSED"
echo ""

# ── AE-F-007: Amplification PoC (mock endpoint — no fork URL needed) ──
echo "━━━ AE-F-007: Amplification PoC (Mock) ━━━"
echo "Command: forge test --match-test test_DoubleMessageSent -vvvv"
forge test --match-test test_DoubleMessageSent -vvvv
echo "✅ AE-F-007 (Mock) PASSED"
echo ""

# ── AE-F-007: Amplification Fork Test (real Arbitrum router) ──
echo "━━━ AE-F-007: Amplification Fork Test (Real Router) ━━━"
echo "Command: forge test --match-test test_AmplificationFork --fork-url \$ARBITRUM_RPC_URL -vvvv"
forge test --match-test test_AmplificationFork --fork-url $ARBITRUM_RPC_URL -vvvv
echo "✅ AE-F-007 (Fork) PASSED"
echo ""

echo "============================================"
echo "  All PoC tests passed!"
echo "============================================"
