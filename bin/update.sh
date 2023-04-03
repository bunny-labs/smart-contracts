#!/bin/sh

contract=$1
echo "Updating $contract..."

forge script "script/Update$contract.s.sol" \
    --sender "$DEPLOYER_ADDRESS" \
    --rpc-url http://localhost:1248 \
    --broadcast \
    --unlocked