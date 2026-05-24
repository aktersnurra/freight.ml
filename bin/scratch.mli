val show
  :  rpc:Nvim_rpc.t
  -> name:string
  -> filetype:string
  -> lines:string list
  -> unit Async.Deferred.t

val update
  :  rpc:Nvim_rpc.t
  -> Msgpck.t
  -> filetype:string
  -> lines:string list
  -> unit Async.Deferred.t

val show_loading
  :  rpc:Nvim_rpc.t
  -> name:string
  -> Msgpck.t Async.Deferred.t
