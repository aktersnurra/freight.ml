let s:plugin_root = expand('<sfile>:p:h:h')
let s:job_id = 0
let s:ready = 0

function! s:resolve_executable() abort
  if exists('g:freight_executable') && !empty(g:freight_executable)
    return g:freight_executable
  endif
  return s:plugin_root . '/_build/default/bin/main.exe'
endfunction

function! freight#start() abort
  if s:job_id > 0
    echo 'freight: already running (channel ' . s:job_id . ')'
    return
  endif
  let l:exe = s:resolve_executable()
  if !filereadable(l:exe)
    echohl ErrorMsg
    echom 'freight: executable not found at ' . l:exe . '. Run `dune build` in the plugin repo or set g:freight_executable.'
    echohl None
    return
  endif
  let s:job_id = jobstart([l:exe], {'rpc': v:true})
  if s:job_id <= 0
    echohl ErrorMsg
    echom 'freight: jobstart failed (' . s:job_id . ')'
    echohl None
    let s:job_id = 0
  endif
endfunction

function! freight#ensure_started() abort
  if s:job_id <= 0
    call freight#start()
  endif
endfunction

function! freight#on_startup(channel) abort
  let s:ready = 1
endfunction

function! freight#channel() abort
  return s:job_id
endfunction

function! freight#ready() abort
  return s:ready
endfunction
