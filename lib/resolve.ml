type error =
  [ `Parse of Ast.parse_error
  | `No_request
  ]

let substitute_request env (request : Ast.request) =
  let sub = Env.substitute env in
  let body =
    match request.body with
    | Ast.Body_inline s -> Ast.Body_inline (sub s)
    | Ast.Body_file path -> Ast.Body_file (sub path)
    | Ast.Body_none as other -> other
  in
  { request with
    url = sub request.url
  ; headers = List.map (fun (k, v) -> (k, sub v)) request.headers
  ; body
  }

let request_strings (request : Ast.request) =
  let body =
    match request.body with
    | Ast.Body_inline s -> [ s ]
    | Ast.Body_file path -> [ path ]
    | Ast.Body_none -> []
  in
  (request.url :: List.map snd request.headers) @ body

let unresolved_request env request =
  request_strings request
  |> List.concat_map (Env.unresolved env)
  |> List.sort_uniq String.compare

let at_cursor ~source ~cursor_line ~env =
  match Parser.request_at_cursor source cursor_line with
  | None ->
    (match Parser.parse_string source with
     | Error err -> Error (`Parse err)
     | Ok _ -> Error `No_request)
  | Some request ->
    Ok (Ast.apply_host_header (substitute_request env request))
