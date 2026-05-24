open Core
open Async

let ext_to_int s =
  String.fold s ~init:0 ~f:(fun acc c -> (acc lsl 8) lor Char.to_int c)

let nvim_call rpc method_ params =
  match%map Nvim_rpc.call rpc method_ params with
  | Ok result -> result
  | Error e -> failwithf "nvim call %s failed: %s" method_ e ()

let show ~rpc ~name ~filetype ~lines =
  let%bind buf = nvim_call rpc "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  (* buf is Ext(0, payload) in Neovim 0.13+; extract integer for nvim_command *)
  let handle_int = match buf with
    | Msgpck.Int n -> n
    | Msgpck.Ext (_, s) -> ext_to_int s
    | _ -> failwith "expected buffer handle"
  in
  let%bind _ = nvim_call rpc "nvim_command"
    [ Msgpck.String (Printf.sprintf "silent! bwipeout %s" name) ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_name" [ buf; Msgpck.String name ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "buftype"; Msgpck.String "nofile" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "filetype"; Msgpck.String filetype ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let flat_lines = List.concat_map lines ~f:(String.split ~on:'\n') in
  let msgpack_lines = Msgpck.List (List.map flat_lines ~f:(fun l -> Msgpck.String l)) in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  let%map _ = nvim_call rpc "nvim_command" [ Msgpck.String (Printf.sprintf "split | buffer %d" handle_int) ] in
  ()

let update ~rpc buf ~filetype ~lines =
  let flat_lines = List.concat_map lines ~f:(String.split ~on:'\n') in
  let msgpack_lines = Msgpck.List (List.map flat_lines ~f:(fun l -> Msgpck.String l)) in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "filetype"; Msgpck.String filetype ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ] in
  let%map _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  ()

let show_loading ~rpc ~name =
  let%bind buf = nvim_call rpc "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  let handle_int = match buf with
    | Msgpck.Int n -> n
    | Msgpck.Ext (_, s) -> ext_to_int s
    | _ -> failwith "expected buffer handle"
  in
  let%bind _ = nvim_call rpc "nvim_command"
    [ Msgpck.String (Printf.sprintf "silent! bwipeout %s" name) ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_name" [ buf; Msgpck.String name ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "buftype"; Msgpck.String "nofile" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ] in
  let loading = Msgpck.List [ Msgpck.String "Loading\xe2\x80\xa6" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; loading ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ] in
  let%map _ = nvim_call rpc "nvim_command" [ Msgpck.String (Printf.sprintf "split | buffer %d" handle_int) ] in
  buf
