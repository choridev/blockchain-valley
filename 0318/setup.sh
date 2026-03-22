#!/bin/bash

# 설정 변수
CHAIN_ID="mac-testnet"
DENOM="uatom"
COINS="1000000000000$DENOM"
STAKE="100000000$DENOM"
NODES=4

echo "🗑️ 기존 데이터 삭제"
rm -rf ./localnet
mkdir -p ./localnet

# 1. 4개 노드 뼈대 초기화 및 지갑 생성
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  echo "🚀 노드 $i 초기화 중..."
  ./gaia/build/gaiad init node$i --chain-id $CHAIN_ID --home $NODE_DIR > /dev/null 2>&1
  ./gaia/build/gaiad keys add val$i --keyring-backend test --home $NODE_DIR > /dev/null 2>&1
done

# 2. 🔥 마스터 제네시스(Node 0) 화폐 단위 개헌
sed -i '' -e "s/\"stake\"/\"$DENOM\"/g" ./localnet/node0/config/genesis.json

echo "💰 모든 지갑의 자금을 Node 0 (마스터 장부)에 기록 중..."
# 3. 🔥 핵심 패치: 4명의 돈을 '노드 0번 장부' 한 곳에 전부 몰아서 기록!
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  VAL_ADDR=$(./gaia/build/gaiad keys show val$i -a --keyring-backend test --home $NODE_DIR)
  
  # 주의: --home 을 node0 로 고정해서 한 장부에 다 기록함!
  ./gaia/build/gaiad genesis add-genesis-account $VAL_ADDR $COINS --home ./localnet/node0
done

# 4. 🔥 돈이 가득 적힌 마스터 장부를 나머지 3명에게 복사 배포!
for i in $(seq 1 $(($NODES - 1))); do
  cp ./localnet/node0/config/genesis.json ./localnet/node$i/config/genesis.json
done

echo "✍️ 각 노드별 출마 선언(Gentx) 생성 중..."
# 5. 이제 모두가 잔고를 인정받았으니, 각자 출마 선언!
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  ./gaia/build/gaiad genesis gentx val$i $STAKE --chain-id $CHAIN_ID --keyring-backend test --home $NODE_DIR > /dev/null 2>&1
done

echo "🔗 마스터 제네시스 파일 조립 중..."
# 6. 모든 노드의 Gentx를 노드 0번으로 모으기
for i in $(seq 1 $(($NODES - 1))); do
  cp ./localnet/node$i/config/gentx/*.json ./localnet/node0/config/gentx/
done

# 노드 0번에서 하나로 취합 (에러 보일 수 있게 숨김 제거!)
./gaia/build/gaiad genesis collect-gentxs --home ./localnet/node0

# 7. 최종 완성된 (검증인 명단이 포함된) 제네시스를 모두에게 재배포!
for i in $(seq 1 $(($NODES - 1))); do
  cp ./localnet/node0/config/genesis.json ./localnet/node$i/config/genesis.json
done

echo "📞 P2P 연락처(persistent_peers) 및 설정 교환 중..."
# 8. P2P 연락처 수집
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

# 9. 각 노드의 config 수정
for i in $(seq 0 $(($NODES - 1))); do
  NODE_DIR="./localnet/node$i"
  sed -i '' -e "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/g" $NODE_DIR/config/config.toml
  sed -i '' -e 's/addr_book_strict = true/addr_book_strict = false/g' $NODE_DIR/config/config.toml
  sed -i '' -e 's/laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/g' $NODE_DIR/config/config.toml
  sed -i '' -e 's/enable = false/enable = true/g' $NODE_DIR/config/app.toml
  sed -i '' -e "s/^minimum-gas-prices = .*/minimum-gas-prices = \"0$DENOM\"/g" $NODE_DIR/config/app.toml
done

echo "🎉 세팅 완벽 종료! 이제 진짜 'docker-compose up -d'를 실행하세요!"
