let method_line request =
  Ast.method_to_string request.Ast.method_ ^ " " ^ request.Ast.url

let name_lines request =
  match request.Ast.name with
  | Some name when name <> "" -> [ "# @name " ^ name ]
  | _ -> []

let render_assertion = function
  | Ast.Expect_status n -> Printf.sprintf "# @expect status %d" n
  | Ast.Expect_header { header_name; header_op; header_value } ->
    let op = match header_op with Op_equals -> "equals" | Op_contains -> "contains" in
    Printf.sprintf "# @expect header %s %s %s" header_name op header_value
  | Ast.Expect_body { body_path; body_op; body_value } -> (
    match body_op, body_value with
    | Op_exists, _ -> Printf.sprintf "# @expect body %s exists" body_path
    | Op_eq, Some v -> Printf.sprintf "# @expect body %s == %s" body_path v
    | Op_neq, Some v -> Printf.sprintf "# @expect body %s != %s" body_path v
    | Op_body_contains, Some v -> Printf.sprintf "# @expect body %s contains %s" body_path v
    | (Op_eq | Op_neq | Op_body_contains), None -> Printf.sprintf "# @expect body %s" body_path)

let assertion_lines request = List.map render_assertion request.Ast.assertions

let header_lines (request : Ast.request) =
  List.map (fun (k, v) -> k ^ ": " ^ v) request.Ast.headers

let multipart_boundary = "boundary"

let part_lines (part : Ast.multipart_part) =
  let disposition =
    let name = Printf.sprintf "name=\"%s\"" part.part_name in
    match part.filename with
    | Some filename -> Printf.sprintf "Content-Disposition: form-data; %s; filename=\"%s\"" name filename
    | None -> Printf.sprintf "Content-Disposition: form-data; %s" name
  in
  let type_line =
    match part.content_type with Some ct -> [ "Content-Type: " ^ ct ] | None -> []
  in
  let value =
    match part.content with
    | Ast.Part_text text -> text
    | Ast.Part_file path -> "< " ^ path
  in
  [ "--" ^ multipart_boundary; disposition ] @ type_line @ [ ""; value ]

let body_lines (request : Ast.request) =
  match request.Ast.body with
  | Ast.Body_none -> []
  | Ast.Body_inline text -> [ ""; text ]
  | Ast.Body_file path -> [ ""; "< " ^ path ]
  | Ast.Body_multipart parts ->
    [ "" ] @ List.concat_map part_lines parts @ [ "--" ^ multipart_boundary ^ "--" ]

(* When a body is multipart, the request must carry the Content-Type header with
   the boundary (the parser strips it, so we re-emit it here). *)
let multipart_content_type (request : Ast.request) =
  match request.Ast.body with
  | Ast.Body_multipart _ ->
    [ Printf.sprintf "Content-Type: multipart/form-data; boundary=%s" multipart_boundary ]
  | _ -> []

let save_lines request =
  match request.Ast.save_to with
  | None -> []
  | Some { save_path; overwrite } ->
    let marker = if overwrite then ">>!" else ">>" in
    let line = match save_path with Some p -> marker ^ " " ^ p | None -> marker in
    [ ""; line ]

let request (r : Ast.request) =
  let lines =
    name_lines r
    @ assertion_lines r
    @ [ method_line r ]
    @ header_lines r
    @ multipart_content_type r
    @ body_lines r
    @ save_lines r
  in
  String.concat "\n" lines ^ "\n"
