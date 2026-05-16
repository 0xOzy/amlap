# Hard PoC Finalization – Cross-Chain Replay

You are a research assistant working within the `ai-sec-research` framework. The current Hard PoC for cross-chain replay is failing because `claimPayout` reverts. Your task is to **make this test PASS** by understanding every validation in the contract and correctly replicating a real payout state.

## Step 1: Study All `claimPayout` Conditions
1. Read `src/ample/AmpleEarn.sol`, focusing on the `claimPayout` function.
2. Also read `src/ample/interfaces/IAmpleEarn.sol` for the `PayoutPool` struct definition.
3. Identify every check performed before funds are transferred:
   - Must `payoutId` be <= `currentPayoutId`?
   - Must `participantsRoot` or `designatedRecipientsRoot` be non-zero?
   - Must `totalTickets` be > 0?
   - Must `remainingPayoutAmount` be > 0?
   - Is there a `isPayoutManager` or `onlyOwner` check?
   - Is there Merkle proof verification requiring leaf and root to match?
   - Are there `claimMask` or `isPayoutClaimed` checks?

## Step 2: Create a Valid Synthetic Payout Pool
Use `vm.store` to write all storage slots needed so that `claimPayout(PAYOUT_ID, proof, leaf, false)` succeeds:
- Use the correct `payoutPool` mapping slot (slot 23 from earlier research).
- Fill all struct fields with sensible values that satisfy every check.
- Ensure `participantsRoot` equals `leaf` (for a single-leaf tree, root = leaf).
- Use `PAYOUT_ID = 999` to avoid collision with real payouts.

## Step 3: Fund the Vault with USDC
Find a way for the vault to hold enough USDC to pay out the claim. Options:
- Use `vm.prank` to impersonate a USDC whale (an address with a large USDC balance) and transfer USDC to the vault.
- Or use `vm.store` to increase the vault's `_balances` entry in the USDC contract (requires the correct storage slot).
- Use the Arbitrum USDC address: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`.

## Step 4: Run the Test and Fix
Execute `forge test --match-test test_DoubleClaimExploit --fork-url $BASE_RPC_URL -vvvv`. If it fails, read the trace and fix the setup. Repeat until claiming on Arbitrum and Monad both succeed.

## Step 5: Save Results
1. After the test passes, capture the log and save it to `TARGETS/ample_earn/research/HARD_POC_RESULTS.md`.
2. Update `submission_AE-F-002.md` with a "Hard PoC" section that describes the test and its result.
3. Copy the fixed test file to `~/ample-earn-hackenproof-submission/poc/FT-02_HardPoC.t.sol`.
4. Copy the updated `submission_AE-F-002.md` to `~/ample-earn-hackenproof-submission/`.

## Environment
- RPC: `$BASE_RPC_URL`, `$ARBITRUM_RPC_URL`, `$MONAD_RPC_URL`
- Tools: Foundry `forge`, `cast`
