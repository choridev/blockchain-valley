# Custom Gaia Local Testnet Setup (Zero timeout_commit)

본 문서는 Cosmos Hub(Gaia) 기반의 로컬 4-노드 테스트넷을 구축하는 절차를 명세합니다. 블록 생성 간의 기본 대기 시간(`timeout_commit`: 5초)을 제거하기 위해 CometBFT 합의 엔진의 소스 코드를 직접 수정하여 적용합니다.

## Prerequisites
* Docker & Docker Compose
* Go 1.24+
* Git
* Make

---

## Setup Workflow

### 1. Repository Clone & Source Modification

Gaia 저장소를 클론한 뒤, 의존성으로 사용되는 CometBFT 소스코드를 내부 디렉터리에 다운로드하여 로컬 모듈로 대체(`replace`)합니다.

```bash
# 1. Gaia 저장소 클론 및 디렉터리 이동
git clone https://github.com/cosmos/gaia.git
cd gaia

# 2. 호환되는 버전의 CometBFT 소스코드 다운로드
git clone --depth 1 --branch v0.38.21 https://github.com/cometbft/cometbft.git ./my-cometbft
```

#### 1.1. 합의 엔진 로직 수정 (timeout_commit 제거)
`./my-cometbft/consensus/state.go` 파일 내 `updateToState` 함수를 찾아 `cs.StartTime` 할당 부분을 다음과 같이 수정합니다. 설정된 딜레이를 무시하고 현재 시간으로 즉시 할당하도록 변경합니다.

```go
// 수정 전
if cs.CommitTime.IsZero() {
	cs.StartTime = cs.config.Commit(cmttime.Now())
} else {
	cs.StartTime = cs.config.Commit(cs.CommitTime)
}

// 수정 후
if cs.CommitTime.IsZero() {
	cs.StartTime = cmttime.Now()
} else {
	cs.StartTime = cmttime.Now()
}
```

#### 1.2. go.mod 업데이트
수정된 로컬 디렉터리를 참조하도록 `replace` 지시어를 추가합니다.

```bash
go mod edit -replace github.com/cometbft/cometbft=./my-cometbft
go mod tidy
```

#### 1.3. Dockerfile 수정
로컬 환경의 `my-cometbft` 디렉터리가 도커 컨테이너 빌드 시점(`go mod download` 이전)에 포함될 수 있도록 `Dockerfile`에 `COPY` 명령어를 추가합니다.

```dockerfile
# Dockerfile 내 해당 위치에 아래와 같이 COPY 명령어 추가
COPY go.mod go.sum* ./
COPY my-cometbft ./my-cometbft
RUN go mod download
```

---

### 2. 로컬 CLI 바이너리 빌드 (`make build`)

`gaia` 디렉터리에서 노드 제어용 클라이언트(CLI)로 사용할 로컬 바이너리를 빌드합니다. 

```bash
make clean
make build
```

---

### 3. 커스텀 Docker 이미지 빌드 (`docker build`)

수정된 로컬 모듈이 반영된 `gaiad` 도커 이미지를 빌드합니다.

```bash
# gaia 디렉터리에서 실행
docker build -t my-gaiad:hacked ./
```

---

### 4. 테스트넷 환경 초기화 (`./setup.sh`)

작업 디렉터리로 이동하고 4-node 로컬넷 구성을 위한 설정 파일 및 제네시스 상태를 초기화합니다.

```bash
# 상위 작업 디렉터리로 이동 (예: 0318)
cd ..

# 제네시스 및 노드 설정 파일 생성
./setup.sh
```

---

### 5. 테스트넷 실행 (`docker-compose up`)

`docker-compose.yml` 파일 내 노드들의 `image` 속성이 위에서 빌드한 `my-gaiad:hacked`로 지정되어 있는지 확인한 후 클러스터를 구동합니다.

```bash
# 컨테이너 백그라운드 실행
docker-compose up -d

# 블록 생성 및 네트워크 상태 실시간 로그 확인
docker-compose logs -f
```
