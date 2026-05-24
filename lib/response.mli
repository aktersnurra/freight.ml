type content_type =
  | Json
  | Xml
  | Html
  | Plain
  | Other of string

val parse_header : string -> (string * string) option
val parse_curl_output : string -> Ast.request -> (Ast.response, string) result
val detect_content_type : Ast.response -> content_type
val pretty_print_body : content_type -> string -> string
val render : Ast.response -> string list
(** Status line, headers, blank line, pretty-printed body. *)

val render_body : Ast.response -> string list
(** Pretty-printed body only. *)

val render_headers : Ast.response -> string list
(** Status line and all response headers, no body. *)

val render_all : Ast.response -> string list
(** Status line, headers, blank line, pretty-printed body. Identical to [render]. *)
