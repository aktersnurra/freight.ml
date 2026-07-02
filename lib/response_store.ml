module String_map = Map.Make (String)

type t = Ast.response String_map.t

let empty = String_map.empty

let record ~name response store =
  if name = "" then store else String_map.add name response store

let lower = String.lowercase_ascii

(* A reference like "login.response.body.data.id" splits into
   name="login", kind="body", rest="data.id". *)
let split_reference ref =
  match String.split_on_char '.' ref with
  | name :: "response" :: kind :: rest -> Some (name, kind, String.concat "." rest)
  | _ -> None

let body_value response path =
  match Yojson.Safe.from_string response.Ast.body with
  | json -> Json_path.lookup json (Json_path.parse path)
  | exception Yojson.Json_error _ -> None

let header_value response header =
  let header = lower header in
  List.find_map
    (fun (name, data) -> if lower name = header then Some data else None)
    response.Ast.headers

let source store ref =
  match split_reference ref with
  | Some (name, "body", path) -> (
      match String_map.find_opt name store with
      | Some response -> body_value response path
      | None -> None)
  | Some (name, "headers", header) -> (
      match String_map.find_opt name store with
      | Some response -> header_value response header
      | None -> None)
  | _ -> None
