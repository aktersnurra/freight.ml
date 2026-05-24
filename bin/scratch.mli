val show
  :  rpc:Rpc.t
  -> name:string
  -> filetype:string
  -> lines:string list
  -> unit Async.Deferred.t
