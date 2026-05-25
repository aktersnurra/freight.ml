type error =
  [ `Parse of Ast.parse_error
  | `No_request
  ]

val substitute_request : Env.t -> Ast.request -> Ast.request

val at_cursor :
  source:string ->
  cursor_line:int ->
  env:Env.t ->
  (Ast.request, error) result
