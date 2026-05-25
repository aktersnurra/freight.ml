open Freight_plugin

type call =
  | Current_buffer
  | Buffer_lines of Freight_plugin.Freight_effect.buffer_id
  | Buffer_dir of Freight_plugin.Freight_effect.buffer_id
  | Cursor
  | Show_scratch of Freight_plugin.Freight_effect.scratch_view
  | Update_scratch of Freight_plugin.Freight_effect.buffer_id * Freight_plugin.Freight_effect.scratch_view
  | Set_keymap of Freight_plugin.Freight_effect.buffer_id * string * string
  | Load_env of { dir : string; active_env : string option }
  | Run_curl of Freight.Executor.invocation
  | Notify of Freight_plugin.Freight_effect.notify_level * string
  | Fork of string
  | Nvim_call of string * Msgpck.t list

type config =
  { current_buffer : Freight_plugin.Freight_effect.buffer_id
  ; buffer_lines : string list
  ; buffer_dir : string option
  ; cursor : Freight_plugin.Freight_effect.Cursor.t
  ; env : Freight.Env.t
  ; curl_result : (string, string) result
  ; nvim_eval_result : Msgpck.t
  ; fork_mode : [ `Run_immediately | `Capture_only ]
  }

let default_config =
  { current_buffer = Freight_plugin.Freight_effect.Buffer_id.of_int 1
  ; buffer_lines = []
  ; buffer_dir = None
  ; cursor = { Freight_plugin.Freight_effect.Cursor.row = 0; col = 0 }
  ; env = Freight.Env.empty
  ; curl_result = Ok ""
  ; nvim_eval_result = Msgpck.Int (-1)
  ; fork_mode = `Run_immediately
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
            | Freight_effect.Nvim_call (method_, params) ->
              Some (fun (k : (a, _) Effect.Deep.continuation) ->
                log (Nvim_call (method_, params));
                Effect.Deep.continue k config.nvim_eval_result)
            | _ -> None)
      }
  in
  (result, List.rev !calls)
