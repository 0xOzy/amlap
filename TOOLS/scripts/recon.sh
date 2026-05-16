#!/bin/bash

TARGET=$1

echo "[+] Running Slither..."
slither $TARGET

echo "[+] Running Semgrep..."
semgrep scan $TARGET

echo "[+] Recon complete."
