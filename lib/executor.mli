type invocation = {
  args : string list;
  env : (string * string) list;
}

val to_curl : Ast.request -> invocation
