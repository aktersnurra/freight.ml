let render_body = function
  | Freight.Ast.Body_none -> [ "Body: <none>" ]
  | Body_inline body -> [ "Body: inline"; body ]
  | Body_file path -> [ "Body: file " ^ path ]

let render_headers headers =
  match headers with
  | [] -> [ "Headers: <none>" ]
  | headers ->
      "Headers:"
      :: List.map (fun (key, value) -> "  " ^ key ^ ": " ^ value) headers

let render_request request invocation =
  let name = Option.value request.Freight.Ast.name ~default:"<unnamed>" in
  [ "Freight Inspect";
    "";
    "Name: " ^ name;
    "Method: " ^ Freight.Ast.method_to_string request.method_;
    "URL: " ^ request.url;
    "" ]
  @ render_headers request.headers
  @ [ "" ]
  @ render_body request.body
  @ [ ""; "Curl argv:" ]
  @ List.map (fun arg -> "  " ^ arg) invocation.Freight.Executor.args

let render_parse_error error =
  [ "Freight Parse Error";
    "";
    "Line: " ^ string_of_int error.Freight.Ast.line;
    "Message: " ^ error.message;
    "Snippet: " ^ error.snippet ]

let render_message ~title ~body =
  title :: "" :: body

let render_env ~active_env ~pairs ~unresolved =
  let label = match active_env with Some n -> n | None -> "(none)" in
  let vars_section =
    match pairs with
    | [] -> [ "Variables: (none)" ]
    | _ ->
      "Variables:"
      :: List.map (fun (k, v) -> Printf.sprintf "  %s = %s" k v) pairs
  in
  let unresolved_section =
    match unresolved with
    | [] -> [ "Unresolved: (none)" ]
    | names ->
      "Unresolved:"
      :: List.map (fun name -> Printf.sprintf "  {{%s}}" name) names
  in
  [ "Freight Env"; ""; "Active: " ^ label; "" ]
  @ vars_section
  @ [ "" ]
  @ unresolved_section
