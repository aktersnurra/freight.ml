val render_request : Freight.Ast.request -> Freight.Executor.curl_invocation -> string list
val render_parse_error : Freight.Ast.parse_error -> string list
val render_message : title:string -> body:string list -> string list
