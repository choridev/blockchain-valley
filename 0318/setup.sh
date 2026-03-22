#!/bin/bash

# Configuration Variables
CHAIN_ID="mac-testnet"
DENOM="uatom"
COINS="1000000000000$DENOM"
STAKE="100000000$DENOM"
NODES=4

echo "[1/9] Cleaning up existing localnet data..."
rm -rf ./localnet
mkdir -p ./localnet

echo "[2/9] Initializing node environments and generating validator keys..."
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  ./gaia/build/gaiad init node$i --chain-id $CHAIN_ID --home $NODE_DIR > /dev/null 2>&1
  ./gaia/build/gaiad keys add val$i --keyring-backend test --home $NODE_DIR > /dev/null 2>&1
done

echo "[3/9] Modifying genesis denomination..."
sed -i '' -e "s/\"stake\"/\"$DENOM\"/g" ./localnet/node0/config/genesis.json

echo "[4/9] Consolidating genesis accounts to the primary node (node0)..."
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  VAL_ADDR=$(./gaia/build/gaiad keys show val$i -a --keyring-backend test --home $NODE_DIR)
  ./gaia/build/gaiad genesis add-genesis-account $VAL_ADDR $COINS --home ./localnet/node0
done

echo "[5/9] Distributing primary genesis file to all nodes..."
for i in $(seq 1 $(($NODES - 1))); do
  cp ./localnet/node0/config/genesis.json ./localnet/node$i/config/genesis.json
done

echo "[6/9] Generating genesis transactions (gentx) for each validator..."
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  ./gaia/build/gaiad genesis gentx val$i $STAKE --chain-id $CHAIN_ID --keyring-backend test --home $NODE_DIR > /dev/null 2>&1
done

echo "[7/9] Collecting gentxs and generating final genesis.json..."
for i in $(seq 1 $(($NODES - 1))); do
  cp ./localnet/node$i/config/gentx/*.json ./localnet/node0/config/gentx/
done

./gaia/build/gaiad genesis collect-gentxs --home ./localnet/node0

echo "[8/9] Distributing final genesis file to all nodes..."
for i in $(seq 1 $(($NODES - 1))); do
  cp ./localnet/node0/config/genesis.json ./localnet/node$i/config/genesis.json
done

echo "[9/9] Configuring node parameters (P2P, RPC, API, Prometheus, Gas)..."
PEERS=""
for i in $(seq 0 $(($NODES - 1))); do
  NODE_ID=$(./gaia/build/gaiad tendermint show-node-id --home ./localnet/node$i)
  PEER_ADDR="${NODE_ID}@node${i}:26656"
  if [ -z "$PEERS" ]; then
    PEERS="$PEER_ADDR"
  else
    PEERS="$PEERS,$PEER_ADDR"
  fi
done

for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  # config.toml modifications
  sed -i '' -e "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/g" $NODE_DIR/config/config.toml
  sed -i '' -e 's/addr_book_strict = true/addr_book_strict = false/g' $NODE_DIR/config/config.toml
  sed -i '' -e 's/laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/g' $NODE_DIR/config/config.toml
  sed -i '' -e 's/prometheus = false/prometheus = true/g' $NODE_DIR/config/config.toml
  
  # app.toml modifications
  sed -i '' -e 's/enable = false/enable = true/g' $NODE_DIR/config/app.toml
  sed -i '' -e "s/^minimum-gas-prices = .*/minimum-gas-prices = \"0$DENOM\"/g" $NODE_DIR/config/app.toml
done

echo "Localnet setup completed successfully."
