(* ===== MVC: Model =====
   도메인 데이터(메시지, 접속 세션)와 채팅방 상태.
   여러 클라이언트 스레드가 동시에 접근하므로 Mutex로 보호한다. *)

type message = { time : float; author : string; text : string }

type session = {
  id : int;
  mutable nick : string;
  send : string -> unit;  (* 이 세션의 소켓으로 한 줄을 보내는 함수 *)
}

type room = {
  mutable sessions : session list;
  mutable next_id : int;
  lock : Mutex.t;
}

let create_room () = { sessions = []; next_id = 1; lock = Mutex.create () }

let locked r f =
  Mutex.lock r.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock r.lock) f

let join r send =
  locked r (fun () ->
      let s = { id = r.next_id; nick = Printf.sprintf "guest%d" r.next_id; send } in
      r.next_id <- r.next_id + 1;
      r.sessions <- r.sessions @ [ s ];
      s)

let leave r s =
  locked r (fun () -> r.sessions <- List.filter (fun x -> x.id <> s.id) r.sessions)

let valid_nick n =
  n <> ""
  && String.length n <= 16
  && String.for_all
       (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' -> true | _ -> false)
       n

let rename r s n =
  locked r (fun () ->
      if not (valid_nick n) then Error "invalid nickname (1-16 chars: a-z A-Z 0-9 _ -)"
      else if List.exists (fun x -> x.id <> s.id && x.nick = n) r.sessions then
        Error "nickname already in use"
      else begin
        let old = s.nick in
        s.nick <- n;
        Ok old
      end)

let nicks r = locked r (fun () -> List.map (fun s -> s.nick) r.sessions)

(* 브로드캐스트용 복사본: 락을 잡은 채로 소켓 I/O를 하지 않기 위함 *)
let snapshot r = locked r (fun () -> r.sessions)
