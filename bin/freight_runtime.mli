val run :
  proc_mgr:_ Eio.Process.mgr ->
  sw:Eio.Switch.t ->
  rpc:Nvim_rpc.t ->
  (unit -> 'a) ->
  'a
