type extraction_path =
  | Response_body of string list
  | Response_header of string

let lower = String.lowercase_ascii

let rec find_body_path json = function
  | [] -> Some json
  | key :: rest -> (
      match json with
      | `Assoc fields -> (
          match List.assoc_opt key fields with
          | Some json -> find_body_path json rest
          | None -> None)
      | _ -> None)

let scalar_to_string = function
  | `String value -> Some value
  | `Int value -> Some (string_of_int value)
  | `Intlit value -> Some value
  | `Float value -> Some (string_of_float value)
  | `Bool value -> Some (string_of_bool value)
  | `Null -> Some "null"
  | `Assoc _ | `List _ | `Tuple _ | `Variant _ -> None

let extract_body response path =
  match Yojson.Safe.from_string response.Ast.body with
  | json -> Option.bind (find_body_path json path) scalar_to_string
  | exception Yojson.Json_error _ -> None

let extract_header response header =
  let header = lower header in
  List.find_map
    (fun (name, data) -> if String.equal (lower name) header then Some data else None)
    response.Ast.headers

let extract response = function
  | Response_body path -> extract_body response path
  | Response_header header -> extract_header response header

let inject_body_field ~name env key json =
  match scalar_to_string json with
  | None -> env
  | Some data -> Env.add env ~key:(name ^ ".response.body." ^ key) ~data

let inject_body ~name response env =
  match Yojson.Safe.from_string response.Ast.body with
  | `Assoc fields ->
      List.fold_left
        (fun env (key, json) -> inject_body_field ~name env key json)
        env fields
  | _ -> env
  | exception Yojson.Json_error _ -> env

let inject_headers ~name response env =
  List.fold_left
    (fun env (header, data) ->
      Env.add env ~key:(name ^ ".response.headers." ^ header) ~data)
    env response.Ast.headers

let inject ~name response env = env |> inject_body ~name response |> inject_headers ~name response
