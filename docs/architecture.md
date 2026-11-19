# 아키텍처

[← README](../README.md) · **아키텍처** · [요청 흐름](flows.md) · [동시성](concurrency.md) · [프로토콜](protocol.md) · [빌드 · CI](build.md)

OCaml Chat은 **3-Tier 아키텍처** 위에 **MVC 패턴**을 얹은 구조입니다.
메시지 처리(검증 · 저장 · 전송)는 모두 서버에서 이루어지고, 클라이언트는 입력과 화면 출력만 담당합니다.

## 계층 구조

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

| 계층 | 폴더 | 역할 | MVC |
|---|---|---|---|
| Tier 1. Presentation | `src/client` | 키보드 입력 해석, 서버 응답 출력 | View · Controller |
| Tier 2. Business Logic | `src/server` | 요청 처리, 상태 관리, 브로드캐스트 | Model · Controller |
| Tier 3. Data | `src/data` | 메시지 영속화 (`chat_history.log`) | — |
| 공용 | `src/shared` | 메시지 타입, 프로토콜, 문자열 · 잠금 도우미 | Model 데이터 |

> Tier 2는 `repository.ml`의 `save` / `load_recent` 두 함수만 사용합니다. 저장소를 DB로 바꿔도 `repository.ml`만 고치면 됩니다.

## 모듈 의존 관계

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

> 화살표는 "사용한다" 방향입니다. 빌드 순서는 아래(shared) → 위(server / client)입니다. 자세한 내용은 [빌드 · CI](build.md)를 보세요.

## 데이터 모델

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

## 클라이언트 접속 상태

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
