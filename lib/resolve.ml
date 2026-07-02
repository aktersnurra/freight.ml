type error =
  [ `Parse of Ast.parse_error
  | `No_request
  ]

let substitute_request_r resolver (request : Ast.request) =
  let sub = Resolver.resolve resolver in
  let sub_part (part : Ast.multipart_part) =
    let content =
      match part.content with
      | Ast.Part_text value -> Ast.Part_text (sub value)
      | Ast.Part_file path -> Ast.Part_file (sub path)
    in
    { part with
      Ast.filename = Option.map sub part.filename
    ; content_type = Option.map sub part.content_type
    ; content
    }
  in
  let body =
    match request.body with
    | Ast.Body_inline s -> Ast.Body_inline (sub s)
    | Ast.Body_file path -> Ast.Body_file (sub path)
    | Ast.Body_multipart parts -> Ast.Body_multipart (List.map sub_part parts)
    | Ast.Body_none as other -> other
  in
  let save_to =
    Option.map
      (fun (save : Ast.save) ->
        { save with Ast.save_path = Option.map sub save.save_path })
      request.save_to
  in
  { request with
    url = sub request.url
  ; headers = List.map (fun (k, v) -> (k, sub v)) request.headers
  ; body
  ; save_to
  }

let substitute_request env request =
  substitute_request_r (Resolver.make [ Env.source env ]) request

let part_strings (part : Ast.multipart_part) =
  let content =
    match part.content with
    | Ast.Part_text value -> value
    | Ast.Part_file path -> path
  in
  content :: Option.to_list part.filename @ Option.to_list part.content_type

let request_strings (request : Ast.request) =
  let body =
    match request.body with
    | Ast.Body_inline s -> [ s ]
    | Ast.Body_file path -> [ path ]
    | Ast.Body_multipart parts -> List.concat_map part_strings parts
    | Ast.Body_none -> []
  in
  (request.url :: List.map snd request.headers) @ body

let unresolved_request_r resolver request =
  request_strings request
  |> List.concat_map (Resolver.unresolved resolver)
  |> List.sort_uniq String.compare

let unresolved_request env request =
  unresolved_request_r (Resolver.make [ Env.source env ]) request

let at_cursor ~source ~cursor_line ~env =
  match Parser.request_at_cursor source cursor_line with
  | None ->
    (match Parser.parse_string source with
     | Error err -> Error (`Parse err)
     | Ok _ -> Error `No_request)
  | Some request ->
    Ok (Ast.apply_host_header (substitute_request env request))
