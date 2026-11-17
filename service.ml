(* ===== 3-Tier: Business Logic Tier  /  MVC: Controller (서버 측) =====
   클라이언트 요청을 해석해서 Model을 갱신하고,
   Data Tier(Repository)에 저장한 뒤 접속자 전원에게 브로드캐스트한다.
   메시지 처리는 모두 여기, 서버에서 이루어진다. *)

open Protocol

let room = Model.create_room ()

let log fmt = Printf.ksprintf (fun s -> Printf.printf "[server] %s\n%!" s) fmt

let send (s : Model.session) r = s.send (encode_response r)

let broadcast r =
  let line = encode_response r in
  List.iter
    (fun (s : Model.session) -> try s.send line with _ -> () (* 끊긴 소켓은 무시 *))
    (Model.snapshot room)

let on_connect send_line =
  let s = Model.join room send_line in
  log "%s connected" s.nick;
  send s (Sys (Printf.sprintf "Welcome, %s! Commands: /nick NAME, /who, /history, /quit" s.nick));
  List.iter (fun m -> send s (Msg m)) (Repository.load_recent 5);
  broadcast (Sys (s.nick ^ " joined the chat"));
  s

let on_disconnect (s : Model.session) =
  Model.leave room s;
  log "%s disconnected" s.nick;
  broadcast (Sys (s.nick ^ " left the chat"))

(* 요청 하나를 처리한다. 연결을 끊어야 하면 false *)
let handle (s : Model.session) = function
  | Say text when String.trim text = "" -> true
  | Say text ->
      let m = { Model.time = Unix.time (); author = s.nick; text = String.trim text } in
      Repository.save m;                 (* Data Tier 저장 *)
      log "%s: %s" m.author m.text;
      broadcast (Msg m);                 (* 전체 전송 *)
      true
  | Nick n ->
      (match Model.rename room s n with
       | Ok old ->
           log "%s -> %s" old n;
           broadcast (Sys (old ^ " is now known as " ^ n))
       | Error e -> send s (Err e));
      true
  | Who ->
      send s (Users (Model.nicks room));
      true
  | History ->
      (match Repository.load_recent 20 with
       | [] -> send s (Sys "no history yet")
       | h ->
           send s (Sys "---- last messages ----");
           List.iter (fun m -> send s (Msg m)) h);
      true
  | Quit -> false
