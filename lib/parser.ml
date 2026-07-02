let trim = String.trim

let starts_with ~prefix string =
  let prefix_length = String.length prefix in
  String.length string >= prefix_length
  && String.sub string 0 prefix_length = prefix

let strip_cr line =
  let length = String.length line in
  if length > 0 && line.[length - 1] = '\r' then String.sub line 0 (length - 1)
  else line

let split_lines source = source |> String.split_on_char '\n' |> List.map strip_cr

let make_error ?(line = 1) ?(snippet = "") message =
  Error { Ast.message; line; snippet }

let split_blocks lines =
  let rec loop blocks current current_start line_num = function
    | [] -> List.rev ((current_start, List.rev current) :: blocks)
    | line :: rest when starts_with ~prefix:"###" (trim line) ->
        loop ((current_start, List.rev current) :: blocks) [] (line_num + 1) (line_num + 1) rest
    | line :: rest -> loop blocks (line :: current) current_start (line_num + 1) rest
  in
  loop [] [] 1 1 lines
  |> List.filter (fun (_, block) -> List.exists (fun line -> trim line <> "") block)

let parse_name line =
  let trimmed = trim line in
  if starts_with ~prefix:"# @name" trimmed then
    let name = String.sub trimmed 7 (String.length trimmed - 7) |> trim in
    if name = "" then None else Some name
  else None

let parse_request_line line =
  let open Angstrom in
  let space = satisfy (function ' ' | '\t' -> true | _ -> false) in
  let token = take_while1 (function ' ' | '\t' -> false | _ -> true) in
  let parser =
    token >>= fun method_ ->
    skip_many1 space *> take_while (fun _ -> true) >>| fun url ->
    (Ast.method_of_string method_, trim url)
  in
  match parse_string ~consume:All parser (trim line) with
  | Ok (_, "") -> Error "missing request URL"
  | Ok request_line -> Ok request_line
  | Error _ when trim line = "" -> Error "missing request line"
  | Error _ -> Error "missing request URL"

let split_at_blank lines =
  let rec loop before = function
    | [] -> (List.rev before, [])
    | line :: rest when trim line = "" -> (List.rev before, rest)
    | line :: rest -> loop (line :: before) rest
  in
  loop [] lines

let parse_header line =
  let open Angstrom in
  let parser =
    take_till (Char.equal ':') >>= fun key ->
    char ':' *> take_while (fun _ -> true) >>| fun value -> (trim key, trim value)
  in
  match parse_string ~consume:All parser line with
  | Ok ("", _) | Error _ -> None
  | Ok header -> Some header

let rec drop_while p = function
  | x :: rest when p x -> drop_while p rest
  | xs -> xs

let parse_body lines =
  let body_lines =
    lines
    |> drop_while (fun line -> trim line = "")
    |> List.rev
    |> drop_while (fun line -> trim line = "")
    |> List.rev
  in
  match body_lines with
  | [] -> Ast.Body_none
  | [ line ] ->
      let trimmed = trim line in
      if starts_with ~prefix:"<" trimmed then
        Ast.Body_file (String.sub trimmed 1 (String.length trimmed - 1) |> trim)
      else Ast.Body_inline (String.concat "\n" body_lines)
  | _ -> Ast.Body_inline (String.concat "\n" body_lines)

let lower = String.lowercase_ascii

(* [multipart_boundary headers] returns the boundary declared on a
   [Content-Type: multipart/form-data; boundary=...] header, if any. *)
let multipart_boundary headers =
  List.find_map
    (fun (name, value) ->
      if lower name = "content-type" && starts_with ~prefix:"multipart/form-data" (lower (trim value)) then
        value
        |> String.split_on_char ';'
        |> List.find_map (fun param ->
               match String.index_opt param '=' with
               | Some index when lower (trim (String.sub param 0 index)) = "boundary" ->
                   Some (String.sub param (index + 1) (String.length param - index - 1) |> trim)
               | _ -> None)
      else None)
    headers

(* Extract a quoted or bare parameter [key] from a Content-Disposition value,
   e.g. [name="file"] or [name=file]. *)
let disposition_param value key =
  value
  |> String.split_on_char ';'
  |> List.find_map (fun param ->
         match String.index_opt param '=' with
         | Some index when lower (trim (String.sub param 0 index)) = key ->
             let raw = String.sub param (index + 1) (String.length param - index - 1) |> trim in
             let unquoted =
               let length = String.length raw in
               if length >= 2 && raw.[0] = '"' && raw.[length - 1] = '"' then
                 String.sub raw 1 (length - 2)
               else raw
             in
             Some unquoted
         | _ -> None)

(* Split multipart body lines on [--boundary] delimiters, dropping the final
   [--boundary--] terminator. Each returned chunk is one part's raw lines. *)
let split_multipart ~boundary lines =
  let delimiter = "--" ^ boundary in
  let terminator = delimiter ^ "--" in
  let rec loop parts current started = function
    | [] -> if started then List.rev (List.rev current :: parts) else List.rev parts
    | line :: _ when trim line = terminator ->
        if started then List.rev (List.rev current :: parts) else List.rev parts
    | line :: rest when trim line = delimiter ->
        let parts = if started then List.rev current :: parts else parts in
        loop parts [] true rest
    | line :: rest -> loop parts (line :: current) started rest
  in
  loop [] [] false lines

let parse_part chunk =
  let header_lines, value_lines = split_at_blank chunk in
  let part_headers = List.filter_map parse_header header_lines in
  let disposition =
    List.find_map
      (fun (name, value) -> if lower name = "content-disposition" then Some value else None)
      part_headers
  in
  match disposition with
  | None -> None
  | Some disposition ->
      let part_name =
        match disposition_param disposition "name" with Some name -> name | None -> ""
      in
      let filename = disposition_param disposition "filename" in
      let content_type =
        List.find_map
          (fun (name, value) -> if lower name = "content-type" then Some value else None)
          part_headers
      in
      let value_lines =
        value_lines
        |> drop_while (fun line -> trim line = "")
        |> List.rev
        |> drop_while (fun line -> trim line = "")
        |> List.rev
      in
      let content =
        match value_lines with
        | [ line ] when starts_with ~prefix:"<" (trim line) ->
            let path = String.sub (trim line) 1 (String.length (trim line) - 1) |> trim in
            Ast.Part_file path
        | _ -> Ast.Part_text (String.concat "\n" value_lines)
      in
      Some { Ast.part_name; filename; content_type; content }

let parse_multipart ~boundary body_lines =
  split_multipart ~boundary body_lines |> List.filter_map parse_part

let parse_block ~start_line block =
  let rec skip_leading_metadata line_number name = function
    | [] -> make_error ~line:line_number "missing request line"
    | line :: rest when trim line = "" ->
        skip_leading_metadata (line_number + 1) name rest
    | line :: rest -> (
        match parse_name line with
        | Some parsed_name ->
            skip_leading_metadata (line_number + 1) (Some parsed_name) rest
        | None when starts_with ~prefix:"#" (trim line) ->
            skip_leading_metadata (line_number + 1) name rest
        | None -> (
            match parse_request_line line with
            | Error message -> make_error ~line:line_number ~snippet:line message
            | Ok (method_, url) ->
                let header_lines, body_lines = split_at_blank rest in
                let headers = List.filter_map parse_header header_lines in
                let headers, body =
                  match multipart_boundary headers with
                  | Some boundary ->
                      (* Drop the multipart Content-Type header: curl regenerates
                         the boundary and sets the header itself. *)
                      let headers =
                        List.filter
                          (fun (name, _) -> lower name <> "content-type")
                          headers
                      in
                      (headers, Ast.Body_multipart (parse_multipart ~boundary body_lines))
                  | None -> (headers, parse_body body_lines)
                in
                Ok { Ast.name; method_; url; headers; body }))
  in
  skip_leading_metadata start_line None block

let parse_source source =
  let blocks = split_lines source |> split_blocks in
  let rec loop requests = function
    | [] -> Ok { Ast.requests = List.rev (List.map snd requests); path = "" }
    | (start, block) :: rest -> (
        match parse_block ~start_line:start block with
        | Ok request -> loop ((start, request) :: requests) rest
        | Error error -> Error error)
  in
  loop [] blocks

let parse_source_with_lines source =
  let blocks = split_lines source |> split_blocks in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | (start, block) :: rest -> (
        match parse_block ~start_line:start block with
        | Ok request -> loop ((start, request) :: acc) rest
        | Error error -> Error error)
  in
  loop [] blocks

let parse_string = parse_source

let parse_file path =
  try
    let channel = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
        let length = in_channel_length channel in
        let source = really_input_string channel length in
        match parse_source source with
        | Ok file -> Ok { file with Ast.path }
        | Error error -> Error error)
  with Sys_error message -> make_error message

(* The content span of a block runs from its request line (the first non-blank,
   non-comment line) through its last non-blank line. [start] is the 1-based line
   number of the block's first line; the returned span is 0-based inclusive to
   match the cursor coordinate system. Returns [None] when the block holds no
   request line (comment/blank only). *)
let block_content_span ~start block =
  let indexed = List.mapi (fun offset line -> (start - 1 + offset, line)) block in
  let request_line =
    List.find_map
      (fun (index, line) ->
        let trimmed = trim line in
        if trimmed = "" || starts_with ~prefix:"#" trimmed then None
        else Some index)
      indexed
  in
  match request_line with
  | None -> None
  | Some first ->
    let last =
      List.fold_left
        (fun acc (index, line) -> if trim line <> "" then index else acc)
        first indexed
    in
    Some (first, last)

let request_at_cursor source cursor_line =
  let blocks = split_lines source |> split_blocks in
  let rec loop = function
    | [] -> None
    | (start, block) :: rest -> (
        match block_content_span ~start block with
        | Some (first, last) when first <= cursor_line && cursor_line <= last -> (
            match parse_block ~start_line:start block with
            | Ok request -> Some request
            | Error _ -> None)
        | _ -> loop rest)
  in
  loop blocks
