type error =
  [ `Parse of Ast.parse_error
  | `No_request
  ]

let substitute_request env request =
  let sub = Env.substitute env in
  let body =
    match request.Ast.body with
    | Ast.Body_inline s -> Ast.Body_inline (sub s)
    | other -> other
  in
  { request with
    Ast.url = sub request.Ast.url
  ; headers = List.map (fun (k, v) -> (k, sub v)) request.Ast.headers
  ; body
  }

let at_cursor ~source ~cursor_line ~env =
  match Parser.request_at_cursor source cursor_line with
  | None ->
    (match Parser.parse_string source with
     | Error err -> Error (`Parse err)
     | Ok _ -> Error `No_request)
  | Some request ->
    Ok (Ast.apply_host_header (substitute_request env request))
