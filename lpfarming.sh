#! /bin/bash

source .env

echo "Enter the start date:"
read start_date

echo "Enter the end date:"
read end_date

echo "---STARTING REWARDS---"
forge script script/LPFarming.s.sol:LPFarming --via-ir \
	-f $BNB_MAINNET_RPC_URL \
	--fork-block-number $(cast find-block -r $BNB_MAINNET_RPC_URL $(date -d "$start_date" "+%s"))
echo "----------------------"

echo "---ENDING REWARDS---"
forge script script/LPFarming.s.sol:LPFarming --via-ir \
	-f $BNB_MAINNET_RPC_URL \
	--fork-block-number $(cast find-block -r $BNB_MAINNET_RPC_URL $(date -d "$end_date" "+%s"))
echo "----------------------"
