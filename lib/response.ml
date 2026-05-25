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
  | http_version :: status :: rest
    when String.length http_version >= 5
         && String.equal (String.sub http_version 0 5) "HTTP/" -> (
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

let starts_with_http line =
  String.length line >= 5 && String.equal (String.sub line 0 5) "HTTP/"

let rec split_response_header_block = function
  | [] -> Error "missing HTTP status line"
  | line :: _ as lines when starts_with_http line -> split_header_block [] lines
  | _ :: rest -> split_response_header_block rest

let is_response_header_block lines =
  match split_response_header_block lines with
  | Error _ -> false
  | Ok (status_line :: header_lines, _) ->
      Result.is_ok (parse_status_line status_line)
      && List.for_all (fun line -> Option.is_some (parse_header line)) header_lines
  | Ok ([], _) -> false

let rec last_response_header_block lines =
  match split_response_header_block lines with
  | Error message -> Error message
  | Ok (header_lines, body_lines) -> (
      match body_lines with
      | next :: _ when starts_with_http next && is_response_header_block body_lines ->
          last_response_header_block body_lines
      | _ -> Ok (header_lines, body_lines))

let parse_curl_output raw request =
  let lines = split_lines raw in
  match List.rev lines with
  | time_total :: status_code :: body_and_headers_rev -> (
      match (int_of_string_opt status_code, float_of_string_opt time_total) with
      | Some status, Some seconds -> (
          let body_and_headers = List.rev body_and_headers_rev in
          match last_response_header_block body_and_headers with
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

let pretty_print_body content_type body =
  match content_type with
  | Json -> (
      match Yojson.Safe.from_string body with
      | json -> Yojson.Safe.pretty_to_string json
      | exception Yojson.Json_error _ -> body)
  | _ -> body

let box_width = 60

let pad_right s len =
  let n = String.length s in
  if n >= len then String.sub s 0 len
  else s ^ String.make (len - n) ' '

let box_section title rows =
  let inner = box_width - 2 in
  let dash_str = "\xe2\x94\x80" in
  let dash_count = max 0 (inner - String.length title - 3) in
  let dashes = String.concat "" (List.init dash_count (fun _ -> dash_str)) in
  let top = "\xe2\x95\xad\xe2\x94\x80 " ^ title ^ " " ^ dashes ^ "\xe2\x95\xae" in
  let bottom = "\xe2\x95\xb0" ^ String.concat "" (List.init inner (fun _ -> dash_str)) ^ "\xe2\x95\xaf" in
  let body =
    List.map (fun row ->
      let content = pad_right row (inner - 2) in
      "\xe2\x94\x82  " ^ content ^ "\xe2\x94\x82"
    ) rows
  in
  top :: body @ [ bottom ]

let kv_row key value =
  let k = pad_right key 12 in
  k ^ "  " ^ value

let render response =
  let status = Printf.sprintf "HTTP %d %s" response.Ast.status response.status_text in
  let timing = Printf.sprintf "%d ms" response.duration_ms in
  let status_rows = [ kv_row "Status" status; kv_row "Time" timing ] in
  let header_rows =
    List.map (fun (name, value) -> kv_row name value) response.headers
  in
  let body = pretty_print_body (detect_content_type response) response.body in
  box_section "Response" status_rows
  @ [ "" ]
  @ box_section "Headers" header_rows
  @ [ "" ]
  @ box_section "Body" (split_lines body)

let render_body response =
  let body = pretty_print_body (detect_content_type response) response.body in
  box_section "Body" (split_lines body)

let render_headers response =
  let status = Printf.sprintf "HTTP %d %s" response.Ast.status response.status_text in
  let timing = Printf.sprintf "%d ms" response.duration_ms in
  let rows =
    kv_row "Status" status
    :: kv_row "Time" timing
    :: List.map (fun (name, value) -> kv_row name value) response.headers
  in
  box_section "Headers" rows

let render_all = render

let render_verbose raw =
  box_section "Verbose" (split_lines raw)
