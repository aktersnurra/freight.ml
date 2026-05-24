open Core
open Async
open Vcaml

let freight_open_rpc =
  Vcaml_plugin.Persistent.Rpc.create_blocking
    [%here]
    ~name:"FreightOpen"
    ~type_:Ocaml_from_nvim.Blocking.(return Nil)
    ~f:(fun state ~run_in_background:_ ~client ->
      Handlers.freight_open ~client state)
;;

let freight_env_rpc =
  Vcaml_plugin.Persistent.Rpc.create_blocking
    [%here]
    ~name:"FreightEnv"
    ~type_:Ocaml_from_nvim.Blocking.Expert.(varargs ~args_type:Type.String ~return_type:Type.Nil)
    ~f:(fun state ~run_in_background:_ ~client args ->
      let arg = match args with
        | [] -> None
        | s :: _ -> if String.is_empty s then None else Some s
      in
      Handlers.freight_env ~client state arg)
;;

let freight_inspect_rpc =
  Vcaml_plugin.Persistent.Rpc.create_blocking
    [%here]
    ~name:"FreightInspect"
    ~type_:Ocaml_from_nvim.Blocking.(return Nil)
    ~f:(fun state ~run_in_background:_ ~client ->
      Handlers.freight_inspect ~client state)
;;

let freight_run_rpc =
  Vcaml_plugin.Persistent.Rpc.create_blocking
    [%here]
    ~name:"FreightRun"
    ~type_:Ocaml_from_nvim.Blocking.(return Nil)
    ~f:(fun state ~run_in_background:_ ~client ->
      Handlers.freight_run ~client state)
;;

let on_startup client =
  let open Deferred.Or_error.Let_syntax in
  let state = State.create () in
  let channel = Client.channel client in
  let%bind () =
    block_nvim [%here] client ~f:(fun client ->
      let open Deferred.Or_error.Let_syntax in
      let%bind () =
        Command.create
          [%here]
          client
          ~bar:true
          ()
          ~name:"FreightOpen"
          ~scope:`Global
          (Viml (Printf.sprintf "call rpcrequest(%d, 'FreightOpen')" channel))
      in
      let%bind () =
        Command.create
          [%here]
          client
          ~bar:true
          ~nargs:At_most_one
          ()
          ~name:"FreightEnv"
          ~scope:`Global
          (Viml (Printf.sprintf "call rpcrequest(%d, 'FreightEnv', <q-args>)" channel))
      in
      let%bind () =
        Command.create
          [%here]
          client
          ~bar:true
          ()
          ~name:"FreightInspect"
          ~scope:`Global
          (Viml (Printf.sprintf "call rpcrequest(%d, 'FreightInspect')" channel))
      in
      let%bind () =
        Command.create
          [%here]
          client
          ~bar:true
          ()
          ~name:"FreightRun"
          ~scope:`Global
          (Viml (Printf.sprintf "call rpcrequest(%d, 'FreightRun')" channel))
      in
      return ())
  in
  return state
;;

let after_startup state ~client =
  let open Deferred.Or_error.Let_syntax in
  ignore state;
  let%bind group =
    Autocmd.Group.create [%here] client ~clear_if_exists:true "FreightFiletype"
  in
  let%bind _id =
    Autocmd.create
      [%here]
      client
      ~description:"Set filetype=http for .http and .rest files"
      ~group
      ~patterns_or_buffer:
        (Autocmd.Patterns_or_buffer.Patterns
           (Nonempty_list.of_list_exn [ "*.http"; "*.rest" ]))
      ~events:(Nonempty_list.singleton Autocmd.Event.BufEnter)
      (Viml "if &filetype ==# '' | setlocal filetype=http | endif")
  in
  return ()
;;

let command =
  Vcaml_plugin.Persistent.create
    ~name:"freight"
    ~description:"Freight HTTP plugin for Neovim"
    ~on_startup
    ~after_startup
    ~notify_fn:(`Viml "function('freight#on_startup')")
    [ freight_open_rpc
    ; freight_env_rpc
    ; freight_inspect_rpc
    ; freight_run_rpc
    ]
;;

let () = Command_unix.run command
