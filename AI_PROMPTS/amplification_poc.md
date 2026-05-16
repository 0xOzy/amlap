# Amplification PoC – Complete Update (PoC, Reports, One-Click Script, Repos)

You are a research assistant in the `ai-sec-research` framework. Your task is to prove that the reentrancy gap (AE-F-005) can amplify cross-chain replay (AE-F-002) by sending duplicate LayerZero messages for the same payoutId, and then update ALL related files and repos.

## Step 1: Create the Amplification PoC
Create `src/test/FT-05_AmplificationPoC.t.sol` inside `~/ai-sec-research/`. The test must prove that `batchCrossChainClaimPayout` can be re-entered to send duplicate messages for the same payoutId.

## Step 2: Run and Fix the Test
Run `forge test --match-test test_DoubleMessageSent --fork-url $BASE_RPC_URL -vvvv`. If it fails, fix it until it PASSES.

## Step 3: Update One-Click Reproduction Script
Edit `~/ample-earn-hackenproof-submission/run_all_poc.sh` to include the new test `FT-05_AmplificationPoC.t.sol` as step 5, and update the summary to count 5 tests.

## Step 4: Copy PoC to Report Repo
Copy the final PoC file to `~/ample-earn-hackenproof-submission/poc/FT-05_AmplificationPoC.t.sol`.

## Step 5: Update Findings Matrix
Edit `~/ample-earn-hackenproof-submission/FINDINGS_MATRIX.md`:
- Add a row for AE-F-002+AE-F-005 (Combined Amplification) with severity HIGH.
- Note that this is permissionless and requires no additional capital.

## Step 6: Update Submission Files
1. Update `~/ample-earn-hackenproof-submission/submission_AE-F-002.md`:
   - Revise Economic Ceiling to $500–$1,200/week based on on-chain payout values.
2. Update `~/ample-earn-hackenproof-submission/submission_AE-F-005.md`:
   - Add "Amplification PoC" section with test description and result.
   - Add "Potential Amplification" section explaining severity upgrade to HIGH.

## Step 7: Update README
Edit `~/ample-earn-hackenproof-submission/README.md`:
- Add the Amplification PoC to the "Proof of Concept" list.
- Update the Mermaid diagram to include the reentrancy amplification step.

## Step 8: Commit and Push
Commit and push all changes to BOTH repositories:
- `~/ai-sec-research/`
- `~/ample-earn-hackenproof-submission/`

## Environment
- RPC: `$BASE_RPC_URL`, `$ARBITRUM_RPC_URL`, `$MONAD_RPC_URL`, `$KATANA_RPC_URL` (all available in `.env`)
- Tools: Foundry `forge`, `cast`
