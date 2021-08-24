(* See https://github.com/ocaml/dune/blob/05b1a9a5cb4c10d3b9459b8f2222bebafc6a84ed/src/dune_file_watcher/dune_file_watcher.ml#L259-L286
   for possibly out-of-date command line options Dune uses in `dune --watch`.
   We'll delegate to https://github.com/thekid/inotify-win.
 *)
let usage_msg =
  "fswatch.exe [-r|--recursive] [--event TYPE] [-i|--include REGEX] [-e|--exclude \
   REGEX] path\n\n\
   Requirements: Either DiskuvOCamlHome environment value must be defined or `inotifywait` must be in the PATH.\n"

let recursive_ref = ref false

let events_ref = ref []

let includes_ref = ref []

(* dune --watch has a bug where it excludes only UNIX paths like /_build. That causes Z:\source\diskuv-ocaml-starter\_build for example
   to be missed, which renders dune --watch useless on Windows (TODO: we haven't filed an issue yet).

   For now, we add in the same directories that Dune 2.9.0 does (just Windows-ized), and we also add in a few paths
   that are specific to Diskuv OCaml.
*)
let exclude_auto_added = [
  (* add in the same directories that Dune 2.9.0 does (just Windows-ized) *)
  {|\\#[^#]*#$|};
  {|\\\..+|};
  {|\\_esy|};
  {|\\_opam|};
  {|\\_build|};

  (* paths specific to Diskuv OCaml distribution, or paths we simply want to add *)
  {|\\\.git|};
  {|\\_tmp|}
]
let excludes_ref = ref []

let paths_ref = ref []

let include_fun incl = includes_ref := incl :: !includes_ref

let exclude_fun excl = excludes_ref := excl :: !excludes_ref

let event_fun event = events_ref := event :: !events_ref

let anon_fun path = paths_ref := path :: !paths_ref

let speclist =
  [
    ("-r", Arg.Set recursive_ref, "Recurse subdirectories.");
    ("--recursive", Arg.Set recursive_ref, "Recurse subdirectories.");
    ("--event", Arg.String event_fun, "Filter the event by the specified type.");
    ("-i", Arg.String include_fun, "Include paths_ref matching REGEX.");
    ("--include", Arg.String include_fun, "Include paths_ref matching REGEX.");
    ("-e", Arg.String exclude_fun, "Exclude paths_ref matching REGEX.");
    ("--exclude", Arg.String exclude_fun, "Exclude paths_ref matching REGEX.");
  ]

let list_pp fmt v = Format.fprintf fmt "@[[%s]@]" (String.concat "; " v)

let () =
  Arg.parse speclist anon_fun usage_msg;

  (* Try to find inotifywait. If it is not in $DiskuvOCamlHome then the caller must place it on
     the PATH. *)
  let inotifywait_call, inotifywait_loc =
    match Sys.getenv_opt "DiskuvOCamlHome" with
    | Some dkmlhome ->
        let filename =
          Filename.concat
            (Filename.concat (Filename.concat dkmlhome "tools") "inotify-win")
            "inotifywait.exe"
        in
        Unix.execv filename, filename
    | None ->
      (* search in PATH with execvp *)
      Unix.execvp "inotifywait", "inotifywait"
  in

  Format.fprintf Format.err_formatter
    "@\n@[fswatch args = (@]@[@[recursive=%b;@]@ @[event=%a;@]@ @[include=%a;@]@ \
     @[exclude=%a;@]@ @[exclude_auto_added=%a;@]@ @[paths=%a@])@]@\n"
    !recursive_ref list_pp !events_ref list_pp !includes_ref list_pp
    !excludes_ref list_pp exclude_auto_added list_pp !paths_ref;

  let event_csv =
    List.filter_map
      (function
        | "Created" -> Some "create"
        | "Updated" | "OwnerModified" | "AttributeModified" -> Some "modify"
        | "Removed" -> Some "delete"
        | "Renamed" | "MovedFrom" | "MovedTo" -> Some "move"
        | _ -> None)
      !events_ref
    |> String.concat ","
  in
  (* 1. We can convert all fswatch arguments to inotifywait arguments except '--include' which we ignore.
     We can put in a regex filter on standard output if the lack of `--include` becomes a problem
     for dune --wait.

     2. We use --excludei (case-insensitive exclusions) since Windows is case-insensitive.

     ---------------------------------------------------------------------------------------------

     fswatch 1.11.2

     Usage:
     fswatch [OPTION] ... path ...

     Options:
     -0, --print0          Use the ASCII NUL character (0) as line separator.
     -1, --one-event       Exit fswatch after the first set of events is received.
         --allow-overflow  Allow a monitor to overflow and report it as a change event.
         --batch-marker    Print a marker at the end of every batch.
     -a, --access          Watch file accesses.
     -d, --directories     Watch directories only.
     -e, --exclude=REGEX   Exclude paths matching REGEX.
     -E, --extended        Use extended regular expressions.
         --filter-from=FILE
                           Load filters from file.
         --format=FORMAT   Use the specified record format.
     -f, --format-time     Print the event time using the specified format.
         --fire-idle-event Fire idle events.
     -h, --help            Show this message.
     -i, --include=REGEX   Include paths matching REGEX.
     -I, --insensitive     Use case insensitive regular expressions.
     -l, --latency=DOUBLE  Set the latency.
     -L, --follow-links    Follow symbolic links.
     -M, --list-monitors   List the available monitors.
     -m, --monitor=NAME    Use the specified monitor.
         --monitor-property name=value
                           Define the specified property.
     -n, --numeric         Print a numeric event mask.
     -o, --one-per-batch   Print a single message with the number of change events.
     -r, --recursive       Recurse subdirectories.
     -t, --timestamp       Print the event timestamp.
     -u, --utc-time        Print the event time as UTC time.
     -x, --event-flags     Print the event flags.
         --event=TYPE      Filter the event by the specified type.
         --event-flag-separator=STRING
                           Print event flags using the specified separator.
     -v, --verbose         Print verbose output.
         --version         Print the version of fswatch and exit.

     ---------------------------------------------------------------------------------------------

     Usage: inotifywait [options] path [...]

     Options:

     -r/--recursive:  Recursively watch all files and subdirectories inside path
     -m/--monitor:    Keep running until killed (e.g. via Ctrl+C)
     -q/--quiet:      Do not output information about actions
     -e/--event list: Which events (create, modify, delete, move) to watch, comma-separated. Default: all
     --format format: Format string for output.
     --exclude:       Do not process any events whose filename matches the specified regex
     --excludei:      Ditto, case-insensitive

     Formats:
     %e             : Event name
     %f             : File name
     %w             : Path name
     %T             : Current date and time
  *)
  let args =
    [ inotifywait_loc; "--monitor"; "--format"; {|%w\%f|} ]
    @ (if !recursive_ref then [ "--recursive" ] else [])
    @ (if event_csv = "" then [] else [ "--event"; event_csv ])
    (* can only specify --excludei once so we use an regexp OR expression *)
    @ [ "--excludei"; String.concat "|" (!excludes_ref @ exclude_auto_added) ]
    @ !paths_ref
  in

  Format.fprintf Format.err_formatter "@[inotifywait loc = @[%s@]@]@\n" inotifywait_loc;
  Format.fprintf Format.err_formatter "@[inotifywait args = @[%a@]@]@\n" list_pp
    (List.tl args);
  Format.pp_print_flush Format.err_formatter ();
  inotifywait_call (Array.of_list args)
