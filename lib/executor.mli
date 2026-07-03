type invocation = {
  args : string list;
  env : (string * string) list;
}

val to_curl : ?cookie_jar:string -> Ast.request -> invocation
(** [?cookie_jar] is a file path curl uses to persist and replay cookies
    ([-c]/[-b]), so a login response's Set-Cookie carries into later requests. *)
