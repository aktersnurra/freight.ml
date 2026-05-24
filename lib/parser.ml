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
  loop [] [] 0 0 lines
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

let parse_block block =
  let rec skip_leading_metadata name = function
    | [] -> make_error "missing request line"
    | line :: rest when trim line = "" -> skip_leading_metadata name rest
    | line :: rest -> (
        match parse_name line with
        | Some parsed_name -> skip_leading_metadata (Some parsed_name) rest
        | None when starts_with ~prefix:"#" (trim line) ->
            skip_leading_metadata name rest
        | None -> (
            match parse_request_line line with
            | Error message -> make_error ~snippet:line message
            | Ok (method_, url) ->
                let header_lines, body_lines = split_at_blank rest in
                let headers = List.filter_map parse_header header_lines in
                Ok
                  {
                    Ast.name;
                    method_;
                    url;
                    headers;
                    body = parse_body body_lines;
                  }))
  in
  skip_leading_metadata None block

let parse_source source =
  let blocks = split_lines source |> split_blocks in
  let rec loop requests = function
    | [] -> Ok { Ast.requests = List.rev (List.map snd requests); path = "" }
    | (start, block) :: rest -> (
        match parse_block block with
        | Ok request -> loop ((start, request) :: requests) rest
        | Error error -> Error error)
  in
  loop [] blocks

let parse_source_with_lines source =
  let blocks = split_lines source |> split_blocks in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | (start, block) :: rest -> (
        match parse_block block with
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

let request_at_cursor source cursor_line =
  match parse_source_with_lines source with
  | Error _ -> None
  | Ok [] -> None
  | Ok pairs ->
    (* Pick the last request whose block starts at or before the cursor *)
    let result = List.fold_left (fun acc (start, req) ->
      if start <= cursor_line then Some req else acc
    ) None pairs in
    (* Fall back to first request if cursor is before all blocks *)
    (match result with
     | Some _ -> result
     | None -> Some (snd (List.hd pairs)))
