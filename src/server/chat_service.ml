(* =========================================================================
   Chat_service — 3-Tier: Business Logic Tier  /  MVC: Controller (서버)
   -------------------------------------------------------------------------
   모든 메시지 처리는 여기서 한다.
     요청 수신 → Model 갱신 → Repository(Data Tier) 저장 → 접속자 전원에게 전송
   소켓을 직접 다루지 않고, 세션에 들어 있는 send_line 함수만 사용한다.
   ========================================================================= *)

open Protocol  (* request / response 생성자(Say, Chat, Notice ...)를 짧게 쓰기 위해 *)

(* 서버 전체에서 하나만 쓰는 채팅방 *)
let room = Model.create_room ()

(* 입장할 때 보여 줄 최근 메시지 수 / /history 요청 시 보여 줄 수 *)
let history_on_join = 5
let history_on_request = 20

(* 서버 콘솔 로그: log "%s connected" nick  →  "[server] alice connected" *)
let log format =
  Printf.ksprintf (fun text -> print_endline ("[server] " ^ text)) format

(* ---------------------------------------------------------------------
   전송 도우미
   --------------------------------------------------------------------- *)

(* [reply session response] — 요청한 한 사람에게만 응답 *)
let reply (session : Model.session) (response : response) : unit =
  session.send_line (encode_response response)

(* [broadcast response] — 접속자 전원에게 전송 *)
let broadcast (response : response) : unit =
  let line = encode_response response in             (* 한 번만 인코딩해서 재사용 *)
  Model.all_sessions room                            (* 잠금 밖에서 쓸 세션 목록 복사본 *)
  |> List.iter (fun (session : Model.session) ->
         try session.send_line line                  (* 각자에게 전송 *)
         with _ -> ())                               (* 이미 끊긴 소켓이면 조용히 무시 *)

(* ---------------------------------------------------------------------
   접속 / 종료
   --------------------------------------------------------------------- *)

(* 새 클라이언트 접속: 세션 등록 → 환영 인사 → 최근 대화 → 입장 알림 *)
let on_connect ~(send_line : string -> unit) : Model.session =
  let session = Model.add_session room ~send_line in                  (* 1. 세션 등록 *)
  log "%s connected" session.nick;                                    (* 2. 서버 로그 *)
  reply session                                                       (* 3. 환영 인사 *)
    (Notice ("Welcome, " ^ session.nick
             ^ "! Commands: /nick NAME, /who, /history, /quit"));
  Repository.load_recent history_on_join                              (* 4. 최근 대화 보여주기 *)
  |> List.iter (fun message -> reply session (Chat message));
  broadcast (Notice (session.nick ^ " joined the chat"));             (* 5. 모두에게 입장 알림 *)
  session

(* 클라이언트 종료: 세션 제거 → 퇴장 알림 *)
let on_disconnect (session : Model.session) : unit =
  Model.remove_session room session;                                  (* 1. 목록에서 제거 *)
  log "%s disconnected" session.nick;                                 (* 2. 서버 로그 *)
  broadcast (Notice (session.nick ^ " left the chat"))                (* 3. 남은 사람에게 알림 *)

(* ---------------------------------------------------------------------
   요청별 처리 함수
   --------------------------------------------------------------------- *)

(* SAY: 채팅 메시지 → 저장 후 전원에게 전송 *)
let handle_say (session : Model.session) (raw_text : string) : unit =
  let text = String.trim raw_text in                       (* 앞뒤 공백 제거 *)
  if text <> "" then begin                                 (* 빈 메시지는 무시 *)
    let message = Message.make ~author:session.nick ~text in  (* 메시지 생성 (현재 시각) *)
    Repository.save message;                               (* Data Tier 에 저장 *)
    log "%s: %s" message.author message.text;              (* 서버 로그 *)
    broadcast (Chat message)                               (* 전원에게 전송 *)
  end

(* NICK: 닉네임 변경 → 성공하면 전원에게 알림, 실패하면 본인에게만 사유 *)
let handle_change_nick (session : Model.session) (new_nick : string) : unit =
  match Model.rename room session new_nick with
  | Ok old_nick ->                                         (* 성공 *)
      log "%s -> %s" old_nick new_nick;
      broadcast (Notice (old_nick ^ " is now known as " ^ new_nick))
  | Error reason ->                                        (* 실패 *)
      reply session (Rejected reason)

(* WHO: 접속자 목록을 요청한 사람에게만 *)
let handle_list_users (session : Model.session) : unit =
  reply session (User_list (Model.nicknames room))

(* HIST: 최근 대화를 요청한 사람에게만 *)
let handle_show_history (session : Model.session) : unit =
  match Repository.load_recent history_on_request with
  | [] -> reply session (Notice "no history yet")          (* 저장된 대화 없음 *)
  | messages ->
      reply session (Notice "---- last messages ----");    (* 구분선 *)
      List.iter (fun message -> reply session (Chat message)) messages

(* ---------------------------------------------------------------------
   요청 분배 (dispatcher)
   --------------------------------------------------------------------- *)

(* 요청 처리 후 연결을 계속 유지할지 *)
type next_step = Keep_connection | Close_connection

(* 요청 종류에 맞는 처리 함수를 호출한다 *)
let handle_request (session : Model.session) (request : request) : next_step =
  match request with
  | Say text -> handle_say session text; Keep_connection
  | Change_nick name -> handle_change_nick session name; Keep_connection
  | List_users -> handle_list_users session; Keep_connection
  | Show_history -> handle_show_history session; Keep_connection
  | Quit -> Close_connection                               (* 종료 요청 → 연결 닫기 *)
