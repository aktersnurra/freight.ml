if exists('g:loaded_freight')
  finish
endif
let g:loaded_freight = 1

command! FreightStart call freight#start()

augroup freight_autostart
  autocmd!
  autocmd BufRead,BufNewFile *.http,*.rest call freight#ensure_started()
augroup END
