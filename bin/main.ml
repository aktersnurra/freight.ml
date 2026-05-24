open Core
open Async

let register_commands rpc channel =
  let cmd name nargs rpc_method =
    let nargs_str = match nargs with
      | `None -> ""
      | `Optional -> " -nargs=?"
    in
    let call_str = match nargs with
      | `None -> Printf.sprintf "call rpcrequest(%d, '%s')" channel rpc_method
      | `Optional -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
    in
    Nvim_rpc.call rpc "nvim_command"
      [ Msgpck.String (Printf.sprintf "command!%s %s %s" nargs_str name call_str) ]
    >>| ignore
  in
  let%bind () = cmd "FreightOpen"    `None     "FreightOpen"    in
  let%bind () = cmd "FreightRun"     `None     "FreightRun"     in
  let%bind () = cmd "FreightEnv"     `Optional "FreightEnv"     in
  let%bind () = cmd "FreightInspect" `None     "FreightInspect" in
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
  | _ ->
    return Msgpck.Nil

let rec loop rpc state =
  match%bind Nvim_rpc.read rpc with
  | Nvim_rpc.Request { msgid; method_; params } ->
    let%bind result = dispatch rpc state method_ params in
    Nvim_rpc.reply_ok rpc ~msgid result;
    loop rpc state
  | Nvim_rpc.Notification _ ->
    loop rpc state

let main () =
  let rpc = Nvim_rpc.create () in
  let state = State.create () in
  let%bind channel =
    match%map Nvim_rpc.read rpc with
    | Nvim_rpc.Notification { params = Msgpck.Int ch :: _; _ } -> ch
    | Nvim_rpc.Request { params = Msgpck.Int ch :: _; _ } -> ch
    | _ -> failwith "unexpected first message from neovim"
  in
  let%bind () = register_commands rpc channel in
  loop rpc state

let () =
  don't_wait_for (main ());
  never_returns (Scheduler.go ())
