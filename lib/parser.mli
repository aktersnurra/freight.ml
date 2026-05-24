val parse_string : string -> (Ast.http_file, Ast.parse_error) result
val parse_file : string -> (Ast.http_file, Ast.parse_error) result
val request_at_cursor : string -> int -> Ast.request option
(** [request_at_cursor source cursor_line] returns the request that contains
    [cursor_line] (0-based). Returns the last request whose block starts at or
    before the cursor. *)
