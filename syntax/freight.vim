" syntax/freight.vim
if exists("b:current_syntax")
  finish
endif

" Box drawing borders  ╭ ╮ ╰ ╯ │ ─
syntax match FreightBorder /[╭╮╰╯│─]/
" Section title inside top border: ╭─ Title ──╮
syntax match FreightTitle /╭─ [^─]*/ contains=FreightBorder
" Key in a kv row: up to 14 chars followed by two spaces
syntax match FreightKey /^\(│  \)\zs\S\+\ze\s\{2,}/
" HTTP status codes
syntax match FreightStatus /HTTP \d\{3\}/
" HTTP methods
syntax keyword FreightMethod GET POST PUT PATCH DELETE HEAD OPTIONS
" Template vars
syntax match FreightVar /{{[^}]*}}/
" Parenthesised annotations like (none), (unnamed)
syntax match FreightMuted /([^)]*)/
" Numbers (ms timing, port numbers)
syntax match FreightNumber /\d\+ ms/

highlight default link FreightBorder Comment
highlight default link FreightTitle  Title
highlight default link FreightKey    Keyword
highlight default link FreightStatus Constant
highlight default link FreightMethod Statement
highlight default link FreightVar    Special
highlight default link FreightMuted  Comment
highlight default link FreightNumber Number

let b:current_syntax = "freight"
