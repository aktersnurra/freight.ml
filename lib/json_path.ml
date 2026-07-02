type step =
  | Field of string
  | Index of int

let parse path =
  let buf = Stdlib.Buffer.create (String.length path + 8) in
  String.iter
    (fun c ->
      if c = '[' then Stdlib.Buffer.add_string buf ".["
      else Stdlib.Buffer.add_char buf c)
    path;
  Stdlib.Buffer.contents buf
  |> String.split_on_char '.'
  |> List.filter (fun s -> s <> "")
  |> List.map (fun segment ->
         let n = String.length segment in
         if n >= 2 && segment.[0] = '[' && segment.[n - 1] = ']' then
           Index (int_of_string (String.sub segment 1 (n - 2)))
         else
           match int_of_string_opt segment with
           | Some i -> Index i
           | None -> Field segment)

let scalar_to_string = function
  | `String s -> Some s
  | `Int i -> Some (string_of_int i)
  | `Intlit s -> Some s
  | `Float f -> Some (string_of_float f)
  | `Bool b -> Some (string_of_bool b)
  | `Null -> Some "null"
  | `Assoc _ | `List _ | `Tuple _ | `Variant _ -> None

let rec walk json = function
  | [] -> scalar_to_string json
  | Field key :: rest -> (
      match json with
      | `Assoc fields -> (
          match List.assoc_opt key fields with
          | Some json -> walk json rest
          | None -> None)
      | _ -> None)
  | Index i :: rest -> (
      match json with
      | `List items -> (
          match List.nth_opt items i with
          | Some json -> walk json rest
          | None -> None)
      | _ -> None)

let lookup json steps = walk json steps
