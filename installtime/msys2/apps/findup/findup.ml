(* Command line options *)

let usage_msg = "dkml-findup.exe [-f FROM_PATH] FILE_BASENAME_TO_FIND"

let from_path = ref (Sys.getcwd ())

let file_basename_to_find = ref ""

let anon_fun path = 
  file_basename_to_find := path

let speclist =
  [
    ("-f", Arg.Set_string from_path, "Start the search from `FROM_PATH`. Defaults to the current directory")
  ]

(* Parse arguments *)
let () =
  Arg.parse speclist anon_fun usage_msg;
  if !file_basename_to_find = "" then (
    prerr_endline usage_msg;
    prerr_endline "Missing FILE_BASENAME_TO_FIND";
    exit 1
  )

(* Main recursive find helper *)
let rec helper path tries_remaining =
  if tries_remaining <= 0 then failwith ("Could not find the file named: " ^ !file_basename_to_find)
  else if Sys.file_exists (Filename.concat path !file_basename_to_find) then path
  else helper (Filename.dirname path) (tries_remaining - 1)

(* Kickoff helper *)
let () =
  print_endline (helper !from_path 20)
