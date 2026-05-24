val show
  :  client:[ `blocking ] Vcaml.Client.t
  -> name:string
  -> filetype:string
  -> lines:string list
  -> unit Async.Deferred.Or_error.t
