let render_part (part : Freight.Ast.multipart_part) =
  let value =
    match part.content with
    | Freight.Ast.Part_text text -> text
    | Freight.Ast.Part_file path -> "file " ^ path
  in
  Printf.sprintf "  %s: %s" part.part_name value

let render_body = function
  | Freight.Ast.Body_none -> [ "Body: <none>" ]
  | Body_inline body -> [ "Body:"; body ]
  | Body_file path -> [ "Body: file " ^ path ]
  | Body_multipart parts -> "Body: multipart" :: List.map render_part parts

let render_headers headers =
  match headers with
  | [] -> [ "Headers: <none>" ]
  | hs ->
    "Headers:"
    :: List.map (fun (k, v) -> "  " ^ k ^ ": " ^ v) hs

let render_request request invocation =
  let name = Option.value request.Freight.Ast.name ~default:"<unnamed>" in
  [ "Freight Inspect"
  ; ""
  ; "Name:    " ^ name
  ; "Method:  " ^ Freight.Ast.method_to_string request.method_
  ; "URL:     " ^ request.url
  ; ""
  ]
  @ render_headers request.headers
  @ [ "" ]
  @ render_body request.body
  @ [ ""; "Curl argv:" ]
  @ List.map (fun a -> "  " ^ a) invocation.Freight.Executor.args

let render_parse_error error =
  [ "Parse Error"
  ; ""
  ; "Line:    " ^ string_of_int error.Freight.Ast.line
  ; "Message: " ^ error.message
  ; "Snippet: " ^ error.snippet
  ]

let render_message ~title ~body =
  title :: "" :: body

let render_env ~active_env ~pairs ~unresolved =
  let label = Option.value active_env ~default:"(none)" in
  let vars_section =
    match pairs with
    | [] -> [ "Variables: (none)" ]
    | ps ->
      "Variables:"
      :: List.map (fun (k, v) -> "  " ^ k ^ " = " ^ v) ps
  in
  let unresolved_section =
    match unresolved with
    | [] -> [ "Unresolved: (none)" ]
    | ns ->
      "Unresolved:"
      :: List.map (fun n -> "  {{" ^ n ^ "}}") ns
  in
  [ "Freight Env"; ""; "Active: " ^ label; "" ]
  @ vars_section
  @ [ "" ]
  @ unresolved_section

let render_history (entries : State.history_entry list) =
  if entries = [] then
    [ "No requests in history." ]
  else
    List.mapi (fun i ({ State.request; response; _ } : State.history_entry) ->
      let n = Printf.sprintf "%2d" (i + 1) in
      let meth = Printf.sprintf "%-6s" (Freight.Ast.method_to_string request.Freight.Ast.method_) in
      let status = Printf.sprintf "%d %s" response.Freight.Ast.status response.status_text in
      let ms = Printf.sprintf "(%d ms)" response.duration_ms in
      Printf.sprintf "  %s  %s %s  %s  %s" n meth request.url status ms
    ) entries
