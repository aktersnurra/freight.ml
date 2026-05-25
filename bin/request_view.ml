let box_width = 60

let pad_right s len =
  let n = String.length s in
  if n >= len then String.sub s 0 len
  else s ^ String.make (len - n) ' '

let box_section title rows =
  let inner = box_width - 2 in
  let dash_str = "\xe2\x94\x80" in
  let dash_count = max 0 (inner - String.length title - 3) in
  let dashes = String.concat "" (List.init dash_count (fun _ -> dash_str)) in
  let top =
    "\xe2\x95\xad\xe2\x94\x80 " ^ title ^ " " ^ dashes ^ "\xe2\x95\xae"
  in
  let bottom = "\xe2\x95\xb0" ^ String.concat "" (List.init inner (fun _ -> dash_str)) ^ "\xe2\x95\xaf" in
  let body =
    List.map (fun row ->
      let content = pad_right row (inner - 2) in
      "\xe2\x94\x82  " ^ content ^ "\xe2\x94\x82"
    ) rows
  in
  top :: body @ [ bottom ]

let kv_row key value =
  let k = pad_right key 12 in
  k ^ "  " ^ value

let render_body = function
  | Freight.Ast.Body_none -> box_section "Body" [ "(none)" ]
  | Body_inline body -> box_section "Body" (String.split_on_char '\n' body)
  | Body_file path -> box_section "Body" [ "file  " ^ path ]

let render_headers headers =
  match headers with
  | [] -> box_section "Headers" [ "(none)" ]
  | hs ->
    let rows = List.map (fun (k, v) -> kv_row k v) hs in
    box_section "Headers" rows

let render_request request invocation =
  let name = Option.value request.Freight.Ast.name ~default:"<unnamed>" in
  let meta_rows =
    [ kv_row "Name"   name
    ; kv_row "Method" (Freight.Ast.method_to_string request.method_)
    ; kv_row "URL"    request.url
    ]
  in
  let curl_rows = List.map (fun a -> "  " ^ a) invocation.Freight.Executor.args in
  box_section "Request" meta_rows
  @ [ "" ]
  @ render_headers request.headers
  @ [ "" ]
  @ render_body request.body
  @ [ "" ]
  @ box_section "Curl argv" curl_rows

let render_parse_error error =
  let rows =
    [ kv_row "Line"    (string_of_int error.Freight.Ast.line)
    ; kv_row "Message" error.message
    ; kv_row "Snippet" error.snippet
    ]
  in
  box_section "Parse Error" rows

let render_message ~title ~body =
  box_section title body

let render_env ~active_env ~pairs ~unresolved =
  let label = Option.value active_env ~default:"(none)" in
  let vars_rows =
    match pairs with
    | [] -> [ "(none)" ]
    | ps -> List.map (fun (k, v) -> kv_row k v) ps
  in
  let unresolved_rows =
    match unresolved with
    | [] -> [ "(none)" ]
    | ns -> List.map (fun n -> "{{" ^ n ^ "}}") ns
  in
  box_section ("Env: " ^ label) vars_rows
  @ [ "" ]
  @ box_section "Unresolved" unresolved_rows
