type source = string -> string option
type t = source list

let make sources = sources

(* Capture anything between braces; each source decides if it recognizes it. *)
let variable = Re.Perl.compile_pat "\\{\\{[ \\t]*([^}]*?)[ \\t]*\\}\\}"

let first_some sources ref =
  List.fold_left
    (fun acc source -> match acc with Some _ -> acc | None -> source ref)
    None sources

let resolve sources source_text =
  Re.replace variable source_text ~f:(fun group ->
      let ref = Re.Group.get group 1 in
      match first_some sources ref with
      | Some value -> value
      | None -> Re.Group.get group 0)

let unresolved sources source_text =
  let seen = Hashtbl.create 8 in
  Re.all variable source_text
  |> List.filter_map (fun group ->
         let ref = Re.Group.get group 1 in
         match first_some sources ref with
         | Some _ -> None
         | None ->
             if Hashtbl.mem seen ref then None
             else begin
               Hashtbl.add seen ref ();
               Some ref
             end)
  |> List.sort_uniq String.compare
