(* =========================================================================
   Model — MVC: Model (서버의 상태)
   -------------------------------------------------------------------------
   채팅방(room)과 접속 세션(session)을 관리한다.
   - 상태를 바꾸는 함수는 모두 room.lock 을 잡고 실행한다 (스레드 안전).
   - 소켓 I/O 는 여기서 하지 않는다. 전송은 Controller(Chat_service)의 몫이다.
   ========================================================================= *)

(* 접속한 클라이언트 한 명 *)
type session = {
  id : int;                    (* 접속 순서대로 붙는 고유 번호 *)
  mutable nick : string;       (* 닉네임 (바뀔 수 있으므로 mutable) *)
  send_line : string -> unit;  (* 이 클라이언트 소켓으로 한 줄을 보내는 함수 *)
}

(* 채팅방: 접속 중인 세션 전체 *)
type room = {
  mutable sessions : session list;  (* 접속 순서대로 정렬된 세션 목록 *)
  mutable next_id : int;            (* 다음 접속자에게 줄 번호 *)
  lock : Mutex.t;                   (* 이 방의 상태를 보호하는 잠금 *)
}

(* 빈 채팅방을 만든다 *)
let create_room () : room =
  { sessions = []; next_id = 1; lock = Mutex.create () }

(* [add_session room ~send_line] — 새 접속자를 "guest<번호>" 이름으로 등록 *)
let add_session (room : room) ~(send_line : string -> unit) : session =
  Sync.with_lock room.lock (fun () ->
      let id = room.next_id in                              (* 이번 접속자의 번호 *)
      let session = { id; nick = "guest" ^ string_of_int id; send_line } in  (* 기본 닉네임 *)
      room.next_id <- id + 1;                               (* 다음 번호 준비 *)
      room.sessions <- room.sessions @ [ session ];         (* 목록 맨 뒤에 추가 *)
      session)                                              (* 만든 세션 반환 *)

(* [remove_session room session] — 접속을 끊은 세션을 목록에서 뺀다 *)
let remove_session (room : room) (session : session) : unit =
  Sync.with_lock room.lock (fun () ->
      room.sessions <-
        List.filter (fun other -> other.id <> session.id) room.sessions)  (* 같은 id 만 제외 *)

(* 닉네임 규칙: 1~16자, 영문/숫자/밑줄/하이픈만 *)
let max_nick_length = 16

let is_allowed_nick_char (c : char) : bool =
  match c with
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' -> true  (* 허용 문자 *)
  | _ -> false                                                (* 나머지 금지 *)

let is_valid_nick (nick : string) : bool =
  nick <> ""                                       (* 비어 있지 않고 *)
  && String.length nick <= max_nick_length         (* 16자 이하이며 *)
  && String.for_all is_allowed_nick_char nick      (* 모든 문자가 허용 문자 *)

(* [rename room session new_nick]
   성공하면 Ok 이전닉네임, 실패하면 Error 사유 *)
let rename (room : room) (session : session) (new_nick : string) : (string, string) result =
  Sync.with_lock room.lock (fun () ->
      let taken_by_someone_else =                           (* 다른 사람이 이미 쓰는 이름인가? *)
        List.exists
          (fun other -> other.id <> session.id && other.nick = new_nick)
          room.sessions
      in
      if not (is_valid_nick new_nick) then
        Error "invalid nickname (1-16 chars: a-z A-Z 0-9 _ -)"   (* 규칙 위반 *)
      else if taken_by_someone_else then
        Error "nickname already in use"                          (* 중복 *)
      else begin
        let old_nick = session.nick in                      (* 바꾸기 전 이름 기억 *)
        session.nick <- new_nick;                           (* 새 이름으로 변경 *)
        Ok old_nick                                         (* 이전 이름을 돌려줌 (안내문용) *)
      end)

(* 현재 접속자 닉네임 목록 *)
let nicknames (room : room) : string list =
  Sync.with_lock room.lock (fun () ->
      List.map (fun session -> session.nick) room.sessions)

(* 현재 세션 목록의 복사본.
   잠금을 잡은 채 소켓 전송을 하면 느린 클라이언트 하나가 방 전체를 막으므로,
   목록만 복사해 두고 전송은 잠금 밖에서 한다. *)
let all_sessions (room : room) : session list =
  Sync.with_lock room.lock (fun () -> room.sessions)
