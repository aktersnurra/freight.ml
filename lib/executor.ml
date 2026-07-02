type invocation = {
  args : string list;
  env : (string * string) list;
}

let header_arg (key, value) = [ "-H"; key ^ ": " ^ value ]

let part_arg (part : Ast.multipart_part) =
  match part.content with
  | Ast.Part_text value -> [ "-F"; part.part_name ^ "=" ^ value ]
  | Ast.Part_file path ->
      let spec = part.part_name ^ "=@" ^ path in
      let spec =
        match part.content_type with
        | Some content_type -> spec ^ ";type=" ^ content_type
        | None -> spec
      in
      let spec =
        match part.filename with
        | Some filename -> spec ^ ";filename=" ^ filename
        | None -> spec
      in
      [ "-F"; spec ]

let body_args method_ = function
  | Ast.Body_none -> []
  | Body_inline body -> [ "--data-binary"; body ]
  | Body_multipart parts -> List.concat_map part_arg parts
  | Body_file path -> (
      match method_ with
      | Ast.Put -> [ "-T"; path ]
      | _ -> [ "--data-binary"; "@" ^ path ])

(* When saving to a known path, stream the body straight to the file with [-o]
   and dump the headers to stdout with [-D -] so the response buffer still shows
   status/headers without routing binary bytes through the text renderer. When
   the path is omitted (derive from Content-Disposition) the file name is not
   known up front, so fall back to the header+body capture that [-i] provides. *)
let capture_args = function
  | Some { Ast.save_path = Some path; _ } -> [ "-D"; "-"; "-o"; path ]
  | Some { Ast.save_path = None; _ } | None -> [ "-i" ]

let to_curl request =
  let request = Ast.apply_host_header request in
  let method_ = Ast.method_to_string request.Ast.method_ in
  let headers = List.concat_map header_arg request.headers in
  let args =
    capture_args request.save_to @ [ "-s"; "-X"; method_ ] @ headers
    @ body_args request.method_ request.body
    @ [ request.url; "-w"; "\n%{http_code}\n%{time_total}" ]
  in
  { args; env = [] }
