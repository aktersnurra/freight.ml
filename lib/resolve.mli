type error =
  [ `Parse of Ast.parse_error
  | `No_request
  ]

val substitute_request : Env.t -> Ast.request -> Ast.request

val unresolved_request : Env.t -> Ast.request -> string list
(** [unresolved_request env request] returns the sorted, deduplicated list of
    [{{var}}] references in the request's url, header values, and body that are
    not present in [env]. Empty when every reference resolves. *)

val at_cursor :
  source:string ->
  cursor_line:int ->
  env:Env.t ->
  (Ast.request, error) result
