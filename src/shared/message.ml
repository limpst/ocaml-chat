(* =========================================================================
   Message — 채팅 메시지 (MVC: Model 의 공용 데이터 타입)
   -------------------------------------------------------------------------
   서버(저장·전송)와 클라이언트(화면 출력)가 함께 쓰는 핵심 데이터.
   필드 목록 변환 함수(to_fields / of_fields)는 통신 프로토콜과 저장 파일이
   같은 형식을 쓰도록 한 곳에 정의해 둔다.
   ========================================================================= *)

(* 채팅 메시지 한 건 *)
type t = {
  time : float;    (* 보낸 시각 — Unix epoch 기준 초 *)
  author : string; (* 보낸 사람의 닉네임 *)
  text : string;   (* 메시지 본문 *)
}

(* [make ~author ~text] — 현재 시각으로 새 메시지를 만든다 *)
let make ~(author : string) ~(text : string) : t =
  { time = Unix.time ();  (* 지금 시각 *)
    author;               (* author = author 의 축약 표기 *)
    text }                (* text = text 의 축약 표기 *)

(* [to_fields m] = ["1794937352"; "alice"; "hello"]
   메시지를 문자열 필드 3개로 바꾼다 (전송·저장용). *)
let to_fields (m : t) : string list =
  [ Printf.sprintf "%.0f" m.time;  (* 시각: 소수점 없는 정수 문자열 *)
    Text.sanitize m.author;        (* 닉네임: 탭·줄바꿈 제거 *)
    Text.sanitize m.text ]         (* 본문: 탭·줄바꿈 제거 *)

(* [of_fields fields] — to_fields 의 역변환. 형식이 틀리면 None *)
let of_fields (fields : string list) : t option =
  match fields with
  | [ time_text; author; text ] -> (                 (* 필드가 정확히 3개일 때만 *)
      match float_of_string_opt time_text with       (* 시각 문자열 → 숫자 *)
      | Some time -> Some { time; author; text }     (* 성공: 메시지 생성 *)
      | None -> None)                                (* 시각이 숫자가 아님 → 실패 *)
  | _ -> None                                        (* 필드 개수가 틀림 → 실패 *)
