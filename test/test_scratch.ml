open OUnit2

let test_float_width_uses_widest_line _ =
  assert_equal 28
    (Scratch.float_width ~screen_width:80 ~line_widths:[ 11; 28; 16 ])

let test_float_width_reserves_rounded_border_space _ =
  assert_equal 78
    (Scratch.float_width ~screen_width:80 ~line_widths:[ 120 ])

let test_float_width_never_returns_less_than_one _ =
  assert_equal 1
    (Scratch.float_width ~screen_width:1 ~line_widths:[])

let suite =
  "scratch" >::: 
  [ "uses widest line" >:: test_float_width_uses_widest_line
  ; "reserves rounded border space" >:: test_float_width_reserves_rounded_border_space
  ; "never returns less than one" >:: test_float_width_never_returns_less_than_one
  ]

let () = run_test_tt_main suite
