type content_type =
  | Json
  | Xml
  | Html
  | Plain
  | Other of string

let split_lines text =
  String.split_on_char '\n' text
  |> List.map (fun line ->
         let length = String.length line in
         if length > 0 && Char.equal line.[length - 1] '\r' then
           String.sub line 0 (length - 1)
         else line)

let join_lines lines = String.concat "\n" lines

let parse_status_line line =
  match String.split_on_char ' ' line with
  | http_version :: status :: rest when String.length http_version >= 5 -> (
      match int_of_string_opt status with
      | Some status -> Ok (status, String.concat " " rest)
      | None -> Error "invalid HTTP status code")
  | _ -> Error "missing HTTP status line"

let parse_header line =
  match String.index_opt line ':' with
  | None -> None
  | Some index ->
      let name = String.sub line 0 index in
      let value_start = index + 1 in
      let value_length = String.length line - value_start in
      let value = String.sub line value_start value_length |> String.trim in
      Some (name, value)

let rec split_header_block acc = function
  | [] -> Error "missing response body separator"
  | "" :: rest -> Ok (List.rev acc, rest)
  | line :: rest -> split_header_block (line :: acc) rest

let parse_curl_output raw request =
  let lines = split_lines raw in
  match List.rev lines with
  | time_total :: status_code :: body_and_headers_rev -> (
      match (int_of_string_opt status_code, float_of_string_opt time_total) with
      | Some status, Some seconds -> (
          let body_and_headers = List.rev body_and_headers_rev in
          match split_header_block [] body_and_headers with
          | Error message -> Error message
          | Ok (header_lines, body_lines) -> (
              match header_lines with
              | status_line :: header_lines -> (
                  match parse_status_line status_line with
                  | Error message -> Error message
                  | Ok (header_status, status_text) ->
                      if status <> header_status then Error "curl status does not match HTTP status"
                      else
                        let headers = List.filter_map parse_header header_lines in
                        Ok
                          {
                            Ast.status;
                            status_text;
                            headers;
                            body = join_lines body_lines;
                            duration_ms = int_of_float (seconds *. 1000.);
                            request;
                          })
              | [] -> Error "missing HTTP status line"))
      | None, _ -> Error "invalid curl status trailer"
      | _, None -> Error "invalid curl time trailer")
  | _ -> Error "missing curl trailers"

let lower text = String.lowercase_ascii text

let contains haystack needle =
  let haystack = lower haystack in
  let needle = lower needle in
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop index =
    if needle_length = 0 then true
    else if index + needle_length > haystack_length then false
    else if String.sub haystack index needle_length = needle then true
    else loop (index + 1)
  in
  loop 0

let detect_content_type response =
  let content_type =
    response.Ast.headers
    |> List.find_map (fun (name, value) ->
           if String.equal (lower name) "content-type" then Some value else None)
  in
  match content_type with
  | None -> Plain
  | Some value when contains value "json" -> Json
  | Some value when contains value "xml" -> Xml
  | Some value when contains value "html" -> Html
  | Some value when contains value "text/plain" -> Plain
  | Some value -> Other value

let rec pretty_json indent json =
  let spaces count = String.make count ' ' in
  match json with
  | `Assoc fields ->
      let child_indent = indent + 2 in
      let field_to_string (name, value) =
        Printf.sprintf "%s%s: %s" (spaces child_indent)
          (Yojson.Safe.to_string (`String name))
          (pretty_json child_indent value)
      in
      "{\n" ^ String.concat ",\n" (List.map field_to_string fields) ^ "\n"
      ^ spaces indent ^ "}"
  | `List values ->
      let child_indent = indent + 2 in
      let value_to_string value = spaces child_indent ^ pretty_json child_indent value in
      "[\n" ^ String.concat ",\n" (List.map value_to_string values) ^ "\n"
      ^ spaces indent ^ "]"
  | value -> Yojson.Safe.to_string value

let pretty_print_body content_type body =
  match content_type with
  | Json -> (
      match Yojson.Safe.from_string body with
      | json -> pretty_json 0 json
      | exception Yojson.Json_error _ -> body)
  | _ -> body

let render response =
  let status_line =
    Printf.sprintf "HTTP %d %s (%d ms)" response.Ast.status response.status_text
      response.duration_ms
  in
  let header_lines =
    List.map (fun (name, value) -> Printf.sprintf "%s: %s" name value) response.headers
  in
  let body = pretty_print_body (detect_content_type response) response.body in
  status_line :: header_lines @ [ ""; body ]
