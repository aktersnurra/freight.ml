open Core
open Async

let register_commands rpc channel =
  let cmd name nargs rpc_method =
    let nargs_str = match nargs with
      | `None -> ""
      | `Optional -> " -nargs=?"
      | `Required -> " -nargs=1"
    in
    let call_str = match nargs with
      | `None -> Printf.sprintf "call rpcrequest(%d, '%s')" channel rpc_method
      | `Optional -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
      | `Required -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
    in
    let cmd_str = Printf.sprintf "command!%s %s %s" nargs_str name call_str in
    match%map Nvim_rpc.call rpc "nvim_command" [ Msgpck.String cmd_str ] with
    | Ok _ -> ()
    | Error e -> eprintf "ERROR registering %s: %s\n" name e
  in
  let%bind () = cmd "FreightOpen"    `None     "FreightOpen"    in
  let%bind () = cmd "FreightRun"     `None     "FreightRun"     in
  let%bind () = cmd "FreightEnv"     `Optional "FreightEnv"     in
  let%bind () = cmd "FreightInspect" `None     "FreightInspect" in
  let%bind () = cmd "FreightView"    `Required "FreightView"    in
  return ()

let dispatch rpc state method_ params =
  match method_ with
  | "FreightOpen" ->
    let%map () = Handlers.freight_open ~rpc state in
    Msgpck.Nil
  | "FreightRun" ->
    let%map () = Handlers.freight_run ~rpc state in
    Msgpck.Nil
  | "FreightEnv" ->
    let arg = match params with
      | Msgpck.String s :: _ when not (String.is_empty s) -> Some s
      | _ -> None
    in
    let%map () = Handlers.freight_env ~rpc state arg in
    Msgpck.Nil
  | "FreightInspect" ->
    let%map () = Handlers.freight_inspect ~rpc state in
    Msgpck.Nil
  | "FreightView" ->
    let view_name = match params with
      | Msgpck.String s :: _ -> s
      | _ -> "All"
    in
    let%map () = Handlers.freight_view ~rpc state view_name in
    Msgpck.Nil
  | _ ->
    return Msgpck.Nil

let rec loop rpc incoming state =
  match%bind Nvim_rpc.read incoming with
  | Nvim_rpc.Request { msgid; method_; params } ->
    let%bind result = dispatch rpc state method_ params in
    Nvim_rpc.reply_ok rpc ~msgid result;
    loop rpc incoming state
  | Nvim_rpc.Notification _ ->
    loop rpc incoming state

let main () =
  let rpc, incoming, reader_done = Nvim_rpc.create () in
  don't_wait_for reader_done;
  let state = State.create () in
  (* We initiate: ask Neovim for api info, which returns [channel_id, info] *)
  let%bind channel =
    match%map Nvim_rpc.call rpc "nvim_get_api_info" [] with
    | Ok (Msgpck.List (Msgpck.Int ch :: _)) -> ch
    | Ok other ->
      failwithf "unexpected api_info reply: %s" (Msgpck.show other) ()
    | Error e ->
      failwithf "api_info error: %s" e ()
  in
  let%bind () = register_commands rpc channel in
  loop rpc incoming state

let () =
  don't_wait_for (main ());
  never_returns (Scheduler.go ())
