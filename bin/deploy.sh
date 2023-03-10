#!/bin/sh

contract=$1
echo "Deploying $contract..."

forge script "script/Deploy$contract.s.sol" \
    --sender "$DEPLOYER_ADDRESS" \
    --rpc-url http://localhost:1248 \
    --broadcast \
    --slow \
    --verify \
    --unlocked