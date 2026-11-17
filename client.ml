(* ===== 클라이언트 진입점 (Presentation Tier 실행 파일) =====
   사용법: client.exe [host] [port]   (기본 127.0.0.1 9000)
   - 메인 스레드  : 키보드 입력 -> Controller -> 소켓 전송
   - 수신 스레드  : 소켓 수신 -> Controller -> View *)

let resolve host =
  try Unix.inet_addr_of_string host
  with Failure _ -> (Unix.gethostbyname host).Unix.h_addr_list.(0)

let () =
  let host = if Array.length Sys.argv > 1 then Sys.argv.(1) else "127.0.0.1" in
  let port = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 9000 in
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  (try Unix.connect fd (Unix.ADDR_INET (resolve host, port))
   with Unix.Unix_error (e, _, _) ->
     View.info "cannot connect to %s:%d (%s)" host port (Unix.error_message e);
     exit 1);
  let ic = Unix.in_channel_of_descr fd in
  let oc = Unix.out_channel_of_descr fd in
  let send req =
    output_string oc (Protocol.encode_request req);
    output_char oc '\n';
    flush oc
  in
  let receiver =
    Thread.create
      (fun () ->
        (try
           while true do
             Controller.on_server_line (input_line ic)
           done
         with _ -> ());
        View.info "*** disconnected from server";
        exit 0)
      ()
  in
  View.info "connected to %s:%d" host port;
  let rec loop () =
    match input_line stdin with
    | exception End_of_file -> send Protocol.Quit
    | line -> (
        match Controller.parse_input line with
        | Controller.Send Protocol.Quit -> send Protocol.Quit
        | Controller.Send req -> send req; loop ()
        | Controller.Help -> View.help (); loop ()
        | Controller.Ignore -> loop ())
  in
  (try loop () with _ -> ());
  Thread.join receiver
