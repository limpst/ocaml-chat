# OCaml Chat

OCaml로 작성한 TCP 소켓 기반 멀티 유저 채팅 프로그램입니다.
**3-Tier 아키텍처**와 **MVC 패턴**으로 구성되어 있으며, 메시지 처리는 모두 서버에서 이루어집니다.

## 아키텍처

```
┌───────────────────────────┐
│ 1. Presentation Tier      │  client.ml
│    View       view.ml     │  화면 출력
│    Controller controller.ml│  입력 → 요청 변환, 응답 → View
└─────────────┬─────────────┘
              │ TCP Socket  (protocol.ml)
┌─────────────┴─────────────┐
│ 2. Business Logic Tier    │  server.ml  (접속 수락, 클라이언트별 스레드)
│    Controller service.ml  │  요청 처리 · 저장 · 브로드캐스트
│    Model      model.ml    │  채팅방 / 세션 상태 (Mutex 보호)
└─────────────┬─────────────┘
              │
┌─────────────┴─────────────┐
│ 3. Data Tier              │  repository.ml → chat_history.log
└───────────────────────────┘
```

| 파일 | 역할 |
|---|---|
| `model.ml` | 도메인 타입(메시지, 세션)과 채팅방 상태 |
| `protocol.ml` | 소켓 통신 규약 (한 줄 = 한 메시지, 탭 구분) |
| `repository.ml` | 메시지 영속화 (파일 저장 / 최근 N개 조회) |
| `service.ml` | 서버 측 비즈니스 로직 |
| `server.ml` | 서버 진입점 |
| `view.ml` | 클라이언트 화면 출력 |
| `controller.ml` | 클라이언트 입력 해석 / 응답 처리 |
| `client.ml` | 클라이언트 진입점 |

### 통신 프로토콜

| 방향 | 형식 |
|---|---|
| Client → Server | `SAY<TAB>text` · `NICK<TAB>name` · `WHO` · `HIST` · `QUIT` |
| Server → Client | `MSG<TAB>time<TAB>author<TAB>text` · `SYS<TAB>text` · `USERS<TAB>a,b,c` · `ERR<TAB>text` |

## 요구 사항

- OCaml 5.x (opam) — 표준 라이브러리 `unix`, `threads`만 사용, 추가 패키지 불필요
- Windows: `winget install OCaml.opam` → `opam init`

## 빌드

```powershell
.\build.ps1
```

`server.exe`, `client.exe`(네이티브)와 `server.byte`, `client.byte`(바이트코드)가 생성됩니다.

## 실행

```powershell
.\run-server.ps1            # 서버 (기본 포트 9000)
.\run-client.ps1            # 클라이언트 — 터미널 여러 개에서 실행
.\run-client.ps1 192.168.0.10 9000   # 다른 PC의 서버에 접속
```

> 일부 백신이 새로 컴파일된 `server.exe`를 오탐할 수 있어 `run-server.ps1`은 바이트코드(`ocamlrun server.byte`)로 실행합니다.

## 명령어

| 입력 | 동작 |
|---|---|
| `/nick NAME` | 닉네임 변경 (영문/숫자/`_`/`-`, 최대 16자, 중복 불가) |
| `/who` | 접속자 목록 |
| `/history` | 최근 메시지 20개 |
| `/quit` | 종료 |
| 그 외 | 채팅 메시지 전송 |

## 실행 예

```
connected to 127.0.0.1:9000
*** Welcome, guest1! Commands: /nick NAME, /who, /history, /quit
*** guest1 is now known as alice
*** guest2 joined the chat
*** guest2 is now known as bob
[02:42:32] alice: Hello bob!
[02:42:32] bob: Hi alice, OCaml chat works
*** online (2): alice, bob
```
