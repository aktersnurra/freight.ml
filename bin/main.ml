let register_commands ~call channel =
  let cmd name nargs rpc_method =
    let nargs_str =
      match nargs with
      | `None -> ""
      | `Optional -> " -nargs=?"
      | `Required -> " -nargs=1"
    in
    let call_str =
      match (name, nargs) with
      | "FreightEnv", `Optional ->
        "lua require('freight').freight_env_command(<q-args>)"
      | _, `None ->
        Printf.sprintf "call rpcrequest(%d, '%s')" channel rpc_method
      | _, (`Optional | `Required) ->
        Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
    in
    let cmd_str = Printf.sprintf "command!%s %s %s" nargs_str name call_str in
    ignore (call "nvim_command" [ Msgpck.String cmd_str ])
  in
  cmd "FreightOpen"        `None     "FreightOpen";
  cmd "FreightRun"         `None     "FreightRun";
  cmd "FreightRunAll"      `None     "FreightRunAll";
  cmd "FreightEnv"         `Optional "FreightEnv";
  cmd "FreightEnvApply"    `Required "FreightEnvApply";
  cmd "FreightInspect"     `None     "FreightInspect";
  cmd "FreightView"        `Required "FreightView";
  cmd "FreightViewRunAll"  `Required "FreightViewRunAll";
  cmd "FreightJumpRunAll"  `Required "FreightJumpRunAll";
  cmd "FreightHelp"        `None     "FreightHelp";
  cmd "FreightHistory"     `None     "FreightHistory";
  cmd "FreightViewHistory" `Required "FreightViewHistory"

let dispatch state method_ params =
  match method_ with
  | "FreightOpen" ->
    Handlers.freight_open state;
    Msgpck.Nil
  | "FreightRun" ->
    Handlers.freight_run state;
    Msgpck.Nil
  | "FreightRunAll" ->
    Handlers.freight_run_all state;
    Msgpck.Nil
  | "FreightEnv" ->
    let arg =
      match params with
      | Msgpck.String s :: _ when s <> "" -> Some s
      | _ -> None
    in
    Handlers.freight_env state arg;
    Msgpck.Nil
  | "FreightEnvApply" ->
    let arg =
      match params with
      | Msgpck.String s :: _ -> Some s
      | _ -> Some ""
    in
    Handlers.freight_env_apply state arg;
    Msgpck.Nil
  | "FreightInspect" ->
    Handlers.freight_inspect state;
    Msgpck.Nil
  | "FreightView" ->
    let view_name =
      match params with
      | Msgpck.String s :: _ -> s
      | _ -> "All"
    in
    Handlers.freight_view state view_name;
    Msgpck.Nil
  | "FreightViewRunAll" ->
    let line_number =
      match params with
      | Msgpck.String s :: _ -> (try int_of_string (String.trim s) with _ -> 1)
      | Msgpck.Int n :: _ -> n
      | _ -> 1
    in
    Handlers.freight_view_run_all state line_number;
    Msgpck.Nil
  | "FreightJumpRunAll" ->
    let line_number =
      match params with
      | Msgpck.String s :: _ -> (try int_of_string (String.trim s) with _ -> 1)
      | Msgpck.Int n :: _ -> n
      | _ -> 1
    in
    Handlers.freight_jump_run_all state line_number;
    Msgpck.Nil
  | "FreightHelp" ->
    Handlers.freight_help state;
    Msgpck.Nil
  | "FreightHistory" ->
    Handlers.freight_history state;
    Msgpck.Nil
  | "FreightViewHistory" ->
    let line_number =
      match params with
      | Msgpck.String s :: _ -> (try int_of_string (String.trim s) with _ -> 1)
      | Msgpck.Int n :: _ -> n
      | _ -> 1
    in
    Handlers.freight_view_history state line_number;
    Msgpck.Nil
  | _ ->
    Msgpck.Nil

let loop ~proc_mgr ~sw ~rpc state =
  while true do
    match Nvim_rpc.read rpc with
    | Nvim_rpc.Request { msgid; method_; params } ->
      (try
         let result =
           Freight_runtime.run ~proc_mgr ~sw ~rpc @@ fun () ->
             dispatch state method_ params
         in
         Nvim_rpc.reply_ok rpc ~msgid result
       with exn ->
         Nvim_rpc.reply_error rpc ~msgid (Printexc.to_string exn))
    | Nvim_rpc.Notification { method_; params } ->
      (try
         ignore
           (Freight_runtime.run ~proc_mgr ~sw ~rpc @@ fun () ->
              dispatch state method_ params)
       with exn ->
         try
           Freight_runtime.run ~proc_mgr ~sw ~rpc @@ fun () ->
             Freight_effect.notify Freight_effect.Error (Printexc.to_string exn)
         with _ -> ())
  done

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
    let stdin = Eio.Stdenv.stdin env in
    let stdout = Eio.Stdenv.stdout env in
    let proc_mgr = Eio.Stdenv.process_mgr env in
    let rpc =
      Nvim_rpc.create ~sw
        ~stdin:(stdin :> _ Eio.Flow.source)
        ~stdout:(stdout :> _ Eio.Flow.sink)
    in
    let state = State.create () in
    let channel =
      match Nvim_rpc.call rpc "nvim_get_api_info" [] with
      | Msgpck.List (Msgpck.Int ch :: _) -> ch
      | other ->
        failwith ("unexpected api_info reply: " ^ Msgpck.show other)
    in
    Freight_runtime.run ~proc_mgr ~sw ~rpc @@ fun () ->
      register_commands ~call:Freight_effect.nvim_call channel;
    loop ~proc_mgr ~sw ~rpc state
