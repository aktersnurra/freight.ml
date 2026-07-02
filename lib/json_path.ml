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
         (* A bracketed segment [n] is an array index when n is an integer;
            anything else (including a malformed [abc]) is treated as a literal
            field so [parse] is total and never raises on user input. *)
         if n >= 2 && segment.[0] = '[' && segment.[n - 1] = ']' then
           match int_of_string_opt (String.sub segment 1 (n - 2)) with
           | Some i -> Index i
           | None -> Field segment
         else
           match int_of_string_opt segment with
           | Some i -> Index i
           | None -> Field segment)

let scalar_to_string = function
  | `String s -> Some s
  | `Int i -> Some (string_of_int i)
  | `Intlit s -> Some s
  (* [string_of_float 9.0] is "9.", not valid JSON; Yojson renders "9.0". *)
  | `Float _ as json -> Some (Yojson.Safe.to_string json)
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
