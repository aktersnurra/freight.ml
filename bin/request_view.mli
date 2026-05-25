val render_request : Freight.Ast.request -> Freight.Executor.invocation -> string list
val render_parse_error : Freight.Ast.parse_error -> string list
val render_message : title:string -> body:string list -> string list
val render_env : active_env:string option -> pairs:(string * string) list -> unresolved:string list -> string list
val render_history : State.history_entry list -> string list
