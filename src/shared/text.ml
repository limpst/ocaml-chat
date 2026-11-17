(* =========================================================================
   Text — 문자열 도우미 (서버/클라이언트 공용)
   -------------------------------------------------------------------------
   통신 프로토콜과 저장 파일은 모두 "한 줄 = 레코드 하나, 필드는 탭으로 구분"
   형식을 쓴다. 그 형식을 만들고 읽는 데 필요한 작은 함수들을 모아 둔다.
   ========================================================================= *)

(* 필드 구분자: 탭 문자 *)
let field_separator = '\t'

(* [sanitize s]
   사용자가 입력한 문자열 안에 탭이나 줄바꿈이 있으면 형식이 깨지므로
   그런 문자를 공백으로 바꾼다. *)
let sanitize (s : string) : string =
  String.map                                         (* 문자열의 각 문자를 변환 *)
    (fun c ->
      match c with
      | '\t' | '\n' | '\r' -> ' '                    (* 구분자·줄바꿈 → 공백 *)
      | other -> other)                              (* 나머지 문자는 그대로 *)
    s

(* [join_fields ["a"; "b"]] = "a\tb"  — 필드 목록을 한 줄로 합친다 *)
let join_fields (fields : string list) : string =
  String.concat (String.make 1 field_separator) fields

(* [split_fields "a\tb"] = ["a"; "b"]  — 한 줄을 필드 목록으로 나눈다 *)
let split_fields (line : string) : string list =
  String.split_on_char field_separator line

(* [strip_cr s]
   Windows 줄바꿈(\r\n)으로 들어온 줄은 끝에 \r 이 남으므로 제거한다. *)
let strip_cr (s : string) : string =
  if String.ends_with ~suffix:"\r" s                 (* 마지막 글자가 \r 이면 *)
  then String.sub s 0 (String.length s - 1)          (* 그 한 글자를 잘라낸 문자열 *)
  else s                                             (* 아니면 원본 그대로 *)

(* UTF-8 BOM: 일부 프로그램(파이프, 메모장 등)이 텍스트 맨 앞에 붙이는 3바이트 *)
let utf8_bom = "\xEF\xBB\xBF"

(* [strip_bom s] — 맨 앞의 BOM 을 제거한다. 남아 있으면 "/nick" 같은 명령이 인식되지 않는다. *)
let strip_bom (s : string) : string =
  if String.starts_with ~prefix:utf8_bom s           (* BOM 으로 시작하면 *)
  then
    let bom_length = String.length utf8_bom in       (* BOM 길이 = 3 *)
    String.sub s bom_length (String.length s - bom_length)  (* BOM 뒤부터 끝까지 *)
  else s                                             (* BOM 이 없으면 그대로 *)
