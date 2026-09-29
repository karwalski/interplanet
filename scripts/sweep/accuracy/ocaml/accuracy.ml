(* Accuracy harness for ocaml/planet-time (see ../gen-cases-group2.js).
   Run from ocaml/planet-time:
     mkdir -p _build && ocamlopt -I lib lib/constants.ml lib/orbital.ml lib/time_calc.ml \
       lib/interplanet_time.ml ../../scripts/sweep/accuracy/ocaml/accuracy.ml -o _build/accuracy &&
     ./_build/accuracy ../../scripts/sweep/accuracy/instants-group2.txt *)

let bodies = [ "mercury", 0; "venus", 1; "earth", 2; "mars", 3; "jupiter", 4;
               "saturn", 5; "uranus", 6; "neptune", 7; "moon", 8 ]

let b v = if v then 1 else 0

let () =
  let ic = open_in Sys.argv.(1) in
  (try
     while true do
       let line = String.trim (input_line ic) in
       if line <> "" then begin
         let ms = float_of_string line in
         List.iter (fun (name, idx) ->
             let pt = Interplanet_time.get_planet_time ~body:idx ~utc_ms:ms in
             let lt = Orbital.light_travel_time_ms ~body1:idx ~body2:2 ~utc_ms:ms in
             Printf.printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%.6f\n"
               line name pt.hour pt.minute pt.second pt.day_number pt.day_in_year
               pt.year_number pt.period_in_week (b pt.is_work_period) (b pt.is_work_hour) lt)
           bodies;
         let m = Interplanet_time.get_mtc ~utc_ms:ms in
         Printf.printf "%s\tmtc\t%d\t%d\t%d\t%d\n" line m.mtc_sol m.mtc_hour m.mtc_minute m.mtc_second
       end
     done
   with End_of_file -> ());
  close_in ic
