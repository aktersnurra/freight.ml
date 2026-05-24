(lang dune 3.21)

(name freight)

(generate_opam_files true)

(source
 (github aktersnurra/freight.ml))

(authors "aktersnurra")

(maintainers "aktersnurra")

(license LICENSE)

(documentation https://github.com/aktersnurra/freight.ml)

(package
 (name freight)
 (synopsis "Neovim HTTP client plugin core library")
 (description "Core OCaml library for parsing, executing, and rendering HTTP requests for freight.ml")
 (depends
  ocaml
  dune
  angstrom
  yojson
  re
  vcaml
  async
  core
  (ounit2 :with-test))
 (tags
  (neovim http ocaml)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
