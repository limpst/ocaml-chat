(* =========================================================================
   Client — 클라이언트 진입점 (Presentation Tier 실행 파일)
   -------------------------------------------------------------------------
   스레드 두 개로 동작한다.
     메인 스레드 : 키보드 입력 → Controller 해석 → 소켓으로 전송
     수신 스레드 : 소켓에서 한 줄 수신 → Controller → View 출력

   사용법:  client.exe [호스트] [포트]      (기본 127.0.0.1 9000)
   ========================================================================= *)

let default_host = "127.0.0.1"
let default_port = 9000

(* argv.(index) 가 있으면 그 값, 없으면 기본값 *)
let argument_or (index : int) (default : string) : string =
  if Array.length Sys.argv > index then Sys.argv.(index) else default

(* "127.0.0.1" 같은 IP 는 그대로, "localhost" 같은 이름은 DNS 조회 *)
let resolve_address (host : string) : Unix.inet_addr =
  try Unix.inet_addr_of_string host                    (* IP 문자열로 해석 시도 *)
  with Failure _ ->                                    (* 실패하면 호스트 이름으로 간주 *)
    (Unix.gethostbyname host).h_addr_list.(0)          (* 첫 번째 주소 사용 *)

(* 서버에 접속한다. 실패하면 이유를 출력하고 프로그램 종료 *)
let connect_to_server (host : string) (port : int) : Unix.file_descr =
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in       (* IPv4 TCP 소켓 *)
  try
    Unix.connect socket (Unix.ADDR_INET (resolve_address host, port)); (* 접속 시도 *)
    socket
  with Unix.Unix_error (error, _, _) ->
    View.show_connection_failed host port (Unix.error_message error);
    exit 1

(* 요청 하나를 한 줄로 인코딩해서 서버로 보내는 함수를 만든다 *)
let make_request_sender (output : out_channel) : Protocol.request -> unit =
  fun request ->
    output_string output (Protocol.encode_request request);  (* "SAY\thello" 등 *)
    output_char output '\n';                                 (* 줄바꿈 = 메시지 끝 *)
    flush output                                             (* 즉시 전송 *)

(* 수신 스레드: 서버가 보내는 줄을 계속 받아서 화면에 출력.
   서버가 연결을 끊으면 안내를 출력하고 프로그램 전체를 종료한다. *)
let start_receiver (input : in_channel) : Thread.t =
  Thread.create
    (fun () ->
      (try
         while true do
           Controller.handle_server_line (input_line input)  (* 한 줄 받아서 처리 *)
         done
       with _ -> ());                                        (* 연결 끊김 → 반복 종료 *)
      View.show_disconnected ();
      exit 0)                                                (* 입력 대기 중인 메인 스레드도 함께 종료 *)
    ()

(* 메인 스레드: 키보드 입력을 읽어 처리. /quit 또는 입력 끝(Ctrl+Z)이면 멈춘다 *)
let rec read_keyboard_loop (send : Protocol.request -> unit) : unit =
  match input_line stdin with
  | exception End_of_file -> send Protocol.Quit                (* 입력 끝 → 종료 요청 *)
  | line -> (
      match Controller.interpret_input line with
      | Send Protocol.Quit -> send Protocol.Quit               (* 종료 요청 후 반복 중단 *)
      | Send request -> send request; read_keyboard_loop send  (* 전송하고 계속 *)
      | Show_help -> View.show_help (); read_keyboard_loop send
      | Do_nothing -> read_keyboard_loop send)

let () =
  let host = argument_or 1 default_host in                          (* 접속할 호스트 *)
  let port = int_of_string (argument_or 2 (string_of_int default_port)) in  (* 접속할 포트 *)
  let socket = connect_to_server host port in                       (* 1. 접속 *)
  let input = Unix.in_channel_of_descr socket in                    (* 소켓 → 읽기 채널 *)
  let output = Unix.out_channel_of_descr socket in                  (* 소켓 → 쓰기 채널 *)
  let receiver = start_receiver input in                            (* 2. 수신 스레드 시작 *)
  View.show_connected host port;
  (try read_keyboard_loop (make_request_sender output)              (* 3. 키보드 입력 처리 *)
   with _ -> ());                                                   (*    전송 실패(서버 종료) 등 무시 *)
  Thread.join receiver                                              (* 4. 서버가 연결을 닫을 때까지 대기 *)
