module String_map = Map.Make (String)

type t = string String_map.t

let empty = String_map.empty
let of_list pairs = List.fold_left (fun env (key, data) -> String_map.add key data env) empty pairs
let find env key = String_map.find_opt key env
let add env ~key ~data = String_map.add key data env

let read_lines path =
  let channel = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () ->
      let rec loop lines =
        match input_line channel with
        | line -> loop (line :: lines)
        | exception End_of_file -> List.rev lines
      in
      loop [])

let parse_line env line =
  let line = String.trim line in
  if line = "" || String.starts_with ~prefix:"#" line then env
  else
    match String.index_opt line '=' with
    | None -> env
    | Some index ->
        let key = String.sub line 0 index |> String.trim in
        let data =
          String.sub line (index + 1) (String.length line - index - 1)
          |> String.trim
        in
        if key = "" then env else add env ~key ~data

let load_file env path =
  if Sys.file_exists path then List.fold_left parse_line env (read_lines path) else env

let ancestors dir =
  let rec loop acc dir =
    let parent = Filename.dirname dir in
    let acc = dir :: acc in
    if parent = dir then acc else loop acc parent
  in
  let dir = if Filename.is_relative dir then Filename.concat (Sys.getcwd ()) dir else dir in
  loop [] dir

let load ~dir ~active_env =
  let names =
    match active_env with
    | None -> [ ".env"; ".env.local" ]
    | Some active_env -> [ ".env"; ".env." ^ active_env; ".env.local" ]
  in
  ancestors dir
  |> List.fold_left
       (fun env dir ->
         List.fold_left
           (fun env name -> load_file env (Filename.concat dir name))
           env names)
       empty

let variable = Re.Perl.compile_pat "\\{\\{[ \\t]*([A-Za-z_][A-Za-z0-9_.-]*)[ \\t]*\\}\\}"

let substitute env source =
  Re.replace variable source ~f:(fun group ->
      let key = Re.Group.get group 1 in
      match find env key with Some data -> data | None -> Re.Group.get group 0)
