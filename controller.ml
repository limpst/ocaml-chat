(* ===== MVC: Controller (클라이언트 측, Presentation Tier) =====
   사용자 입력을 서버 요청으로 바꾸고, 서버 응답을 View에 넘긴다. *)

type action = Send of Protocol.request | Help | Ignore

(* 파이프/파일 입력 첫 줄에 붙는 UTF-8 BOM 제거 *)
let strip_bom s =
  if String.length s >= 3 && String.sub s 0 3 = "\xEF\xBB\xBF" then
    String.sub s 3 (String.length s - 3)
  else s

let parse_input line =
  let line = String.trim (strip_bom line) in
  if line = "" then Ignore
  else if line.[0] <> '/' then Send (Protocol.Say line)
  else
    let cmd, arg =
      match String.index_opt line ' ' with
      | Some i ->
          (String.sub line 0 i, String.trim (String.sub line i (String.length line - i)))
      | None -> (line, "")
    in
    match cmd with
    | "/nick" when arg <> "" -> Send (Protocol.Nick arg)
    | "/who" -> Send Protocol.Who
    | "/history" -> Send Protocol.History
    | "/quit" -> Send Protocol.Quit
    | _ -> Help

let on_server_line line =
  match Protocol.decode_response line with
  | Some r -> View.render r
  | None -> View.info "(unknown data from server: %s)" line
