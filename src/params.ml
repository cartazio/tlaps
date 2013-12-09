(*
 * params.ml --- parameters
 *
 * Copyright (C) 2008-2010  INRIA and Microsoft Corporation
 *)

Revision.f "$Rev: 32647 $";;

open Ext
open Printf;;

let self_sum = Digest.file Sys.executable_name

(* must be a function because it must not be computed before all the
   modules are loaded. *)
let rawversion () =
  sprintf "%d.%d.%d (build %s)" Version.major Version.minor Version.micro
          (Revision.get ())
;;

let debug_flags : (string, unit) Hashtbl.t = Hashtbl.create 3
let add_debug_flag flg = Hashtbl.add debug_flags flg ()
let rm_debug_flag flg = Hashtbl.remove debug_flags flg
let debugging flg = Hashtbl.mem debug_flags flg

let nprocs = Sysconf.nprocs ()

let timeout_stretch = ref 1.0;;

let tb_sl = ref 0 (* toolbox start line *)
let tb_el = ref 0 (* toolbox end line *)

let toolbox = ref false     (* Run in toolbox mode. *)
let toolbox_all = ref false (* Consider the whole tla file. *)

let no_fp = ref false
(* Don't use the fingerprints but still save them with the old ones. *)

let nofp_sl = ref 0
let nofp_el = ref 0
(* Don't use the fingerprints for obligations located
   between [nofp_sl] and [nofp_el] *)

let cleanfp = ref false (* Erase the fingerprint file. *)

let safefp = ref false
(* Check pm, zenon and isabelle versions before using fingerprints. *)

let wait = ref 3
(* Wait time before sending a "being proved" message to the toolbox. *)

let noproving = ref false (* Don't send any obligation to the back-ends. *)

let toolbox_killed = ref false (* true if the toolbox has killed the pm *)

let printallobs = ref false
(* print unnormalized and normalized versions of obligations in toolbox mode *)


let library_path =
  let d = Sys.executable_name in
  let d = Filename.dirname (Filename.dirname d) in
  let d = Filename.concat d "lib" in
  let d = Filename.concat d "tlaps" in
  d

type executable =
  | Unchecked of string * string * string (* exec, command, version_command *)
  | User of string                        (* command *)
  | Checked of string * string list       (* command, version *)
  | NotFound
;;

type exec = executable ref;;

let mydir = Filename.dirname Sys.executable_name;;
let auxdir = Filename.concat library_path "bin";;
let extrapath = sprintf ":%s:%s" mydir auxdir;;
let path_prefix = sprintf "PATH=\"${PATH}%s\";" extrapath;;

let get_exec e =
  match !e with
  | Unchecked (exec, cmd, vers) ->
     let check = sprintf "%s type %s >/dev/null" path_prefix exec in
     begin match Sys.command check with
     | 0 ->
        let p = Unix.open_process_in (path_prefix ^ vers) in
        let v = Std.input_list p in
        let c = sprintf "%s %s" path_prefix cmd in
        e := Checked (c, v);
        c
     | _ ->
        let msg1 = sprintf "Executable %S not found" exec in
        let msg2 =
          if Filename.is_relative exec
          then sprintf " in this PATH:\n%s%s\n" (Sys.getenv "PATH") extrapath
          else "."
        in
        let msg = msg1 ^ msg2 in
        eprintf "%s" msg;
        e := NotFound;
        raise Not_found;
     end;
  | User (cmd) ->
     e := Checked (cmd, []);
     cmd
  | Checked (cmd, vers) -> cmd
  | NotFound -> raise Not_found;
;;

let get_version e =
  match !e with
  | Checked (cmd, vers) -> vers
  | _ -> []
;;

let make_exec cmd args version = ref (Unchecked (cmd, args, version));;

let isabelle_success_string = "((TLAPS SUCCESS))"

let isabelle =
  let cmd =
    Printf.sprintf "isabelle-process -r -q -e \"(use_thy \\\"$file\\\"; \
                                                writeln \\\"%s\\\");\" TLA+"
                   isabelle_success_string
  in
  make_exec "isabelle-process" cmd "isabelle version"
;;

let set_fast_isabelle () =
  if Sys.os_type <> "Cygwin" then
    eprintf "Warning: --fast-isabelle is not available on this architecture \
             (ignored)\n%!"
  else begin try
    let echos =
      "echo \"$ISABELLE_HOME\"; echo \"$ML_HOME\"; echo \"$ISABELLE_OUTPUT\""
    in
    let pr_cmd =
      sprintf "%s isabelle env sh -c %s" path_prefix (Filename.quote echos)
    in
    let ic = Unix.open_process_in pr_cmd in
    let isabelle_home = input_line ic in
    let ml_home = input_line ic in
    let isabelle_output = input_line ic in
    close_in ic;
    let poly = Filename.concat ml_home "poly" in
    let cmd =
      Printf.sprintf "export ISABELLE_HOME='%s'; \
                      export ML_HOME='%s'; \
                      (echo 'PolyML.SaveState.loadState \"%s/TLA+\"; \
                             (use_thy \"'\"$file\"'\"; writeln \"%s\");') | \
                      %s"
                     isabelle_home ml_home
                     isabelle_output isabelle_success_string poly
    in
    isabelle := Unchecked (poly, cmd, "isabelle version");
  with _ -> eprintf "Warning: error trying to set up fast-isabelle\n%!";
  end
;;

let zenon =
  make_exec "zenon" "zenon -p0 -x tla -oisar -max-time 1d \"$file\"" "zenon -v"
;;

let cvc3 = make_exec "cvc3" "cvc3 -lang smt2 \"$file\"" "cvc3 -version";;
(* let cvc3 = make_exec "cvc3" "cvc4 --lang=smt2 \"$file\"" "cvc4 --version";; *)
let yices = make_exec "yices" "yices -tc \"$file\"" "yices --version";;
let z3 =
  if Sys.os_type = "Cygwin" then
    make_exec "z3"
              "z3 /smt2 `cygpath -w \"$file\"`"
              "z3 /version"
  else
    make_exec "z3"
              "z3 -smt2 \"$file\""
              "z3 -version"
;;
let verit =
  make_exec "verit"
            "verit --input=smtlib2 --disable-ackermann \
                   --disable-banner --disable-print-success \"$file\""
            "echo unknown"
;;
let spass = make_exec "SPASS" "SPASS -PGiven=0 -PProblem=0 -PStatistic=0 \"$file\"" "echo unknown";;
let eprover = make_exec "eprover" "eprover --tstp-format --silent \"$file\"" "eprover --version";;

let smt =
  try ref (User (Sys.getenv "TLAPM_SMT_SOLVER"))
  with Not_found -> ref !cvc3
;;
    (* "verit --input=smtlib2 --disable-ackermann --disable-banner $file" *)
    (* "z3 /smt2 MODEL=true PULL_NESTED_QUANTIFIERS=true $file" *)
    (* Yices does not handle SMTLIB version 2 yet *)

let set_smt_solver slv = smt := User slv;;

let max_threads = ref nprocs

let rev_search_path = ref [library_path]
let add_search_dir dir =
  let dir =
    if dir.[0] = '+'
    then Filename.concat library_path (String.sub dir 1 (String.length dir - 1))
    else dir
  in
  if List.for_all (fun lp -> lp <> dir) !rev_search_path then
    rev_search_path := library_path :: dir :: List.tl !rev_search_path

let output_dir = ref "."

let default_method =
  ref [
    Method.Zenon Method.default_zenon_timeout;
    Method.Isabelle (Method.default_isabelle_timeout,
                     Method.default_isabelle_tactic);
    Method.Smt3 Method.default_smt2_timeout;
  ]
;;

let mk_meth name timeout =
  match name with
  | "zenon" ->
     let timeout = Option.default Method.default_zenon_timeout timeout in
     Method.Zenon timeout
  | "auto" | "blast" | "force" ->
     let timeout = Option.default Method.default_isabelle_timeout timeout in
     Method.Isabelle (timeout, name)
  | "smt" ->
     let timeout = Option.default Method.default_smt_timeout timeout in
     Method.SmtT timeout
  | "yices" ->
     let timeout = Option.default Method.default_yices_timeout timeout in
     Method.YicesT timeout
  | "z3" ->
     let timeout = Option.default Method.default_z3_timeout timeout in
     Method.Z3T timeout
  | "fail" ->
     Method.Fail
  | "cvc3" ->
     let timeout = Option.default Method.default_cvc3_timeout timeout in
     Method.Cvc3T timeout
  | "smt2" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Smt2lib timeout
  | "smt2z3" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Smt2z3 timeout
  | "smt3" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Smt3 timeout
  | "z33" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Z33 timeout
  | "cvc33" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Cvc33 timeout
  | "yices3" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Yices3 timeout
  | "verit" ->
     let timeout = Option.default Method.default_smt2_timeout timeout in
     Method.Verit timeout
  | "spass" ->
     let timeout = Option.default Method.default_spass_timeout timeout in
     Method.Spass timeout
  | "tptp" ->
     let timeout = Option.default Method.default_tptp_timeout timeout in
     Method.Tptp timeout
  | _ -> failwith (sprintf "unknown method %S" name)
;;

(** Raise Failure in case of syntax error or unknown method. *)
let parse_default_methods s =
  if s = "help" then begin
    printf "configured methods:\n\n" ;
    printf "  zenon  -- Zenon";
    printf "  auto   -- Isabelle with \"auto\" tactic\n";
    printf "  blast  -- Isabelle with \"blast\" tactic\n";
    printf "  force  -- Isabelle with \"force\" tactic\n";
    printf "  smt    -- Default SMT solver (deprecated)\n";
    printf "  yices  -- Yices (deprecated)\n";
    printf "  z3     -- Z3 (deprecated)\n";
    printf "  cvc3   -- CVC3 (deprecated)\n";
    printf "  smt2   -- Default SMT solver with new translation (deprecated)\n";
    printf "  smt2z3 -- Z3 with new translation (deprecated)\n";
    printf "  smt3   -- Default SMT solver with new translation\n";
    printf "  z33    -- Z3\n";
    printf "  cvc33  -- CVC3\n";
    printf "  yices3 -- Yices\n";
    printf "  verit  -- VeriT\n";
    printf "  spass  -- SPASS\n";
    printf "\n" ;
    printf "  fail   -- Dummy method that always fails\n" ;
    exit 0
  end else begin
    let f x =
      if String.contains x ':' then
        try
          Scanf.sscanf x "%[^:]:%f" (fun name time -> mk_meth name (Some time))
        with Scanf.Scan_failure _ ->
          failwith "bad timeout specification: not a number"
      else
        mk_meth x None
    in
    List.map f (Ext.split s ',')
  end
;;

let set_default_method meths =
  default_method := parse_default_methods meths
;;

let verbose = ref false

let ob_flatten = ref true
let () =
  try match Sys.getenv "TLAPM_FLATTEN" with
    | "yes" | "true" -> ob_flatten := true
    | _ -> ob_flatten := false
  with Not_found -> ()

let pr_normal = ref true
let () =
  try match Sys.getenv "TLAPM_NORMALIZE" with
    | "yes" | "true" -> pr_normal := true
    | _ -> pr_normal := false
  with Not_found -> ()

let notl     = ref false
let xtla     = ref false
let use_xtla = ref false
let () =
  try match Sys.getenv "TLAPM_CACHE" with
    | "gen" ->
        xtla := true ;
        use_xtla := false
    | "use" ->
         xtla := true ;
        use_xtla:= true
    | _ ->
        xtla := false ;
        use_xtla := false
  with Not_found -> ()

let keep_going   = ref false
let suppress_all = ref false
let check        = ref false
let summary      = ref false
let stats        = ref false

let solve_cmd cmd file = sprintf "file=%s; %s" file (get_exec cmd);;

let external_tool_config force (name, tool) =
  if force then begin
    try ignore (get_exec tool) with Not_found -> ()
  end;
  match !tool with
  | Checked (cmd, []) ->
      [sprintf "%s == %S" name cmd]
  | Checked (cmd, v::_) ->
      [sprintf "%s == %S" name cmd;
       sprintf "%s version == %S" name v]
  | NotFound ->
      [sprintf "%s : command not found" name]
  | _ -> []
;;

let configuration toolbox force =
  let lines =
    [ "version == \"" ^ rawversion () ^ "\""
    ; "built_with == \"OCaml " ^ Config.ocaml_version ^ "\""
    ; "tlapm_executable == \"" ^ Sys.executable_name ^ "\""
    ; "max_threads == " ^ string_of_int !max_threads
    ; "library_path == \"" ^ String.escaped library_path ^ "\"" ]
    @ begin match !rev_search_path with
      | [] -> ["search_path == << >>"]
      | [p] -> ["search_path == << \"" ^ p ^ "\" >>"]
      | last :: sp -> begin
          let sp = List.rev sp in
          let first_line = "search_path == << \"" ^ List.hd sp ^ "\"" in
          let mid_lines = List.map begin
            fun l -> "                , \"" ^ l ^ "\""
          end (List.tl sp) in
          let last_line = "                , \"" ^ last ^ "\" >>" in
          first_line :: mid_lines @ [last_line]
        end
      end
    @ List.flatten (List.map (external_tool_config force)
                             [("Isabelle", isabelle);
                              ("zenon", zenon);
                              ("CVC3", cvc3);
                              ("Yices", yices);
                              ("Z3", z3);
                              ("VeriT", verit);
                              ("SMT", smt);
                              ("Spass", spass)])
    @ [ "flatten_obligations == " ^ (if !ob_flatten then "TRUE" else "FALSE")
      ; "normalize == " ^ (if !pr_normal then "TRUE" else "FALSE") ]
  in
  let (header, footer) =
    if toolbox then ([], []) else
      let h = "-------------------- tlapm configuration --------------------" in
      ([h], [String.make (String.length h) '='])
  in
  header @ lines @ footer
;;

let printconfig force =
  String.concat "\n" (configuration false force)

let print_config_toolbox force =
  String.concat "\n" (configuration true force)


let zenon_version = ref None

let check_zenon_ver () =
  let zen = get_exec zenon in
  match get_version zenon with
  | [] -> ()
  | ret :: _ ->
     Scanf.sscanf ret
       "zenon version %d.%d.%d [%c%d] %4d-%02d-%02d"
       (fun _ _ _ _ znum year month date ->
          zenon_version := Some (zen, znum, year * 10000 + month * 100 + date))
;;

let get_zenon_verfp () = if !zenon_version = None then check_zenon_ver ();
  "Zenon version ["^(string_of_int (let _,znum,_ = Option.get !zenon_version in znum))^"]"

let isabelle_version = ref None

let check_isabelle_ver () =
  (try ignore (get_exec isabelle) with Not_found -> ());
  match get_version isabelle with
  | [] -> ()
  | ret :: _ ->
     isabelle_version := Some (List.hd (Ext.split ret ':'))

let get_isabelle_version () =
  if !isabelle_version = None then check_isabelle_ver ();
  match !isabelle_version with
  | None -> "(unknown)"
  | Some s -> s
;;

let fpf_out: string option ref = ref None

let fpf_in: string option ref = ref None

let fp_loaded = ref false

let fp_original_number = ref (-1)

let fp_hist_dir = ref ""

let fp_deb = ref false