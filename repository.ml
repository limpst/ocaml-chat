(* ===== 3-Tier: Data Tier =====
   채팅 메시지 영속화. 파일(chat_history.log)에 한 줄씩 TSV로 저장한다.
   저장 방식을 DB로 바꾸더라도 이 모듈만 교체하면 된다. *)

let path = ref "chat_history.log"
let lock = Mutex.create ()

let locked f =
  Mutex.lock lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock lock) f

let clean s = String.map (function '\t' | '\n' | '\r' -> ' ' | c -> c) s

let save (m : Model.message) =
  locked (fun () ->
      let oc =
        open_out_gen [ Open_wronly; Open_append; Open_creat; Open_binary ] 0o644 !path
      in
      Printf.fprintf oc "%.0f\t%s\t%s\n" m.time (clean m.author) (clean m.text);
      close_out oc)

let parse line : Model.message option =
  match String.split_on_char '\t' line with
  | [ t; author; text ] -> (
      match float_of_string_opt t with
      | Some time -> Some { time; author; text }
      | None -> None)
  | _ -> None

(* 최근 n개 메시지 (오래된 것부터) *)
let load_recent n : Model.message list =
  locked (fun () ->
      if not (Sys.file_exists !path) then []
      else begin
        let ic = open_in_bin !path in
        let rec read acc =
          match input_line ic with
          | line -> read (match parse line with Some m -> m :: acc | None -> acc)
          | exception End_of_file -> close_in ic; acc
        in
        let newest_first = read [] in
        let rec take k = function
          | x :: rest when k > 0 -> x :: take (k - 1) rest
          | _ -> []
        in
        List.rev (take n newest_first)
      end)
