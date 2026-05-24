type curl_invocation = {
  args : string list;
  env : (string * string) list;
}

val to_curl : Ast.request -> curl_invocation
