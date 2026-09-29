(* Interop driver for ocaml/ltx (see scripts/interop/run.js).
   (a) v2 uses the typed Interplanet_ltx API; v3 goes through V11 (which
   works on JSON values): the typed wire JSON is parsed, upgraded with
   V11.upgrade_plan_to_v3 and serialised with Security.canonical_json. *)

open Models

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

let write_file path s =
  let oc = open_out_bin path in
  output_string oc s; close_out oc

let () =
  let in_dir = Sys.argv.(1) and out_dir = Sys.argv.(2) in
  let plan =
    Interplanet_ltx.create_plan
      ~title:"Réunion Mars 🚀" ~start:"2026-03-15T14:00:00.000Z" ~quantum:3 ~mode:"LTX-ASYNC"
      ~nodes:[
        { id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0; location = "earth" };
        { id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 840; location = "mars" };
        { id = "N2"; name = "L-1 Gateway"; role = "PARTICIPANT"; delay = 2; location = "moon" } ]
      ~segments:[
        segment "PLAN_CONFIRM" 2;
        segment ~speaker:"N0" ~label:"Ouverture: état de la mission" "TX" 3;
        segment "RX" 3;
        segment ~speaker:"N1" ~label:"Réponse 🔴" "TX" 2;
        segment "BUFFER" 1 ]
      ()
  in
  print_endline "NOTE typed ltx_plan: v2 only; v3 via V11 on the parsed wire JSON";
  let hash = Interplanet_ltx.encode_hash plan in
  let wire = Security.b64u_decode (String.sub hash 3 (String.length hash - 3)) in
  write_file (Filename.concat out_dir "wire-v2.json") wire;
  print_endline ("ID_V2 " ^ Interplanet_ltx.make_plan_id plan);

  let v3 =
    V11.upgrade_plan_to_v3
      ~extras:[ ("delays", Security.JObj [ ("N1|N2", Security.JInt 842) ]) ]
      (V11.parse_json wire)
  in
  write_file (Filename.concat out_dir "wire-v3.json") (Security.canonical_json v3);
  print_endline ("ID_V3 " ^ V11.make_plan_id v3);

  List.iter (fun v ->
    let json = read_file (Filename.concat in_dir ("js-v" ^ v ^ ".json")) in
    print_endline ("JS_V" ^ v ^ " " ^ V11.make_plan_id (V11.parse_json json))
  ) [ "2"; "3"; "P" ]
