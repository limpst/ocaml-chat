(* ===== 서버 진입점 (Business Logic Tier 실행 파일) =====
   TCP 소켓으로 접속을 받고, 클라이언트마다 스레드를 하나씩 만든다.
   사용법: server.exe [port]   (기본 포트 9000) *)

let handle_client fd =
  let ic = Unix.in_channel_of_descr fd in
  let oc = Unix.out_channel_of_descr fd in
  let wlock = Mutex.create () in
  (* 여러 스레드가 같은 소켓에 동시에 쓰지 않도록 소켓마다 락을 둔다 *)
  let send_line line =
    Mutex.lock wlock;
    Fun.protect
      ~finally:(fun () -> Mutex.unlock wlock)
      (fun () -> output_string oc line; output_char oc '\n'; flush oc)
  in
  let s = Service.on_connect send_line in
  let rec loop () =
    match input_line ic with
    | exception (End_of_file | Sys_error _ | Unix.Unix_error _) -> ()
    | line -> (
        match Protocol.decode_request line with
        | Some req -> if Service.handle s req then loop ()
        | None ->
            Service.send s (Protocol.Err "bad request");
            loop ())
  in
  (try loop () with e -> Service.log "client error: %s" (Printexc.to_string e));
  Service.on_disconnect s;
  (try Unix.shutdown fd Unix.SHUTDOWN_ALL with _ -> ());
  try Unix.close fd with _ -> ()

let () =
  (try Sys.set_signal Sys.sigpipe Sys.Signal_ignore with _ -> ());
  let port = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 9000 in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen sock 16;
  Service.log "listening on port %d (history: %s)" port !Repository.path;
  while true do
    let fd, _ = Unix.accept sock in
    ignore (Thread.create handle_client fd)
  done
