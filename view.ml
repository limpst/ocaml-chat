(* ===== MVC: View  (Presentation Tier) =====
   화면 출력만 담당한다. 데이터를 받아 문자열로 그린다. *)

let time_str t =
  let tm = Unix.localtime t in
  Printf.sprintf "%02d:%02d:%02d" tm.tm_hour tm.tm_min tm.tm_sec

let render = function
  | Protocol.Msg m ->
      Printf.printf "[%s] %s: %s\n%!" (time_str m.Model.time) m.Model.author m.Model.text
  | Protocol.Sys t -> Printf.printf "*** %s\n%!" t
  | Protocol.Users l ->
      Printf.printf "*** online (%d): %s\n%!" (List.length l) (String.concat ", " l)
  | Protocol.Err t -> Printf.printf "!!! %s\n%!" t

let info fmt = Printf.ksprintf (fun s -> Printf.printf "%s\n%!" s) fmt

let help () =
  info "Commands:\n  /nick NAME   change nickname\n  /who         list online users\n  /history     show recent messages\n  /quit        exit\n  (anything else is sent as a chat message)"
