val parse_string : string -> (Ast.http_file, Ast.parse_error) result
val parse_file : string -> (Ast.http_file, Ast.parse_error) result
val parse_source_with_lines : string -> ((int * Ast.request) list, Ast.parse_error) result
val request_at_cursor : string -> int -> Ast.request option
(** [request_at_cursor source cursor_line] returns the request whose content
    span contains [cursor_line] (0-based). A request's span runs from its
    request line through its last non-blank body line. Returns [None] when the
    cursor sits in a leading/trailing comment block or a blank gap between
    requests. *)
