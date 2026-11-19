# OCaml Chat

![OCaml](https://img.shields.io/badge/OCaml-5.x-EC6813?logo=ocaml&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![Libraries](https://img.shields.io/badge/deps-unix%20%C2%B7%20threads%20only-555)
![Architecture](https://img.shields.io/badge/architecture-3--Tier%20%2B%20MVC-6f42c1)

OCaml로 작성한 TCP 소켓 기반 멀티 유저 채팅 프로그램입니다.
**3-Tier 아키텍처**와 **MVC 패턴**으로 구성되어 있으며, 메시지 처리는 모두 서버에서 이루어집니다.

## 목차

- [아키텍처](#아키텍처) — 계층 구조 · 모듈 의존 관계 · 데이터 모델 · 접속 상태
- [스레드와 동시성](#스레드와-동시성)
- [폴더 구조](#폴더-구조)
- [요청 처리 흐름](#요청-처리-흐름) — 채팅 · 연결 수명 주기 · 닉네임 변경 · 히스토리
- [통신 프로토콜](#통신-프로토콜)
- [요구 사항](#요구-사항) · [빌드](#빌드) · [실행](#실행) · [명령어](#명령어) · [실행 예](#실행-예)

## 아키텍처

```mermaid
flowchart TB
    subgraph T1["Tier 1. Presentation — src/client"]
        direction LR
        CL["client.ml<br/>진입점 · 입력/수신 스레드"]
        CC["controller.ml<br/>MVC Controller<br/>키보드 입력 → 요청, 응답 → View"]
        CV["view.ml<br/>MVC View<br/>화면 출력"]
        CL --> CC --> CV
    end

    subgraph T2["Tier 2. Business Logic — src/server"]
        direction LR
        SS["server.ml<br/>진입점 · 클라이언트별 스레드"]
        CS["chat_service.ml<br/>MVC Controller<br/>요청 처리 · 저장 · 브로드캐스트"]
        SM["model.ml<br/>MVC Model<br/>채팅방 / 세션 상태"]
        SS --> CS --> SM
    end

    subgraph T3["Tier 3. Data — src/data"]
        direction LR
        RP["repository.ml<br/>메시지 저장/조회"]
        LOG[("chat_history.log")]
        RP <--> LOG
    end

    T1 <==>|"TCP Socket<br/>src/shared/protocol.ml"| T2
    T2 ==> T3
```

### 모듈 의존 관계

```mermaid
flowchart BT
    subgraph shared["src/shared — 서버·클라이언트 공용"]
        sync["sync.ml"]
        text["text.ml"]
        message["message.ml"]
        protocol["protocol.ml"]
    end

    subgraph data["src/data"]
        repository["repository.ml"]
    end

    subgraph server["src/server"]
        model["model.ml"]
        chat_service["chat_service.ml"]
        srv["server.ml"]
    end

    subgraph client["src/client"]
        view["view.ml"]
        controller["controller.ml"]
        cli["client.ml"]
    end

    message --> text
    protocol --> message
    repository --> message
    repository --> sync
    model --> sync
    chat_service --> model
    chat_service --> repository
    chat_service --> protocol
    srv --> chat_service
    view --> protocol
    controller --> view
    cli --> controller
```

> 화살표는 "사용한다" 방향입니다. 빌드 순서는 아래(shared) → 위(server / client)입니다.

### 데이터 모델

서버 상태(`model.ml`)와 공용 메시지 타입(`message.ml`)입니다.

```mermaid
classDiagram
    direction LR
    class room {
        <<model.ml>>
        +mutable sessions : session list
        +mutable next_id : int
        +lock : Mutex.t
        create_room() room
        add_session(room, send_line) session
        remove_session(room, session)
        rename(room, session, new_nick) result
        nicknames(room) string list
        all_sessions(room) session list
    }
    class session {
        <<model.ml>>
        +id : int
        +mutable nick : string
        +send_line : string → unit
    }
    class Message_t {
        <<message.ml · Message.t>>
        +time : float
        +author : string
        +text : string
        make(author, text) t
        to_fields(t) string list
        of_fields(string list) t option
    }
    room "1" o-- "0..*" session : sessions
    session ..> Message_t : nick = author
```

| 규칙 | 내용 |
|---|---|
| 기본 닉네임 | 접속 순서대로 `guest1`, `guest2`, … (`next_id`) |
| 닉네임 형식 | 1~16자, `a-z A-Z 0-9 _ -` |
| 닉네임 중복 | 다른 세션이 쓰는 이름이면 `ERR⇥nickname already in use` |

### 클라이언트 접속 상태

```mermaid
stateDiagram-v2
    state "접속됨" as Connected
    state "대화 중" as Chatting
    state "종료 처리" as Closing

    [*] --> Connected: Unix.accept
    Connected --> Chatting: on_connect (guest N 등록, 환영, 최근 5개, 입장 알림)
    Chatting --> Chatting: SAY / WHO / HIST
    Chatting --> Chatting: NICK 성공 → 전원 알림
    Chatting --> Chatting: NICK 실패 / 잘못된 요청 → ERR
    Chatting --> Closing: QUIT
    Chatting --> Closing: 연결 끊김 (End_of_file, 소켓 오류)
    Closing --> [*]: on_disconnect, close_socket
```

## 스레드와 동시성

서버는 접속마다 스레드를 하나씩 띄우고, 공유 자원은 `Sync.with_lock`(예외가 나도 반드시 잠금 해제)으로 보호합니다.

```mermaid
flowchart TB
    subgraph SERVER["서버 프로세스"]
        MAIN["메인 스레드<br/>while true: Unix.accept"]
        MAIN -- "Thread.create" --> TA["handle_client 스레드<br/>(alice)"]
        MAIN -- "Thread.create" --> TB["handle_client 스레드<br/>(bob)"]
        MAIN -- "Thread.create" --> TC["handle_client 스레드<br/>(…)"]

        subgraph LOCKS["공유 자원 · Mutex"]
            RL["room.lock<br/>세션 목록 · 닉네임"]
            FL["file_lock<br/>chat_history.log"]
            WL["소켓별 write_lock<br/>한 줄 단위 전송"]
        end

        TA & TB & TC --> RL
        TA & TB & TC --> FL
        TA & TB & TC -- "broadcast" --> WL
    end

    subgraph CLIENT["클라이언트 프로세스 (각자)"]
        KM["메인 스레드<br/>read_keyboard_loop → 요청 전송"]
        RX["수신 스레드<br/>start_receiver → View 출력"]
    end

    KM -- "SAY / NICK / …" --> SERVER
    SERVER -- "MSG / SYS / …" --> RX
```

| 잠금 | 위치 | 보호 대상 | 이유 |
|---|---|---|---|
| `room.lock` | `model.ml` | 세션 목록, 닉네임, `next_id` | 동시 접속·닉 변경 시 목록 일관성 |
| `file_lock` | `repository.ml` | `chat_history.log` 쓰기/읽기 | 저장 중 읽기 · 줄 섞임 방지 |
| `write_lock` | `server.ml` (소켓마다) | 소켓 출력 채널 | 여러 스레드의 broadcast가 한 소켓에 겹쳐 쓰는 것 방지 |

> `broadcast`는 `all_sessions`로 세션 목록 **복사본**만 잠금 안에서 얻고, 실제 전송은 잠금 밖에서 합니다. 느린 클라이언트 하나가 채팅방 전체를 막지 않도록 하기 위해서입니다.

## 폴더 구조

```
src/
  shared/              서버·클라이언트 공용
    sync.ml            스레드 잠금 도우미 (with_lock)
    text.ml            문자열 도우미 (탭 필드 분리/결합, BOM·\r 제거)
    message.ml         채팅 메시지 타입 (공용 Model 데이터)
    protocol.ml        소켓 통신 규약 (request / response 인코딩·디코딩)
  data/
    repository.ml      Tier 3 — 메시지 영속화
  server/
    model.ml           Tier 2 — MVC Model
    chat_service.ml    Tier 2 — MVC Controller (메시지 처리)
    server.ml          Tier 2 — 서버 진입점
  client/
    view.ml            Tier 1 — MVC View
    controller.ml      Tier 1 — MVC Controller
    client.ml          Tier 1 — 클라이언트 진입점
build.ps1              빌드 스크립트 → bin/
run-server.ps1         서버 실행
run-client.ps1         클라이언트 실행
```

## 요청 처리 흐름

키보드로 `hello`를 입력했을 때의 흐름입니다.

```mermaid
sequenceDiagram
    autonumber
    actor U as 사용자 (alice)
    box Tier 1 · Client
        participant CC as controller.ml
        participant CL as client.ml
        participant V as view.ml
    end
    box Tier 2 · Server
        participant S as server.ml
        participant CS as chat_service.ml
    end
    box Tier 3 · Data
        participant R as repository.ml
    end

    U->>CC: "hello"
    CC->>CL: interpret_input → Send (Say "hello")
    CL->>S: make_request_sender → "SAY⇥hello" (소켓)
    S->>S: serve_requests → decode_request
    S->>CS: handle_request → handle_say
    CS->>R: save (chat_history.log에 추가)
    CS-->>CL: broadcast (Chat message) → "MSG⇥time⇥alice⇥hello"
    Note over CS,CL: 접속한 모든 클라이언트에게 전송
    CL->>CC: handle_server_line
    CC->>V: render
    V->>U: [12:00:00] alice: hello
```

### 클라이언트 연결 수명 주기 (서버)

```mermaid
flowchart TD
    A["Unix.accept<br/>접속 대기"] --> B["Thread.create handle_client<br/>클라이언트별 스레드"]
    B --> C["on_connect<br/>세션 등록 · 환영 인사<br/>최근 대화 5개 · 입장 알림"]
    C --> D{"input_line"}
    D -- "End_of_file / 소켓 오류" --> X
    D -- "한 줄 수신" --> E{"decode_request"}
    E -- "None" --> F["ERR⇥bad request"] --> D
    E -- "SAY · NICK · WHO · HIST" --> G["handle_request<br/>→ Keep_connection"] --> D
    E -- "QUIT" --> X["on_disconnect<br/>세션 제거 · 퇴장 알림"]
    X --> Y["close_socket"]
    A -. "다음 접속" .-> A
```

### 닉네임 변경 (`/nick`)

```mermaid
sequenceDiagram
    actor U as 사용자 (guest1)
    participant CL as client
    participant CS as chat_service.ml
    participant M as model.ml
    participant ALL as 모든 클라이언트

    U->>CL: /nick alice
    CL->>CS: NICK⇥alice
    CS->>M: rename room session "alice"
    Note over M: room.lock 안에서<br/>형식 검사 → 중복 검사 → 변경
    alt 성공
        M-->>CS: Ok "guest1"
        CS-->>ALL: SYS⇥guest1 is now known as alice
    else 형식 위반
        M-->>CS: Error "invalid nickname (1-16 chars: a-z A-Z 0-9 _ -)"
        CS-->>CL: ERR⇥invalid nickname …
    else 이미 사용 중
        M-->>CS: Error "nickname already in use"
        CS-->>CL: ERR⇥nickname already in use
    end
```

### 대화 기록 (입장 시 · `/history`)

```mermaid
sequenceDiagram
    participant CL as client
    participant CS as chat_service.ml
    participant R as repository.ml
    participant F as chat_history.log

    rect rgba(100, 150, 255, 0.12)
    Note over CL,F: 입장할 때 (on_connect)
    CS->>R: load_recent 5
    R->>F: read_lines (file_lock)
    F-->>R: 모든 줄
    R-->>CS: 마지막 5개 (깨진 줄은 버림)
    CS-->>CL: MSG × 최대 5
    end

    rect rgba(100, 200, 120, 0.12)
    Note over CL,F: /history 요청 (HIST)
    CL->>CS: HIST
    CS->>R: load_recent 20
    R->>F: read_lines (file_lock)
    R-->>CS: 마지막 20개
    alt 기록 없음
        CS-->>CL: SYS⇥no history yet
    else 기록 있음
        CS-->>CL: SYS⇥---- last messages ----
        CS-->>CL: MSG × 최대 20
    end
    end
```

저장 형식(`chat_history.log`)은 프로토콜의 `MSG` 필드와 같습니다: `time⇥author⇥text` (한 줄에 하나)

## 통신 프로토콜

한 줄 = 메시지 하나, 필드 구분자 = 탭(`⇥`)

```mermaid
flowchart LR
    subgraph REQ["Client → Server · request"]
        direction TB
        r1["SAY⇥text<br/>채팅"]
        r2["NICK⇥name<br/>닉네임 변경"]
        r3["WHO<br/>접속자 목록"]
        r4["HIST<br/>최근 대화"]
        r5["QUIT<br/>종료"]
    end
    subgraph RES["Server → Client · response"]
        direction TB
        s1["MSG⇥time⇥author⇥text<br/>채팅 메시지"]
        s2["SYS⇥text<br/>안내"]
        s3["USERS⇥a,b,c<br/>접속자 목록"]
        s4["ERR⇥text<br/>거절 사유"]
    end
    r1 --> s1
    r2 --> s2
    r2 --> s4
    r3 --> s3
    r4 --> s1
```

| 방향 | 형식 |
|---|---|
| Client → Server | `SAY<TAB>text` · `NICK<TAB>name` · `WHO` · `HIST` · `QUIT` |
| Server → Client | `MSG<TAB>time<TAB>author<TAB>text` · `SYS<TAB>text` · `USERS<TAB>a,b,c` · `ERR<TAB>text` |

## 요구 사항

- OCaml 5.x (opam) — 표준 배포판의 `unix`, `threads`만 사용, 추가 패키지 불필요
- Windows: `winget install OCaml.opam` → `opam init`

## 빌드

```powershell
.\build.ps1
```

`bin\server.exe`, `bin\client.exe`(네이티브)와 `bin\server.byte`, `bin\client.byte`(바이트코드)가 생성됩니다.
중간 파일은 `_build\`에 생깁니다.

```mermaid
flowchart LR
    subgraph SRC["소스 (의존 순서대로 나열)"]
        direction TB
        SV["server:<br/>sync → text → message → protocol<br/>→ repository → model → chat_service → server"]
        CLS["client:<br/>text → message → protocol<br/>→ view → controller → client"]
    end

    SV -- "Copy-Item" --> WS["_build\server 작업 폴더"]
    CLS -- "Copy-Item" --> WC["_build\client 작업 폴더"]

    WS -- "ocamlopt<br/>unix.cmxa threads.cmxa" --> SE["bin\server.exe"]
    WS -- "ocamlc<br/>unix.cma threads.cma" --> SB["bin\server.byte"]
    WC -- "ocamlopt" --> CE["bin\client.exe"]
    WC -- "ocamlc" --> CB["bin\client.byte"]

    SB -. "run-server.ps1<br/>ocamlrun" .-> RUN1(("서버"))
    CE -. "run-client.ps1" .-> RUN2(("클라이언트"))
```

> OCaml은 모듈을 **사용 전에** 컴파일해야 하므로 `build.ps1`의 소스 목록은 의존 순서를 지켜야 합니다. 새 모듈을 추가하면 이 목록에 알맞은 위치로 넣으세요.

## 실행

```powershell
.\run-server.ps1                     # 서버 (기본 포트 9000)
.\run-client.ps1                     # 클라이언트 — 터미널 여러 개에서 실행
.\run-client.ps1 192.168.0.10 9000   # 다른 PC의 서버에 접속
```

> 일부 백신이 새로 컴파일된 `server.exe`를 오탐할 수 있어 `run-server.ps1`은 바이트코드(`ocamlrun bin\server.byte`)로 실행합니다.

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
[03:15:03] alice: Hello bob!
[03:15:03] bob: Hi alice, OCaml chat works
*** online (2): alice, bob
```
