open OUnit2

let test_method_to_string _ =
  assert_equal ~printer:Fun.id "GET" (Freight.Ast.method_to_string Freight.Ast.Get)

let test_method_of_string _ =
  assert_equal Freight.Ast.Post (Freight.Ast.method_of_string "POST");
  assert_equal (Freight.Ast.Custom "PROPFIND")
    (Freight.Ast.method_of_string "PROPFIND")

let suite =
  "freight"
  >::: [
         "method_to_string" >:: test_method_to_string;
         "method_of_string" >:: test_method_of_string;
       ]

let () = run_test_tt_main suite
