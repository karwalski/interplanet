(* security.ml -- Epic 29 security cascade for InterplanetLtx (OCaml)
   Stories 29.1, 29.4, 29.5
   Pure-OCaml SHA-256; Ed25519 stubs via Bytes/Digest. *)

(* ---- base64url (shared with interplanet_ltx.ml) ---- *)

let b64u_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

let b64u_encode (data : string) : string =
  let len = String.length data in
  let buf = Buffer.create ((len + 2) / 3 * 4) in
  let i   = ref 0 in
  while !i < len do
    let b0 = Char.code data.[!i] in
    let b1 = if !i + 1 < len then Char.code data.[!i + 1] else 0 in
    let b2 = if !i + 2 < len then Char.code data.[!i + 2] else 0 in
    let n  = (b0 lsl 16) lor (b1 lsl 8) lor b2 in
    Buffer.add_char buf b64u_chars.[n lsr 18 land 63];
    Buffer.add_char buf b64u_chars.[(n lsr 12) land 63];
    Buffer.add_char buf b64u_chars.[(n lsr 6) land 63];
    Buffer.add_char buf b64u_chars.[n land 63];
    i := !i + 3
  done;
  let s = Buffer.contents buf in
  let trimmed = match len mod 3 with
    | 1 -> String.sub s 0 (String.length s - 2)
    | 2 -> String.sub s 0 (String.length s - 1)
    | _ -> s
  in trimmed

let b64u_decode_char c = match c with
  | 'A'..'Z' -> Char.code c - 65
  | 'a'..'z' -> Char.code c - 97 + 26
  | '0'..'9' -> Char.code c - 48 + 52
  | '-' -> 62
  | '_' -> 63
  | _   -> 0

let b64u_decode (s : string) : string =
  let len = String.length s in
  let pad = (4 - (len mod 4)) mod 4 in
  let padded = s ^ String.make pad '=' in
  let plen = String.length padded in
  let buf = Buffer.create (plen * 3 / 4 + 1) in
  let i = ref 0 in
  while !i + 3 < plen + 1 do
    let c0 = b64u_decode_char padded.[!i] in
    let c1 = b64u_decode_char padded.[!i + 1] in
    let c2 = b64u_decode_char padded.[!i + 2] in
    let c3 = b64u_decode_char padded.[!i + 3] in
    let n  = (c0 lsl 18) lor (c1 lsl 12) lor (c2 lsl 6) lor c3 in
    Buffer.add_char buf (Char.chr ((n lsr 16) land 255));
    if padded.[!i + 2] <> '=' then
      Buffer.add_char buf (Char.chr ((n lsr 8) land 255));
    if padded.[!i + 3] <> '=' then
      Buffer.add_char buf (Char.chr (n land 255));
    i := !i + 4
  done;
  Buffer.contents buf

(* ---- SHA-256 (pure OCaml) ---- *)

let sha256_k = [|
  0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l;
  0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
  0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l;
  0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
  0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl;
  0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
  0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l;
  0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
  0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l;
  0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
  0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l;
  0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
  0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l;
  0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
  0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
  0x90beffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l;
|]

let rotr32 x n = Int32.(logor (shift_right_logical x n) (shift_left x (32 - n)))
let land32 = Int32.logand
let lor32  = Int32.logor
let lxor32 = Int32.logxor
let add32  = Int32.add
let srl32 x n = Int32.shift_right_logical x n

let sha256 (msg : string) : string =
  let h = [|
    0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
    0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l;
  |] in
  let mlen = String.length msg in
  let bitlen = mlen * 8 in
  (* pad *)
  let pad1 = msg ^ "\x80" in
  let extra = (56 - (String.length pad1 mod 64) + 64) mod 64 in
  let pad2 = pad1 ^ String.make extra '\x00' in
  (* append 64-bit big-endian bit length *)
  let blen_bytes = Bytes.make 8 '\x00' in
  Bytes.set blen_bytes 4 (Char.chr ((bitlen lsr 24) land 255));
  Bytes.set blen_bytes 5 (Char.chr ((bitlen lsr 16) land 255));
  Bytes.set blen_bytes 6 (Char.chr ((bitlen lsr 8) land 255));
  Bytes.set blen_bytes 7 (Char.chr (bitlen land 255));
  let padded = pad2 ^ Bytes.to_string blen_bytes in
  let blocks = String.length padded / 64 in
  for blk = 0 to blocks - 1 do
    let base = blk * 64 in
    let w = Array.make 64 0l in
    for i = 0 to 15 do
      let o = base + i * 4 in
      w.(i) <- Int32.of_int (
        ((Char.code padded.[o]) lsl 24) lor
        ((Char.code padded.[o+1]) lsl 16) lor
        ((Char.code padded.[o+2]) lsl 8) lor
        (Char.code padded.[o+3]))
    done;
    for i = 16 to 63 do
      let s0 = lxor32 (rotr32 w.(i-15) 7) (lxor32 (rotr32 w.(i-15) 18) (srl32 w.(i-15) 3)) in
      let s1 = lxor32 (rotr32 w.(i-2) 17) (lxor32 (rotr32 w.(i-2) 19) (srl32 w.(i-2) 10)) in
      w.(i) <- add32 (add32 (add32 w.(i-16) s0) w.(i-7)) s1
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2) and d = ref h.(3) in
    let e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and hh = ref h.(7) in
    for i = 0 to 63 do
      let s1  = lxor32 (rotr32 !e 6) (lxor32 (rotr32 !e 11) (rotr32 !e 25)) in
      let ch  = lxor32 (land32 !e !f) (land32 (Int32.lognot !e) !g) in
      let tmp1 = add32 (add32 (add32 (add32 !hh s1) ch) sha256_k.(i)) w.(i) in
      let s0  = lxor32 (rotr32 !a 2) (lxor32 (rotr32 !a 13) (rotr32 !a 22)) in
      let maj = lxor32 (land32 !a !b) (lxor32 (land32 !a !c) (land32 !b !c)) in
      let tmp2 = add32 s0 maj in
      hh := !g; g := !f; f := !e; e := add32 !d tmp1;
      d := !c; c := !b; b := !a; a := add32 tmp1 tmp2
    done;
    h.(0) <- add32 h.(0) !a; h.(1) <- add32 h.(1) !b;
    h.(2) <- add32 h.(2) !c; h.(3) <- add32 h.(3) !d;
    h.(4) <- add32 h.(4) !e; h.(5) <- add32 h.(5) !f;
    h.(6) <- add32 h.(6) !g; h.(7) <- add32 h.(7) !hh
  done;
  let out = Bytes.make 32 '\x00' in
  for i = 0 to 7 do
    let v = Int32.to_int (land32 h.(i) 0xFFFFFFl) in
    let hi = Int32.to_int (land32 (srl32 h.(i) 16) 0xFFl) in
    let mi = Int32.to_int (land32 (srl32 h.(i) 8) 0xFFl) in
    let lo = v land 255 in
    let byte3 = Int32.to_int (land32 (srl32 h.(i) 24) 0xFFl) in
    Bytes.set out (i*4)   (Char.chr byte3);
    Bytes.set out (i*4+1) (Char.chr hi);
    Bytes.set out (i*4+2) (Char.chr mi);
    Bytes.set out (i*4+3) (Char.chr lo)
  done;
  Bytes.to_string out

(* ---- canonical JSON ---- *)

type json_val =
  | JNull
  | JBool of bool
  | JInt  of int
  | JFloat of float
  | JStr  of string
  | JArr  of json_val list
  | JObj  of (string * json_val) list

let rec canonical_json (v : json_val) : string =
  match v with
  | JNull      -> "null"
  | JBool b    -> if b then "true" else "false"
  | JInt  n    -> string_of_int n
  | JFloat f   -> if Float.is_integer f then Printf.sprintf "%d" (int_of_float f)
                  else string_of_float f
  | JStr  s    -> json_str s
  | JArr  lst  -> "[" ^ String.concat "," (List.map canonical_json lst) ^ "]"
  | JObj  kvs  ->
      let sorted = List.sort (fun (a,_) (b,_) -> String.compare a b) kvs in
      "{" ^ String.concat ","
              (List.map (fun (k,v2) -> json_str k ^ ":" ^ canonical_json v2) sorted)
           ^ "}"

and json_str s =
  let buf = Buffer.create (String.length s + 4) in
  Buffer.add_char buf '"';
  String.iter (fun c -> match c with
    | '"'  -> Buffer.add_string buf "\\\""
    | '\\'  -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c    -> Buffer.add_char buf c) s;
  Buffer.add_char buf '"';
  Buffer.contents buf

(* ---- NIK type ---- *)

type nik = {
  key_type        : string;
  node_id         : string;
  kid             : string;
  issued_at       : string;
  expires_at      : string;
  node_label      : string;
  public_key_b64  : string;
  private_key_b64 : string;
  pub_raw         : string;
  priv_raw        : string;
}

(* ---- ISO-8601 UTC ---- *)

(* Convert Unix epoch seconds to Gregorian calendar (UTC) *)
(* Using Sys.time() which doesn't require the Unix package *)
let is_leap y = (y mod 4 = 0 && y mod 100 <> 0) || (y mod 400 = 0)
let days_in_month m y =
  match m with
  | 1|3|5|7|8|10|12 -> 31
  | 4|6|9|11 -> 30
  | 2 -> if is_leap y then 29 else 28
  | _ -> 30

let epoch_to_ymd_hms secs =
  let secs  = Int64.of_float secs in
  let day_s = 86400L in
  let days  = Int64.div secs day_s in
  let rem   = Int64.to_int (Int64.rem secs day_s) in
  let hh = rem / 3600 in
  let mm = (rem mod 3600) / 60 in
  let ss = rem mod 60 in
  (* count days from 1970-01-01 *)
  let y = ref 1970 and d = ref (Int64.to_int days) in
  let keep = ref true in
  while !keep do
    let yd = if is_leap !y then 366 else 365 in
    if !d >= yd then begin d := !d - yd; incr y end
    else keep := false
  done;
  let m = ref 1 in
  keep := true;
  while !keep do
    let md = days_in_month !m !y in
    if !d >= md then begin d := !d - md; incr m end
    else keep := false
  done;
  (!y, !m, !d + 1, hh, mm, ss)

let iso_now_offset_days days =
  (* Get epoch seconds via 'date +%s', then compute ISO string in OCaml *)
  let tmp = Filename.temp_file "ltx_epoch" ".txt" in
  ignore (Sys.command (Printf.sprintf "date +%%s > %s 2>/dev/null" tmp));
  let ic = open_in tmp in
  let epoch_str = try input_line ic with End_of_file -> "0" in
  close_in ic;
  ignore (Sys.command (Printf.sprintf "rm -f %s" tmp));
  let epoch = (try float_of_string (String.trim epoch_str) with Failure _ -> 0.0) in
  let t = epoch +. (float_of_int days *. 86400.0) in
  let (y,mo,d,h,mi,s) = epoch_to_ymd_hms t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" y mo d h mi s
let iso_now () = iso_now_offset_days 0

(* ---- random bytes ---- *)

let random_bytes n =
  let ic = open_in_bin "/dev/urandom" in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(* ---- SPKI / PKCS8 DER headers ---- *)

let spki_hdr = String.init 12 (fun i -> Char.chr [|
  0x30;0x2a;0x30;0x05;0x06;0x03;0x2b;0x65;0x70;0x03;0x21;0x00|].(i))

let pkcs8_hdr = String.init 16 (fun i -> Char.chr [|
  0x30;0x2e;0x02;0x01;0x00;0x30;0x05;0x06;0x03;0x2b;0x65;0x70;
  0x04;0x22;0x04;0x20|].(i))

(* ---- generate_nik ---- *)

let generate_nik ?(valid_days=365) ?(node_label="") () =
  let priv_raw = random_bytes 32 in
  let pub_raw  = random_bytes 32 in
  let h        = sha256 pub_raw in
  let node_id  = b64u_encode (String.sub h 0 16) in
  let kid      = node_id in
  let pub_der  = spki_hdr  ^ pub_raw in
  let priv_der = pkcs8_hdr ^ priv_raw in
  { key_type        = "ltx-nik-v1";
    node_id;
    kid;
    issued_at       = iso_now ();
    expires_at      = iso_now_offset_days valid_days;
    node_label;
    public_key_b64  = b64u_encode pub_der;
    private_key_b64 = b64u_encode priv_der;
    pub_raw;
    priv_raw;
  }

(* ---- is_nik_expired ---- *)

let is_nik_expired (n : nik) =
  let now = iso_now () in
  n.expires_at <= now

(* ---- COSE_Sign1 wire types ---- *)

type cose_sign1 = {
  protected_hdr : string;
  kid           : string;
  payload       : string;
  signature     : string;
}

type signed_plan = {
  plan      : json_val;
  cose_sign1: cose_sign1;
}

(* ---- sign_plan ---- *)

let sign_plan (plan : json_val) (private_key_b64 : string) ?(kid="") () : signed_plan =
  let protected_b64 = b64u_encode (canonical_json (JObj [("alg", JInt (-19))])) in
  let payload_b64   = b64u_encode (canonical_json plan) in
  let sig_struct = canonical_json (JArr [
    JStr "Signature1"; JStr protected_b64; JStr ""; JStr payload_b64]) in
  let _priv_raw = b64u_decode private_key_b64 in
  (* stub: SHA-256 of sig_struct as signature bytes *)
  let sig_bytes = sha256 sig_struct in
  { plan;
    cose_sign1 = {
      protected_hdr = protected_b64;
      kid;
      payload       = payload_b64;
      signature     = b64u_encode sig_bytes;
    }}

(* ---- verify_plan ---- *)

let verify_plan (sp : signed_plan) (key_cache : (string * nik) list)
    : (bool * string) =
  let cs  = sp.cose_sign1 in
  let kid = cs.kid in
  match List.assoc_opt kid key_cache with
  | None -> (false, "key_not_in_cache")
  | Some nik ->
    if is_nik_expired nik then (false, "key_expired")
    else
      let expected_payload = b64u_encode (canonical_json sp.plan) in
      if cs.payload <> expected_payload then (false, "payload_mismatch")
      else
        let sig_struct = canonical_json (JArr [
          JStr "Signature1"; JStr cs.protected_hdr; JStr ""; JStr cs.payload]) in
        let expected_sig = b64u_encode (sha256 sig_struct) in
        if cs.signature <> expected_sig then (false, "signature_mismatch")
        else (true, "ok")

(* ---- SequenceTracker ---- *)

type sequence_tracker = {
  plan_id : string;
  seqs    : (string, int) Hashtbl.t;
}

let new_sequence_tracker plan_id =
  { plan_id; seqs = Hashtbl.create 16 }

let add_seq (t : sequence_tracker) (peer_id : string) (seq : int)
    : (bool * string) =
  match Hashtbl.find_opt t.seqs peer_id with
  | None ->
      Hashtbl.add t.seqs peer_id seq;
      (true, "ok")
  | Some last ->
      if seq <= last then (false, "replay")
      else if seq > last + 1 then begin
        Hashtbl.replace t.seqs peer_id seq;
        (true, "gap")
      end else begin
        Hashtbl.replace t.seqs peer_id seq;
        (true, "ok")
      end

let check_seq (t : sequence_tracker) (peer_id : string) (seq : int)
    : (bool * string) =
  match Hashtbl.find_opt t.seqs peer_id with
  | None    -> (true, "ok")
  | Some last ->
      if seq <= last then (false, "replay")
      else if seq > last + 1 then (true, "gap")
      else (true, "ok")
