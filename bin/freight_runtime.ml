let ext_to_int s =
  String.fold_left (fun acc c -> (acc lsl 8) lor Char.code c) 0 s

let decode_buffer_id = function
  | Msgpck.Int n -> n
  | Msgpck.Ext (_, s) -> ext_to_int s
  | other -> failwith ("expected buffer id: " ^ Msgpck.show other)

let decode_string_list = function
  | Msgpck.List xs ->
    List.filter_map
      (function Msgpck.String s -> Some s | _ -> None)
      xs
  | _ -> []

let decode_dirname_opt = function
  | Msgpck.String s when s <> "" -> Some (Filename.dirname s)
  | _ -> None

let decode_cursor = function
  | Msgpck.List (Msgpck.Int row :: Msgpck.Int col :: _) ->
    { Freight_effect.Cursor.row = row - 1; col }
  | _ ->
    { Freight_effect.Cursor.row = 0; col = 0 }

let run_curl ~proc_mgr invocation =
  match
    Eio.Process.parse_out proc_mgr Eio.Buf_read.take_all
      ("curl" :: invocation.Freight.Executor.args)
  with
  | output -> Ok output
  | exception exn -> Error (Printexc.to_string exn)

let run_curl_verbose ~proc_mgr invocation =
  let stderr_buf = Buffer.create 4096 in
  let stderr_sink = Eio.Flow.buffer_sink stderr_buf in
  let args = "-v" :: invocation.Freight.Executor.args in
  match
    Eio.Process.parse_out ~stderr:stderr_sink proc_mgr Eio.Buf_read.take_all
      ("curl" :: args)
  with
  | _stdout -> Ok (Buffer.contents stderr_buf)
  | exception exn ->
    if Buffer.length stderr_buf > 0 then Ok (Buffer.contents stderr_buf)
    else Error (Printexc.to_string exn)

let rec run : type a. proc_mgr:_ -> sw:_ -> rpc:_ -> (unit -> a) -> a =
  fun ~proc_mgr ~sw ~rpc f ->
  let call = Nvim_rpc.call rpc in
  Effect.Deep.try_with f ()
    { effc =
        (fun (type a) (eff : a Effect.t) ->
          match eff with
          | Freight_effect.Current_buffer ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let msg = call "nvim_get_current_buf" [] in
              Effect.Deep.continue k (decode_buffer_id msg))
          | Freight_effect.Buffer_lines buf ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let msg =
                call "nvim_buf_get_lines"
                  [ Msgpck.Int buf
                  ; Msgpck.Int 0
                  ; Msgpck.Int (-1)
                  ; Msgpck.Bool false
                  ]
              in
              Effect.Deep.continue k (decode_string_list msg))
          | Freight_effect.Buffer_dir buf ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let msg = call "nvim_buf_get_name" [ Msgpck.Int buf ] in
              Effect.Deep.continue k (decode_dirname_opt msg))
          | Freight_effect.Cursor ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let msg = call "nvim_win_get_cursor" [ Msgpck.Int 0 ] in
              Effect.Deep.continue k (decode_cursor msg))
          | Freight_effect.Show_scratch view ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let buf_id =
                Scratch.show ~call
                  ~name:view.name ~filetype:view.filetype ~lines:view.lines
              in
              Effect.Deep.continue k buf_id)
          | Freight_effect.Show_float view ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Scratch.show_float ~call ~lines:view.lines;
              Effect.Deep.continue k ())
          | Freight_effect.Update_scratch (buf, view) ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Scratch.update ~call buf
                ~filetype:view.filetype ~lines:view.lines;
              Effect.Deep.continue k ())
          | Freight_effect.Set_keymap (buf, key, command) ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Scratch.set_keymap ~call buf ~key ~command;
              Effect.Deep.continue k ())
          | Freight_effect.Load_env { dir; active_env } ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let env = Freight.Env.load ~dir ~active_env in
              Effect.Deep.continue k env)
          | Freight_effect.Run_curl invocation ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let result = run_curl ~proc_mgr invocation in
              Effect.Deep.continue k result)
          | Freight_effect.Run_curl_verbose invocation ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let result = run_curl_verbose ~proc_mgr invocation in
              Effect.Deep.continue k result)
          | Freight_effect.Notify (level, msg) ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let level_int =
                match level with
                | Freight_effect.Info -> 2
                | Warning -> 3
                | Error -> 4
              in
              ignore (call "nvim_notify"
                [ Msgpck.String msg
                ; Msgpck.Int level_int
                ; Msgpck.Map []
                ]);
              Effect.Deep.continue k ())
          | Freight_effect.Fork (_label, child) ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Eio.Fiber.fork ~sw (fun () ->
                (* Nothing raised in a forked fiber may escape to [~sw] — that
                   would cancel the switch and kill the whole RPC loop. Guard the
                   error-reporting path too, in case the notify RPC itself faults. *)
                try run ~proc_mgr ~sw ~rpc child
                with exn -> (
                  try
                    run ~proc_mgr ~sw ~rpc (fun () ->
                      Freight_effect.notify Freight_effect.Error
                        (Printexc.to_string exn))
                  with _ -> ()));
              Effect.Deep.continue k ())
          | Freight_effect.Nvim_call (method_, params) ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let result = call method_ params in
              Effect.Deep.continue k result)
          | Freight_effect.File_exists path ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Effect.Deep.continue k (Sys.file_exists path))
          | Freight_effect.File_size path ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let size =
                try Some (In_channel.with_open_bin path In_channel.length |> Int64.to_int)
                with Sys_error _ -> None
              in
              Effect.Deep.continue k size)
          | Freight_effect.Write_file { path; data } ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              let result =
                try
                  let channel = open_out_bin path in
                  Fun.protect
                    ~finally:(fun () -> close_out_noerr channel)
                    (fun () -> output_string channel data);
                  Ok (String.length data)
                with Sys_error message -> Error message
              in
              Effect.Deep.continue k result)
          | Freight_effect.Get_env name ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Effect.Deep.continue k (Sys.getenv_opt name))
          | Freight_effect.Now () ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Effect.Deep.continue k (Unix.gettimeofday ()))
          | Freight_effect.Random_int bound ->
            Some (fun (k : (a, _) Effect.Deep.continuation) ->
              Effect.Deep.continue k (Random.int (max 1 bound)))
          | _ -> None)
    }
