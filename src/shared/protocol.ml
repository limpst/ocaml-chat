(* =========================================================================
   Protocol — 클라이언트 ↔ 서버 소켓 통신 규약 (Tier 1 ↔ Tier 2 경계)
   -------------------------------------------------------------------------
   규칙: 한 줄 = 메시지 하나, 필드 구분자 = 탭(\t)

     클라이언트 → 서버 (request)
       SAY   <TAB> 본문          채팅 메시지 보내기
       NICK  <TAB> 새닉네임      닉네임 바꾸기
       WHO                        접속자 목록 요청
       HIST                       최근 대화 요청
       QUIT                       접속 종료

     서버 → 클라이언트 (response)
       MSG   <TAB> 시각 <TAB> 보낸사람 <TAB> 본문
       SYS   <TAB> 안내문
       USERS <TAB> 닉1,닉2,...
       ERR   <TAB> 거절 사유
   ========================================================================= *)

(* 클라이언트가 서버에 보내는 요청 *)
type request =
  | Say of string          (* 채팅 메시지 보내기 *)
  | Change_nick of string  (* 닉네임 바꾸기 *)
  | List_users             (* 접속자 목록 요청 *)
  | Show_history           (* 최근 대화 요청 *)
  | Quit                   (* 접속 종료 *)

(* 서버가 클라이언트에 보내는 응답 *)
type response =
  | Chat of Message.t      (* 누군가 보낸 채팅 메시지 *)
  | Notice of string       (* 서버 안내 (입장/퇴장/닉변경 등) *)
  | User_list of string list  (* 현재 접속자 닉네임 목록 *)
  | Rejected of string     (* 요청 거절 + 사유 *)

(* ---------------------------------------------------------------------
   request  <->  한 줄 문자열
   --------------------------------------------------------------------- *)

(* 요청 → 전송할 한 줄 *)
let encode_request (request : request) : string =
  match request with
  | Say text -> Text.join_fields [ "SAY"; Text.sanitize text ]           (* "SAY\t본문" *)
  | Change_nick name -> Text.join_fields [ "NICK"; Text.sanitize name ]  (* "NICK\t이름" *)
  | List_users -> "WHO"                                                  (* 인자 없음 *)
  | Show_history -> "HIST"                                               (* 인자 없음 *)
  | Quit -> "QUIT"                                                       (* 인자 없음 *)

(* 받은 한 줄 → 요청. 알 수 없는 형식이면 None *)
let decode_request (line : string) : request option =
  match Text.split_fields (Text.strip_cr line) with  (* 줄 끝 \r 제거 후 탭으로 분리 *)
  | [ "SAY"; text ] -> Some (Say text)
  | [ "NICK"; name ] -> Some (Change_nick name)
  | [ "WHO" ] -> Some List_users
  | [ "HIST" ] -> Some Show_history
  | [ "QUIT" ] -> Some Quit
  | _ -> None                                        (* 그 외는 잘못된 요청 *)

(* ---------------------------------------------------------------------
   response  <->  한 줄 문자열
   --------------------------------------------------------------------- *)

(* 응답 → 전송할 한 줄 *)
let encode_response (response : response) : string =
  match response with
  | Chat message -> Text.join_fields ("MSG" :: Message.to_fields message)   (* "MSG\t시각\t이름\t본문" *)
  | Notice text -> Text.join_fields [ "SYS"; Text.sanitize text ]          (* "SYS\t안내문" *)
  | User_list names -> Text.join_fields [ "USERS"; String.concat "," names ] (* "USERS\ta,b,c" *)
  | Rejected reason -> Text.join_fields [ "ERR"; Text.sanitize reason ]    (* "ERR\t사유" *)

(* 받은 한 줄 → 응답. 알 수 없는 형식이면 None *)
let decode_response (line : string) : response option =
  match Text.split_fields (Text.strip_cr line) with
  | "MSG" :: message_fields ->                                  (* 나머지 필드는 메시지 *)
      Option.map (fun message -> Chat message) (Message.of_fields message_fields)
  | [ "SYS"; text ] -> Some (Notice text)
  | [ "USERS"; "" ] -> Some (User_list [])                      (* 접속자가 없을 때 *)
  | [ "USERS"; names ] -> Some (User_list (String.split_on_char ',' names))
  | [ "ERR"; reason ] -> Some (Rejected reason)
  | _ -> None
