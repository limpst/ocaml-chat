(* ===== Client <-> Server 소켓 통신 규약 =====
   한 줄 = 한 메시지, 필드 구분자는 탭(\t).
     Client -> Server : SAY<TAB>text | NICK<TAB>name | WHO | HIST | QUIT
     Server -> Client : MSG<TAB>time<TAB>author<TAB>text | SYS<TAB>text
                        | USERS<TAB>a,b,c | ERR<TAB>text *)

type request = Say of string | Nick of string | Who | History | Quit

type response =
  | Msg of Model.message
  | Sys of string
  | Users of string list
  | Err of string

let clean s = String.map (function '\t' | '\n' | '\r' -> ' ' | c -> c) s

(* 소켓에서 읽은 줄의 끝에 붙은 \r 제거 *)
let strip_cr s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s

let encode_request = function
  | Say t -> "SAY\t" ^ clean t
  | Nick n -> "NICK\t" ^ clean n
  | Who -> "WHO"
  | History -> "HIST"
  | Quit -> "QUIT"

let decode_request line =
  match String.split_on_char '\t' (strip_cr line) with
  | [ "SAY"; t ] -> Some (Say t)
  | [ "NICK"; n ] -> Some (Nick n)
  | [ "WHO" ] -> Some Who
  | [ "HIST" ] -> Some History
  | [ "QUIT" ] -> Some Quit
  | _ -> None

let encode_response = function
  | Msg m ->
      Printf.sprintf "MSG\t%.0f\t%s\t%s" m.Model.time (clean m.Model.author) (clean m.Model.text)
  | Sys t -> "SYS\t" ^ clean t
  | Users l -> "USERS\t" ^ String.concat "," l
  | Err t -> "ERR\t" ^ clean t

let decode_response line =
  match String.split_on_char '\t' (strip_cr line) with
  | [ "MSG"; t; author; text ] -> (
      match float_of_string_opt t with
      | Some time -> Some (Msg { Model.time; author; text })
      | None -> None)
  | [ "SYS"; t ] -> Some (Sys t)
  | [ "USERS"; l ] -> Some (Users (if l = "" then [] else String.split_on_char ',' l))
  | [ "ERR"; t ] -> Some (Err t)
  | _ -> None
