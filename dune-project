(lang dune 3.21)

(name freight)

(generate_opam_files true)

(source
 (github aktersnurra/freight.ml))

(authors "Author Name <author@example.com>")

(maintainers "Maintainer Name <maintainer@example.com>")

(license LICENSE)

(documentation https://url/to/documentation)

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
  ounit2)
 (tags
  (neovim http ocaml)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
