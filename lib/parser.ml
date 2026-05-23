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
  let rec loop blocks current = function
    | [] -> List.rev (List.rev current :: blocks)
    | line :: rest when starts_with ~prefix:"###" (trim line) ->
        loop (List.rev current :: blocks) [] rest
    | line :: rest -> loop blocks (line :: current) rest
  in
  loop [] [] lines
  |> List.filter (fun block -> List.exists (fun line -> trim line <> "") block)

let parse_name line =
  let trimmed = trim line in
  if starts_with ~prefix:"# @name" trimmed then
    let name = String.sub trimmed 7 (String.length trimmed - 7) |> trim in
    if name = "" then None else Some name
  else None

let parse_request_line line =
  match String.split_on_char ' ' (trim line) |> List.filter (( <> ) "") with
  | method_ :: url_parts -> Ok (Ast.method_of_string method_, String.concat " " url_parts)
  | [] -> Error "missing request line"

let split_at_blank lines =
  let rec loop before = function
    | [] -> (List.rev before, [])
    | line :: rest when trim line = "" -> (List.rev before, rest)
    | line :: rest -> loop (line :: before) rest
  in
  loop [] lines

let parse_header line =
  match String.index_opt line ':' with
  | None -> None
  | Some index ->
      let key = String.sub line 0 index |> trim in
      let value =
        String.sub line (index + 1) (String.length line - index - 1) |> trim
      in
      if key = "" then None else Some (key, value)

let parse_body lines =
  let body_lines =
    lines
    |> List.drop_while (fun line -> trim line = "")
    |> List.rev
    |> List.drop_while (fun line -> trim line = "")
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
  let parser = Angstrom.(take_while (fun _ -> true) <* end_of_input) in
  match Angstrom.parse_string ~consume:All parser source with
  | Error message -> make_error message
  | Ok parsed_source ->
      let blocks = split_lines parsed_source |> split_blocks in
      let rec loop requests = function
        | [] -> Ok { Ast.requests = List.rev requests; path = "" }
        | block :: rest -> (
            match parse_block block with
            | Ok request -> loop (request :: requests) rest
            | Error error -> Error error)
      in
      loop [] blocks

let parse_string = parse_source

let parse_file path =
  try
    let channel = open_in path in
    let length = in_channel_length channel in
    let source = really_input_string channel length in
    close_in channel;
    match parse_source source with
    | Ok file -> Ok { file with Ast.path }
    | Error error -> Error error
  with Sys_error message -> make_error message

let request_at_cursor requests cursor_line =
  ignore cursor_line;
  match requests with [] -> None | request :: _ -> Some request
