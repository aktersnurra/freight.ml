type call =
  | Current_buffer
  | Buffer_lines of Freight_effect.buffer_id
  | Buffer_dir of Freight_effect.buffer_id
  | Cursor
  | Show_scratch of Freight_effect.scratch_view
  | Show_float of Freight_effect.scratch_view
  | Update_scratch of Freight_effect.buffer_id * Freight_effect.scratch_view
  | Set_keymap of Freight_effect.buffer_id * string * string
  | Load_env of { dir : string; active_env : string option }
  | Run_curl of Freight.Executor.invocation
  | Run_curl_verbose of Freight.Executor.invocation
  | Notify of Freight_effect.notify_level * string
  | Fork of string
  | Nvim_call of string * Msgpck.t list
  | File_exists of string
  | File_size of string
  | Write_file of { path : string; data : string }

type config =
  { current_buffer : Freight_effect.buffer_id
  ; buffer_lines : string list
  ; buffer_dir : string option
  ; cursor : Freight_effect.Cursor.t
  ; env : Freight.Env.t
  ; curl_result : (string, string) result
  ; curl_verbose_result : (string, string) result
  ; nvim_eval_result : Msgpck.t
  ; nvim_eval_results : (string * Msgpck.t) list
  ; nvim_eval_sequence : (string * Msgpck.t list) list
  ; fork_mode : [ `Run_immediately | `Capture_only ]
  ; existing_files : string list
  ; file_sizes : (string * int) list
  ; write_file_result : (int, string) result
  }

let default_config =
  { current_buffer = Freight_effect.Buffer_id.of_int 1
  ; buffer_lines = []
  ; buffer_dir = None
  ; cursor = { Freight_effect.Cursor.row = 0; col = 0 }
  ; env = Freight.Env.empty
  ; curl_result = Ok ""
  ; curl_verbose_result = Ok ""
  ; nvim_eval_result = Msgpck.Int (-1)
  ; nvim_eval_results = []
  ; nvim_eval_sequence = []
  ; fork_mode = `Run_immediately
  ; existing_files = []
  ; file_sizes = []
  ; write_file_result = Ok 0
  }

let rec run config f =
  let calls = ref [] in
  let log c = calls := c :: !calls in
  let next_buf = ref 100 in
  let result =
    Effect.Deep.try_with f ()
      { effc =
          (fun (type a) (eff : a Effect.t) ->
            match eff with
            | Freight_effect.Current_buffer ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log Current_buffer;
                Effect.Deep.continue k config.current_buffer)
            | Freight_effect.Buffer_lines buf ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Buffer_lines buf);
                Effect.Deep.continue k config.buffer_lines)
            | Freight_effect.Buffer_dir buf ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Buffer_dir buf);
                Effect.Deep.continue k config.buffer_dir)
            | Freight_effect.Cursor ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log Cursor;
                Effect.Deep.continue k config.cursor)
            | Freight_effect.Show_scratch view ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Show_scratch view);
                let id = !next_buf in
                incr next_buf;
                Effect.Deep.continue k id)
            | Freight_effect.Show_float view ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Show_float view);
                Effect.Deep.continue k ())
            | Freight_effect.Update_scratch (buf, view) ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Update_scratch (buf, view));
                Effect.Deep.continue k ())
            | Freight_effect.Set_keymap (buf, key, command) ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Set_keymap (buf, key, command));
                Effect.Deep.continue k ())
            | Freight_effect.Load_env { dir; active_env } ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Load_env { dir; active_env });
                Effect.Deep.continue k config.env)
            | Freight_effect.Run_curl invocation ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Run_curl invocation);
                Effect.Deep.continue k config.curl_result)
            | Freight_effect.Run_curl_verbose invocation ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Run_curl_verbose invocation);
                Effect.Deep.continue k config.curl_verbose_result)
            | Freight_effect.Notify (level, msg) ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Notify (level, msg));
                Effect.Deep.continue k ())
            | Freight_effect.Fork (label, child) ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Fork label);
                (match config.fork_mode with
                 | `Run_immediately ->
                   let (), child_calls = run config child in
                   calls := List.rev_append child_calls !calls
                 | `Capture_only -> ());
                Effect.Deep.continue k ())
            | Freight_effect.File_exists path ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (File_exists path);
                Effect.Deep.continue k (List.mem path config.existing_files))
            | Freight_effect.File_size path ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (File_size path);
                Effect.Deep.continue k (List.assoc_opt path config.file_sizes))
            | Freight_effect.Write_file { path; data } ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Write_file { path; data });
                let result =
                  match config.write_file_result with
                  | Ok _ -> Ok (String.length data)
                  | Error _ as error -> error
                in
                Effect.Deep.continue k result)
            | Freight_effect.Nvim_call (method_, params) ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Nvim_call (method_, params));
                let sequence_count =
                  List.fold_left
                    (fun count -> function
                      | Nvim_call (m, _) when m = method_ -> count + 1
                      | _ -> count)
                    0 !calls
                in
                let result =
                  match List.assoc_opt method_ config.nvim_eval_sequence with
                  | Some values when List.length values >= sequence_count ->
                    List.nth values (sequence_count - 1)
                  | _ ->
                    (match List.assoc_opt method_ config.nvim_eval_results with
                     | Some value -> value
                     | None -> config.nvim_eval_result)
                in
                Effect.Deep.continue k result)
            | _ -> None)
      }
  in
  (result, List.rev !calls)
