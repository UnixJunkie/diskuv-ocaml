open Jingoo

let usage_msg =
  "dkml_templatizer.exe [-o OUTPUT_FILE] TEMPLATE_FILE\n\n\
   Requirements: DiskuvOCamlHome environment value must be defined.\n"

let path_ref = ref ""

let output_file_ref = ref ""

let anon_fun path = path_ref := path

let speclist =
  [
    ( "-o",
      Arg.Set_string output_file_ref,
      "Save the resulting file to OUTPUT_FILE. Defaults to standard output" );
  ]

let () =
  Arg.parse speclist anon_fun usage_msg;
  if !path_ref = "" then (
    prerr_endline usage_msg;
    prerr_endline "FATAL: Missing TEMPLATE_FILE";
    exit 1);
  let dkml_home = Sys.getenv "DiskuvOCamlHome" in
  prerr_endline ("dkml_home = " ^ dkml_home);
  prerr_endline ("PATH = " ^ (Sys.getenv "PATH"));
  let dkml_home_windows =
    Feather.(process "cygpath" [ "-aw"; dkml_home ] |> collect stdout)
  in
  let dkml_home_mixed =
    Feather.(process "cygpath" [ "-am"; dkml_home ] |> collect stdout)
  in
  let dkml_home_unix =
    Feather.(process "cygpath" [ "-au"; dkml_home ] |> collect stdout)
  in
  let models =
    [
      ("DiskuvOCamlHome_Windows", Jg_types.Tstr dkml_home_windows);
      ("DiskuvOCamlHome_Unix", Jg_types.Tstr dkml_home_unix);
      ("DiskuvOCamlHome_Mixed", Jg_types.Tstr dkml_home_mixed);
    ]
  in
  let result = Jg_template.from_file !path_ref ~models in
  if !output_file_ref = "" then print_endline result
  else
    let oc = open_out !output_file_ref in
    output_string oc result;
    close_out oc
