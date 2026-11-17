(* =========================================================================
   Repository — 3-Tier: Data Tier (데이터 계층)
   -------------------------------------------------------------------------
   채팅 메시지를 파일(chat_history.log)에 저장하고 다시 읽는다.
   업무 로직 계층은 save / load_recent 두 함수만 알면 되므로,
   나중에 저장소를 DB로 바꿔도 이 파일만 고치면 된다.

   파일 형식: 한 줄에 메시지 하나  →  시각 <TAB> 보낸사람 <TAB> 본문
   ========================================================================= *)

(* 저장 파일 경로 (서버를 실행한 폴더 기준) *)
let file_path = "chat_history.log"

(* 여러 클라이언트 스레드가 동시에 파일을 쓰지 않도록 막는 잠금 *)
let file_lock = Mutex.create ()

(* [save message] — 메시지 한 건을 파일 끝에 덧붙인다 *)
let save (message : Message.t) : unit =
  Sync.with_lock file_lock (fun () ->                       (* 파일 잠금 *)
      let file =
        open_out_gen                                        (* 파일 열기 (옵션 지정) *)
          [ Open_wronly; Open_append; Open_creat; Open_binary ]  (* 쓰기·덧붙이기·없으면 생성 *)
          0o644                                             (* 새로 만들 때의 권한 *)
          file_path
      in
      Fun.protect ~finally:(fun () -> close_out file) (fun () ->  (* 작업 후 반드시 닫기 *)
          output_string file (Text.join_fields (Message.to_fields message));  (* 레코드 한 줄 *)
          output_char file '\n'))                           (* 줄바꿈 *)

(* [read_lines path] — 파일의 모든 줄을 순서대로 읽어 리스트로 돌려준다 *)
let read_lines (path : string) : string list =
  let file = open_in_bin path in                            (* 읽기용으로 열기 *)
  Fun.protect ~finally:(fun () -> close_in file) (fun () -> (* 작업 후 반드시 닫기 *)
      let rec read_from_here lines_so_far =                 (* 한 줄씩 읽는 반복 *)
        match input_line file with
        | line -> read_from_here (line :: lines_so_far)     (* 읽은 줄을 앞에 쌓고 계속 *)
        | exception End_of_file -> List.rev lines_so_far    (* 끝: 쌓인 순서를 뒤집어 반환 *)
      in
      read_from_here [])

(* [keep_last n items] — 리스트의 마지막 n 개만 남긴다 *)
let keep_last (n : int) (items : 'a list) : 'a list =
  let skip = List.length items - n in                       (* 앞에서 버릴 개수 *)
  List.filteri (fun index _ -> index >= skip) items         (* 그 뒤의 것만 남김 *)

(* [load_recent count] — 가장 최근 메시지 count 개 (오래된 것 → 최신 순) *)
let load_recent (count : int) : Message.t list =
  Sync.with_lock file_lock (fun () ->                       (* 쓰는 중에 읽지 않도록 잠금 *)
      if not (Sys.file_exists file_path) then []            (* 파일이 아직 없으면 빈 목록 *)
      else
        read_lines file_path                                (* 1. 모든 줄 읽기 *)
        |> List.filter_map (fun line ->                     (* 2. 각 줄 → 메시지 (깨진 줄은 버림) *)
               Message.of_fields (Text.split_fields line))
        |> keep_last count)                                 (* 3. 마지막 count 개만 *)
