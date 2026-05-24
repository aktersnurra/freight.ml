open Core
open Async

let nvim_call rpc method_ params =
  match%map Rpc.call rpc method_ params with
  | Ok result -> result
  | Error e -> failwithf "nvim call %s failed: %s" method_ e ()

let show ~rpc ~name ~filetype ~lines =
  let%bind buf = nvim_call rpc "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  let handle = match buf with Msgpck.Int n -> n | _ -> failwith "expected buffer handle" in
  let%bind _ = nvim_call rpc "nvim_buf_set_name" [ Msgpck.Int handle; Msgpck.String name ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Msgpck.Int handle; Msgpck.String "buftype"; Msgpck.String "nofile" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Msgpck.Int handle; Msgpck.String "filetype"; Msgpck.String filetype ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Msgpck.Int handle; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let msgpack_lines = Msgpck.List (List.map lines ~f:(fun l -> Msgpck.String l)) in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ Msgpck.Int handle; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Msgpck.Int handle; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  let%map _ = nvim_call rpc "nvim_command" [ Msgpck.String (Printf.sprintf "split | buffer %d" handle) ] in
  ()
