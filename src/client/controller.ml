(* =========================================================================
   Controller — MVC: Controller (클라이언트, Presentation Tier)
   -------------------------------------------------------------------------
   두 방향의 흐름을 연결한다.
     키보드 입력 한 줄  →  interpret_input  →  서버에 보낼 요청
     서버에서 온 한 줄  →  handle_server_line → View 로 출력
   ========================================================================= *)

(* 사용자 입력 한 줄을 해석한 결과 *)
type action =
  | Send of Protocol.request  (* 서버에 요청 보내기 *)
  | Show_help                 (* 도움말 출력 (잘못된 명령) *)
  | Do_nothing                (* 빈 줄 등 → 무시 *)

(* "/nick alice" → ("/nick", "alice"),  "/who" → ("/who", "") *)
let split_command (line : string) : string * string =
  match String.index_opt line ' ' with                 (* 첫 공백 위치 찾기 *)
  | None -> (line, "")                                 (* 공백 없음: 명령만 있음 *)
  | Some space ->
      let command = String.sub line 0 space in         (* 공백 앞: 명령 *)
      let argument =                                   (* 공백 뒤: 인자 *)
        String.sub line (space + 1) (String.length line - space - 1)
      in
      (command, String.trim argument)

(* "/" 로 시작하는 명령 → 행동 *)
let interpret_command (command : string) (argument : string) : action =
  match command, argument with
  | "/nick", "" -> Show_help                           (* 이름 없이 /nick → 도움말 *)
  | "/nick", name -> Send (Protocol.Change_nick name)
  | "/who", _ -> Send Protocol.List_users
  | "/history", _ -> Send Protocol.Show_history
  | "/quit", _ -> Send Protocol.Quit
  | _ -> Show_help                                     (* 모르는 명령 → 도움말 *)

(* 키보드 입력 한 줄 → 행동 *)
let interpret_input (raw_line : string) : action =
  let line = String.trim (Text.strip_bom raw_line) in  (* BOM·앞뒤 공백 제거 *)
  if line = "" then Do_nothing                         (* 빈 줄 *)
  else if line.[0] = '/' then                          (* 명령 *)
    let command, argument = split_command line in
    interpret_command command argument
  else Send (Protocol.Say line)                        (* 그 외는 채팅 메시지 *)

(* 서버에서 받은 한 줄 → 해석해서 View 에 출력 *)
let handle_server_line (line : string) : unit =
  match Protocol.decode_response line with
  | Some response -> View.render response              (* 정상 응답 *)
  | None -> View.show_unknown_data line                (* 알 수 없는 형식 *)
