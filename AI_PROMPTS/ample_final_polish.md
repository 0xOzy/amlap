# Final Polish for AmpleProof Repository

You are a research assistant in the `ai-sec-research` framework. Your task is to further polish the `AmpleProof` repository located at `~/ample-earn-hackenproof-submission`.

## Task 1: Create One-Click Reproduction Script
Create a bash script `run_all_poc.sh` in the root of `~/ample-earn-hackenproof-submission/` that:
1. Sources the environment variables from `~/.env` (or instructs the user to set them).
2. Runs all PoC tests in sequence: `FT-02_CrossChainPayoutReplay.t.sol`, `FT-02_FullPoC.t.sol`, `FT-05_ReentrancyPoC.sol`, and `FT-02_HardPoC.t.sol`.
3. Prints a clear summary of passed/failed tests at the end.

## Task 2: Add Visual Attack Flow Diagram
Add a "Visual Attack Flow" section to the `README.md` of `~/ample-earn-hackenproof-submission/`. Use a **Mermaid sequence diagram** to illustrate the cross-chain replay attack (Arbitrum, Monad, Katana) as described in AE-F-002.

## Task 3: Add Differential Testing Note to Submission
Add a short section titled "**Differential Testing**" to `submission_AE-F-002.md`. Explain:
- The PoC was executed on a forked mainnet state.
- It demonstrates the state *before* a fix.
- If a fix were applied, the same test would fail, proving the fix is effective.
- This serves as a clear regression test for the development team.

## Environment
- RPC: `$BASE_RPC_URL`, `$ARBITRUM_RPC_URL`, `$MONAD_RPC_URL` (assume these are set in the environment or `~/.env`).
- Tools: Foundry `forge`, `cast`.
