(* =========================================================================
   Server — 서버 진입점 (Business Logic Tier 실행 파일)
   -------------------------------------------------------------------------
   TCP 소켓으로 접속을 기다리고, 접속한 클라이언트마다 스레드를 하나씩 만든다.
   각 스레드는 "한 줄 읽기 → 요청 해석 → Chat_service 에 처리 맡기기"를 반복한다.

   사용법:  server.exe [포트]      (기본 포트 9000)
   ========================================================================= *)

let default_port = 9000

(* 명령줄 첫 번째 인자가 있으면 포트로 사용, 없으면 기본값 *)
let port_from_command_line () : int =
  if Array.length Sys.argv > 1                     (* argv.(0) 은 프로그램 이름 *)
  then int_of_string Sys.argv.(1)
  else default_port

(* [make_line_sender output]
   소켓 출력 채널에 "한 줄 + 줄바꿈"을 보내는 함수를 만든다.
   한 소켓에 여러 스레드(브로드캐스트)가 동시에 쓰면 줄이 섞이므로 소켓마다 잠금을 둔다. *)
let make_line_sender (output : out_channel) : string -> unit =
  let write_lock = Mutex.create () in              (* 이 소켓 전용 잠금 *)
  fun line ->
    Sync.with_lock write_lock (fun () ->
        output_string output line;                 (* 내용 *)
        output_char output '\n';                   (* 줄바꿈 = 메시지 끝 *)
        flush output)                              (* 버퍼를 비워 즉시 전송 *)

(* [serve_requests input session]
   연결이 끊기거나 QUIT 요청이 올 때까지 요청을 한 줄씩 처리한다. *)
let rec serve_requests (input : in_channel) (session : Model.session) : unit =
  match input_line input with
  | exception (End_of_file | Sys_error _ | Unix.Unix_error _) ->
      ()                                           (* 클라이언트가 연결을 끊음 → 종료 *)
  | line -> (
      match Protocol.decode_request line with
      | None ->                                    (* 알 수 없는 형식 *)
          Chat_service.reply session (Protocol.Rejected "bad request");
          serve_requests input session             (* 다음 줄 계속 *)
      | Some request -> (
          match Chat_service.handle_request session request with
          | Keep_connection -> serve_requests input session   (* 다음 줄 계속 *)
          | Close_connection -> ()))                         (* QUIT → 종료 *)

(* 소켓을 닫는다. 이미 닫혔을 수도 있으므로 오류는 무시 *)
let close_socket (socket : Unix.file_descr) : unit =
  (try Unix.shutdown socket Unix.SHUTDOWN_ALL with _ -> ());  (* 송수신 중단 알림 *)
  try Unix.close socket with _ -> ()                          (* 자원 해제 *)

(* 클라이언트 하나를 처음부터 끝까지 담당하는 스레드 본문 *)
let handle_client (socket : Unix.file_descr) : unit =
  let input = Unix.in_channel_of_descr socket in     (* 소켓 → 읽기 채널 *)
  let output = Unix.out_channel_of_descr socket in   (* 소켓 → 쓰기 채널 *)
  let session =
    Chat_service.on_connect ~send_line:(make_line_sender output)  (* 1. 접속 처리 *)
  in
  (try serve_requests input session                  (* 2. 요청 반복 처리 *)
   with error ->                                     (*    예상 못 한 오류는 로그만 남김 *)
     Chat_service.log "client error: %s" (Printexc.to_string error));
  Chat_service.on_disconnect session;                (* 3. 종료 처리 (퇴장 알림) *)
  close_socket socket                                (* 4. 소켓 닫기 *)

(* 지정한 포트에서 접속을 기다리는 서버 소켓을 만든다 *)
let create_listening_socket (port : int) : Unix.file_descr =
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in   (* IPv4 TCP 소켓 *)
  Unix.setsockopt socket Unix.SO_REUSEADDR true;                (* 재시작 시 포트 즉시 재사용 *)
  Unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_any, port)); (* 모든 네트워크 주소의 port 에 연결 *)
  Unix.listen socket 16;                                        (* 대기열 최대 16 *)
  socket

let () =
  (* 끊긴 소켓에 쓸 때 프로세스가 죽지 않도록 SIGPIPE 무시 (Windows 에는 없어서 try) *)
  (try Sys.set_signal Sys.sigpipe Sys.Signal_ignore with _ -> ());
  let port = port_from_command_line () in
  let server_socket = create_listening_socket port in
  Chat_service.log "listening on port %d (history: %s)" port Repository.file_path;
  while true do                                                 (* 서버는 끝없이 접속을 받는다 *)
    let client_socket, _client_address = Unix.accept server_socket in  (* 접속이 올 때까지 대기 *)
    ignore (Thread.create handle_client client_socket)                 (* 클라이언트별 스레드 시작 *)
  done
