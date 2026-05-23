open OUnit2

let test_method_to_string _ =
  assert_equal ~printer:Fun.id "GET" (Freight.Ast.method_to_string Freight.Ast.Get)

let suite =
  "freight" >::: [ "method_to_string" >:: test_method_to_string ]

let () = run_test_tt_main suite
