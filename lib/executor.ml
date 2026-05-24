type curl_invocation = {
  args : string list;
  env : (string * string) list;
}

let header_arg (key, value) = [ "-H"; key ^ ": " ^ value ]

let body_args method_ = function
  | Ast.Body_none -> []
  | Body_inline body -> [ "--data-binary"; body ]
  | Body_file path -> (
      match method_ with
      | Ast.Put -> [ "-T"; path ]
      | _ -> [ "--data-binary"; "@" ^ path ])

let to_curl request =
  let method_ = Ast.method_to_string request.Ast.method_ in
  let headers = List.concat_map header_arg request.headers in
  let args =
    [ "-i"; "-s"; "-X"; method_ ] @ headers
    @ body_args request.method_ request.body
    @ [ request.url; "-w"; "\n%{http_code}\n%{time_total}" ]
  in
  { args; env = [] }
