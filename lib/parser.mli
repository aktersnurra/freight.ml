val parse_string : string -> (Ast.http_file, Ast.parse_error) result
val parse_file : string -> (Ast.http_file, Ast.parse_error) result
val request_at_cursor : Ast.request list -> int -> Ast.request option
