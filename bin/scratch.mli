val show
  :  rpc:Nvim_rpc.t
  -> name:string
  -> filetype:string
  -> lines:string list
  -> unit Async.Deferred.t
