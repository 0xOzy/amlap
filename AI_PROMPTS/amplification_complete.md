# Complete Amplification Verification & Submission

You are a research assistant in the `ai-sec-research` framework. Your task is to verify that the amplification PoC accurately represents the real mainnet contracts, then create a new standalone submission (AE-F-007) and update all related files. Do everything in ONE session.

## Part A: Mainnet Verification
1. Read `src/test/FT-05_AmplificationPoC.t.sol` – understand the mock `CountingLzEndpoint`.
2. Read `src/ample/AmpleEarnCrossChainRouter.sol` – focus on `batchCrossChainClaimPayout`, the refund mechanism, and `nonReentrant`.
3. Use `cast` to get the real LayerZero endpoint from Arbitrum router `0xcab6a41090e274efe7fe64cf0ec906f413686d36`.
4. Compare: does the mock refund (`.call{value}(msg.sender)`) match the real router? Does the real router lack `nonReentrant`?
5. Create `src/test/FT-05_AmplificationFork.t.sol` that forks Arbitrum mainnet and proves re-entry against the REAL router.
6. Run `forge test --match-test test_AmplificationFork --fork-url $ARBITRUM_RPC_URL -vvvv`. Fix until PASS.
7. Create `TARGETS/ample_earn/research/AMPLIFICATION_MAINNET_ANALYSIS.md` with comparison table and conclusion.

## Part B: Create New Submission
8. Read existing files in `~/ample-earn-hackenproof-submission/` (README, FINDINGS_MATRIX, submission_AE-F-002, submission_AE-F-005, run_all_poc.sh).
9. Create `~/ample-earn-hackenproof-submission/submission_AE-F-007.md` with severity HIGH, referencing both AE-F-002 and AE-F-005, including the amplification PoC and mainnet verification results.
10. Update `FINDINGS_MATRIX.md` – add AE-F-007 row.
11. Update `submission_AE-F-005.md` – add "Combined Impact with AE-F-002" section.
12. Update `README.md` – add AE-F-007 to table and PoC list.
13. Update `run_all_poc.sh` – ensure it includes `FT-05_AmplificationFork.t.sol` (the NEW fork test) as an additional step, so the one-click script now runs 6 PoC tests including the mainnet fork verification.

## Part C: Finalize
14. Copy both amplification PoC files (`FT-05_AmplificationPoC.t.sol` and `FT-05_AmplificationFork.t.sol`) to `~/ample-earn-hackenproof-submission/poc/`.
15. Commit and push both repos.

## Rules
- Do NOT modify existing severity/content of AE-F-002 and AE-F-005 beyond requested additions.
- Keep all English professional.
- Do NOT invent new findings – only document what has been proven.

## Environment
- RPC: `$ARBITRUM_RPC_URL`, `$BASE_RPC_URL`, `$MONAD_RPC_URL`, `$KATANA_RPC_URL`
- Tools: Foundry `forge`, `cast`
- Arbitrum Router: `0xcab6a41090e274efe7fe64cf0ec906f413686d36`
