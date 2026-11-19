# 요청 처리 흐름

[← README](../README.md) · [아키텍처](architecture.md) · **요청 흐름** · [동시성](concurrency.md) · [프로토콜](protocol.md) · [빌드 · CI](build.md)

## 채팅 메시지 (`SAY`)

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

빈 메시지(공백만 있는 줄)는 `handle_say`에서 무시되고 저장 · 전송하지 않습니다.

## 클라이언트 연결 수명 주기 (서버)

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

## 닉네임 변경 (`/nick`)

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

`/nick`만 입력하고 이름을 비우면 서버로 보내지 않고 클라이언트에서 도움말을 출력합니다.

## 대화 기록 (입장 시 · `/history`)

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

저장 형식은 [프로토콜](protocol.md#저장-형식)을 보세요.
