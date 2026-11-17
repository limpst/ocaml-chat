(* =========================================================================
   View — MVC: View (Presentation Tier)
   -------------------------------------------------------------------------
   화면 출력만 담당한다. 데이터를 받아 문자열로 그려서 콘솔에 찍는다.
   출력 형식을 바꾸고 싶으면 이 파일만 고치면 된다.
   ========================================================================= *)

(* 한 줄 출력 후 즉시 화면에 표시 (수신 스레드와 입력이 섞여도 바로 보이도록) *)
let print_line (text : string) : unit =
  print_string text;   (* 내용 *)
  print_newline ()     (* 줄바꿈 + flush *)

(* epoch 초 → "HH:MM:SS" (이 PC 의 지역 시간) *)
let format_clock (time : float) : string =
  let tm = Unix.localtime time in
  Printf.sprintf "%02d:%02d:%02d" tm.tm_hour tm.tm_min tm.tm_sec

(* 서버 응답 하나를 화면에 그린다 *)
let render (response : Protocol.response) : unit =
  match response with
  | Chat message ->                                    (* [12:00:00] alice: hi *)
      print_line
        (Printf.sprintf "[%s] %s: %s"
           (format_clock message.time) message.author message.text)
  | Notice text ->                                     (* *** bob joined the chat *)
      print_line ("*** " ^ text)
  | User_list names ->                                 (* *** online (2): alice, bob *)
      print_line
        (Printf.sprintf "*** online (%d): %s"
           (List.length names) (String.concat ", " names))
  | Rejected reason ->                                 (* !!! nickname already in use *)
      print_line ("!!! " ^ reason)

(* ---------------------------------------------------------------------
   클라이언트 상태 안내 문구
   --------------------------------------------------------------------- *)

let show_connected (host : string) (port : int) : unit =
  print_line (Printf.sprintf "connected to %s:%d" host port)

let show_connection_failed (host : string) (port : int) (reason : string) : unit =
  print_line (Printf.sprintf "cannot connect to %s:%d (%s)" host port reason)

let show_disconnected () : unit =
  print_line "*** disconnected from server"

let show_unknown_data (line : string) : unit =
  print_line ("(unknown data from server: " ^ line ^ ")")

let show_help () : unit =
  List.iter print_line
    [ "Commands:";
      "  /nick NAME   change nickname";
      "  /who         list online users";
      "  /history     show recent messages";
      "  /quit        exit";
      "  (anything else is sent as a chat message)" ]
