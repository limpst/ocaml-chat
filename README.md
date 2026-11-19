# OCaml Chat

OCaml로 작성한 TCP 소켓 기반 멀티 유저 채팅 프로그램입니다.
**3-Tier 아키텍처**와 **MVC 패턴**으로 구성되어 있으며, 메시지 처리는 모두 서버에서 이루어집니다.

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
