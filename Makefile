-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network opbnb-testnet\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops --no-commit && forge install openzeppelin/openzeppelin-contracts --no-commit && forge install uniswap/v2-core --no-commit && forge install uniswap/v2-periphery --no-commit && forge install uniswap/solidity-lib --no-commit 

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

coverage :; forge coverage --report debug > coverage-report.txt

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network opbnb-testnet,$(ARGS)),--network opbnb-testnet)
	NETWORK_ARGS := \
	--rpc-url $(OPBNB_TESTNET_RPC_URL) \
	--priority-gas-price 100000 \
	--with-gas-price 100000 \
	--broadcast \
	--account $(OPBNB_TESTNET_ACCOUNT) \
	--password $(PASSWORD) \
	-vvvv
endif

deploy:
	@forge script script/DeployRayFi.s.sol:DeployRayFi $(NETWORK_ARGS)

create-pair:
	@forge script script/Interactions.s.sol:CreateRayFiLiquidityPool $(NETWORK_ARGS)

create-users:
	@forge script script/Interactions.s.sol:CreateRayFiUsers $(NETWORK_ARGS)

create-vaults:
	@forge script script/Interactions.s.sol:AddMockRayFiVaults $(NETWORK_ARGS)

fund:
	@forge script script/Interactions.s.sol:FundRayFi $(NETWORK_ARGS)

distribute-stateless:
	@forge script script/Interactions.s.sol:DistributeRewardsStateless $(NETWORK_ARGS)

distribute-stateful:
	@forge script script/Interactions.s.sol:DistributeRewardsStateful $(NETWORK_ARGS)