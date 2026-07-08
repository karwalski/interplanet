(* ed25519.ml -- Pure-OCaml Ed25519 (RFC 8032) + SHA-512 for the LTX v1.1
   cascade (Epic 72, Story 72.5).

   Port of the public-domain TweetNaCl construction (the same arithmetic used
   by tweetnacl-js, whose 16-bit limbs are safe in 53-bit JS floats and a
   fortiori in OCaml's 63-bit native ints). Replaces the Epic-29 signature
   stubs so the shared conformance vectors verify for real.

   All byte buffers are OCaml strings (1 char = 1 byte). *)

(* ---- SHA-512 ---- *)

let sha512_k = [|
  0x428a2f98d728ae22L; 0x7137449123ef65cdL; 0xb5c0fbcfec4d3b2fL; 0xe9b5dba58189dbbcL;
  0x3956c25bf348b538L; 0x59f111f1b605d019L; 0x923f82a4af194f9bL; 0xab1c5ed5da6d8118L;
  0xd807aa98a3030242L; 0x12835b0145706fbeL; 0x243185be4ee4b28cL; 0x550c7dc3d5ffb4e2L;
  0x72be5d74f27b896fL; 0x80deb1fe3b1696b1L; 0x9bdc06a725c71235L; 0xc19bf174cf692694L;
  0xe49b69c19ef14ad2L; 0xefbe4786384f25e3L; 0x0fc19dc68b8cd5b5L; 0x240ca1cc77ac9c65L;
  0x2de92c6f592b0275L; 0x4a7484aa6ea6e483L; 0x5cb0a9dcbd41fbd4L; 0x76f988da831153b5L;
  0x983e5152ee66dfabL; 0xa831c66d2db43210L; 0xb00327c898fb213fL; 0xbf597fc7beef0ee4L;
  0xc6e00bf33da88fc2L; 0xd5a79147930aa725L; 0x06ca6351e003826fL; 0x142929670a0e6e70L;
  0x27b70a8546d22ffcL; 0x2e1b21385c26c926L; 0x4d2c6dfc5ac42aedL; 0x53380d139d95b3dfL;
  0x650a73548baf63deL; 0x766a0abb3c77b2a8L; 0x81c2c92e47edaee6L; 0x92722c851482353bL;
  0xa2bfe8a14cf10364L; 0xa81a664bbc423001L; 0xc24b8b70d0f89791L; 0xc76c51a30654be30L;
  0xd192e819d6ef5218L; 0xd69906245565a910L; 0xf40e35855771202aL; 0x106aa07032bbd1b8L;
  0x19a4c116b8d2d0c8L; 0x1e376c085141ab53L; 0x2748774cdf8eeb99L; 0x34b0bcb5e19b48a8L;
  0x391c0cb3c5c95a63L; 0x4ed8aa4ae3418acbL; 0x5b9cca4f7763e373L; 0x682e6ff3d6b2b8a3L;
  0x748f82ee5defb2fcL; 0x78a5636f43172f60L; 0x84c87814a1f0ab72L; 0x8cc702081a6439ecL;
  0x90befffa23631e28L; 0xa4506cebde82bde9L; 0xbef9a3f7b2c67915L; 0xc67178f2e372532bL;
  0xca273eceea26619cL; 0xd186b8c721c0c207L; 0xeada7dd6cde0eb1eL; 0xf57d4f7fee6ed178L;
  0x06f067aa72176fbaL; 0x0a637dc5a2c898a6L; 0x113f9804bef90daeL; 0x1b710b35131c471bL;
  0x28db77f523047d84L; 0x32caab7b40c72493L; 0x3c9ebe0a15c9bebcL; 0x431d67c49c100d4cL;
  0x4cc5d4becb3e42b6L; 0x597f299cfc657e2aL; 0x5fcb6fab3ad6faecL; 0x6c44198c4a475817L;
|]

let rotr64 x n = Int64.(logor (shift_right_logical x n) (shift_left x (64 - n)))
let srl64 = Int64.shift_right_logical
let ( +% ) = Int64.add
let lxor64 = Int64.logxor
let land64 = Int64.logand

let sha512 (msg : string) : string =
  let h = [|
    0x6a09e667f3bcc908L; 0xbb67ae8584caa73bL; 0x3c6ef372fe94f82bL; 0xa54ff53a5f1d36f1L;
    0x510e527fade682d1L; 0x9b05688c2b3e6c1fL; 0x1f83d9abfb41bd6bL; 0x5be0cd19137e2179L;
  |] in
  let mlen = String.length msg in
  (* pad: 0x80, zeros, 128-bit big-endian bit length (top 64 bits zero here) *)
  let pad1  = msg ^ "\x80" in
  let extra = (112 - (String.length pad1 mod 128) + 128) mod 128 in
  let pad2  = pad1 ^ String.make extra '\x00' ^ String.make 8 '\x00' in
  let bitlen = Int64.of_int (mlen * 8) in
  let blen_bytes = Bytes.create 8 in
  for i = 0 to 7 do
    Bytes.set blen_bytes i
      (Char.chr (Int64.to_int (land64 (srl64 bitlen ((7 - i) * 8)) 0xFFL)))
  done;
  let padded = pad2 ^ Bytes.to_string blen_bytes in
  let blocks = String.length padded / 128 in
  let w = Array.make 80 0L in
  for blk = 0 to blocks - 1 do
    let base = blk * 128 in
    for i = 0 to 15 do
      let o = base + i * 8 in
      let v = ref 0L in
      for b = 0 to 7 do
        v := Int64.logor (Int64.shift_left !v 8)
               (Int64.of_int (Char.code padded.[o + b]))
      done;
      w.(i) <- !v
    done;
    for i = 16 to 79 do
      let s0 = lxor64 (rotr64 w.(i-15) 1)  (lxor64 (rotr64 w.(i-15) 8)  (srl64 w.(i-15) 7)) in
      let s1 = lxor64 (rotr64 w.(i-2) 19) (lxor64 (rotr64 w.(i-2) 61) (srl64 w.(i-2) 6)) in
      w.(i) <- w.(i-16) +% s0 +% w.(i-7) +% s1
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2) and d = ref h.(3) in
    let e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and hh = ref h.(7) in
    for i = 0 to 79 do
      let s1  = lxor64 (rotr64 !e 14) (lxor64 (rotr64 !e 18) (rotr64 !e 41)) in
      let ch  = lxor64 (land64 !e !f) (land64 (Int64.lognot !e) !g) in
      let t1  = !hh +% s1 +% ch +% sha512_k.(i) +% w.(i) in
      let s0  = lxor64 (rotr64 !a 28) (lxor64 (rotr64 !a 34) (rotr64 !a 39)) in
      let maj = lxor64 (land64 !a !b) (lxor64 (land64 !a !c) (land64 !b !c)) in
      let t2  = s0 +% maj in
      hh := !g; g := !f; f := !e; e := !d +% t1;
      d := !c; c := !b; b := !a; a := t1 +% t2
    done;
    h.(0) <- h.(0) +% !a; h.(1) <- h.(1) +% !b;
    h.(2) <- h.(2) +% !c; h.(3) <- h.(3) +% !d;
    h.(4) <- h.(4) +% !e; h.(5) <- h.(5) +% !f;
    h.(6) <- h.(6) +% !g; h.(7) <- h.(7) +% !hh
  done;
  let out = Bytes.create 64 in
  for i = 0 to 7 do
    for b = 0 to 7 do
      Bytes.set out (i * 8 + b)
        (Char.chr (Int64.to_int (land64 (srl64 h.(i) ((7 - b) * 8)) 0xFFL)))
    done
  done;
  Bytes.to_string out

(* ---- Field arithmetic mod 2^255 - 19 (16 x 16-bit limbs) ---- *)

type gf = int array (* length 16 *)

let gf_new () : gf = Array.make 16 0
let gf_of (l : int list) : gf = Array.of_list l

let gf0 = gf_new ()
let gf1 = let g = gf_new () in g.(0) <- 1; g

let gf_D = gf_of [0x78a3; 0x1359; 0x4dca; 0x75eb; 0xd8ab; 0x4141; 0x0a4d; 0x0070;
                  0xe898; 0x7779; 0x4079; 0x8cc7; 0xfe73; 0x2b6f; 0x6cee; 0x5203]
let gf_I = gf_of [0xa0b0; 0x4a0e; 0x1b27; 0xc4ee; 0xe478; 0xad2f; 0x1806; 0x2f43;
                  0xd7a7; 0x3dfb; 0x0099; 0x2b4d; 0xdf0b; 0x4fc1; 0x2480; 0x2b83]
let gf_X = gf_of [0xd51a; 0x8f25; 0x2d60; 0xc956; 0xa7b2; 0x9525; 0xc760; 0x692c;
                  0xdc5c; 0xfdd6; 0xe231; 0xc0a4; 0x53fe; 0xcd6e; 0x36d3; 0x2169]
let gf_Y = gf_of [0x6658; 0x6666; 0x6666; 0x6666; 0x6666; 0x6666; 0x6666; 0x6666;
                  0x6666; 0x6666; 0x6666; 0x6666; 0x6666; 0x6666; 0x6666; 0x6666]

let set25519 (r : gf) (a : gf) = Array.blit a 0 r 0 16

let car25519 (o : gf) =
  let c = ref 1 in
  for i = 0 to 15 do
    let v = o.(i) + !c + 65535 in
    c := v asr 16;
    o.(i) <- v - (!c lsl 16)
  done;
  o.(0) <- o.(0) + (!c - 1) + 37 * (!c - 1)

let sel25519 (p : gf) (q : gf) (b : int) =
  let c = lnot (b - 1) in
  for i = 0 to 15 do
    let t = c land (p.(i) lxor q.(i)) in
    p.(i) <- p.(i) lxor t;
    q.(i) <- q.(i) lxor t
  done

let pack25519 (o : Bytes.t) (n : gf) =
  let m = gf_new () and t = gf_new () in
  set25519 t n;
  car25519 t; car25519 t; car25519 t;
  for _j = 0 to 1 do
    m.(0) <- t.(0) - 0xffed;
    for i = 1 to 14 do
      m.(i) <- t.(i) - 0xffff - ((m.(i-1) asr 16) land 1);
      m.(i-1) <- m.(i-1) land 0xffff
    done;
    m.(15) <- t.(15) - 0x7fff - ((m.(14) asr 16) land 1);
    let b = (m.(15) asr 16) land 1 in
    m.(14) <- m.(14) land 0xffff;
    sel25519 t m (1 - b)
  done;
  for i = 0 to 15 do
    Bytes.set o (2*i)   (Char.chr (t.(i) land 0xff));
    Bytes.set o (2*i+1) (Char.chr ((t.(i) asr 8) land 0xff))
  done

let neq25519 (a : gf) (b : gf) : bool =
  let c = Bytes.create 32 and d = Bytes.create 32 in
  pack25519 c a; pack25519 d b;
  Bytes.to_string c <> Bytes.to_string d

let par25519 (a : gf) : int =
  let d = Bytes.create 32 in
  pack25519 d a;
  Char.code (Bytes.get d 0) land 1

let unpack25519 (o : gf) (n : string) =
  for i = 0 to 15 do
    o.(i) <- Char.code n.[2*i] + (Char.code n.[2*i+1] lsl 8)
  done;
  o.(15) <- o.(15) land 0x7fff

let fadd (o : gf) (a : gf) (b : gf) = for i = 0 to 15 do o.(i) <- a.(i) + b.(i) done
let fsub (o : gf) (a : gf) (b : gf) = for i = 0 to 15 do o.(i) <- a.(i) - b.(i) done

let fmul (o : gf) (a : gf) (b : gf) =
  let t = Array.make 31 0 in
  for i = 0 to 15 do
    for j = 0 to 15 do
      t.(i+j) <- t.(i+j) + a.(i) * b.(j)
    done
  done;
  for i = 0 to 14 do
    t.(i) <- t.(i) + 38 * t.(i+16)
  done;
  Array.blit t 0 o 0 16;
  car25519 o;
  car25519 o

let fsqr (o : gf) (a : gf) = fmul o a a

let inv25519 (o : gf) (i : gf) =
  let c = gf_new () in
  set25519 c i;
  for a = 253 downto 0 do
    fsqr c c;
    if a <> 2 && a <> 4 then fmul c c i
  done;
  set25519 o c

let pow2523 (o : gf) (i : gf) =
  let c = gf_new () in
  set25519 c i;
  for a = 250 downto 0 do
    fsqr c c;
    if a <> 1 then fmul c c i
  done;
  set25519 o c

(* ---- Edwards curve points (extended coordinates: 4 x gf) ---- *)

type point = gf array (* length 4: X Y Z T *)

let point_new () : point = [| gf_new (); gf_new (); gf_new (); gf_new () |]

let point_add (p : point) (q : point) =
  let a = gf_new () and b = gf_new () and c = gf_new () and d = gf_new () in
  let t = gf_new () and e = gf_new () and f = gf_new () and g = gf_new () and h = gf_new () in
  fsub a p.(1) p.(0);
  fsub t q.(1) q.(0);
  fmul a a t;
  fadd b p.(0) p.(1);
  fadd t q.(0) q.(1);
  fmul b b t;
  fmul c p.(3) q.(3);
  fmul c c gf_D; fadd c c c;    (* c = 2 * d * T1 * T2 (D2 = 2D) *)
  fmul d p.(2) q.(2);
  fadd d d d;
  fsub e b a;
  fsub f d c;
  fadd g d c;
  fadd h b a;
  fmul p.(0) e f;
  fmul p.(1) h g;
  fmul p.(2) g f;
  fmul p.(3) e h

let point_cswap (p : point) (q : point) (b : int) =
  for i = 0 to 3 do sel25519 p.(i) q.(i) b done

let point_pack (r : Bytes.t) (p : point) =
  let tx = gf_new () and ty = gf_new () and zi = gf_new () in
  inv25519 zi p.(2);
  fmul tx p.(0) zi;
  fmul ty p.(1) zi;
  pack25519 r ty;
  Bytes.set r 31
    (Char.chr (Char.code (Bytes.get r 31) lxor (par25519 tx lsl 7)))

(* s: 32-byte little-endian scalar (int array of bytes) *)
let scalarmult (p : point) (q : point) (s : int array) =
  set25519 p.(0) gf0;
  set25519 p.(1) gf1;
  set25519 p.(2) gf1;
  set25519 p.(3) gf0;
  for i = 255 downto 0 do
    let b = (s.(i / 8) asr (i land 7)) land 1 in
    point_cswap p q b;
    point_add q p;
    point_add p p;
    point_cswap p q b
  done

let scalarbase (p : point) (s : int array) =
  let q = point_new () in
  set25519 q.(0) gf_X;
  set25519 q.(1) gf_Y;
  set25519 q.(2) gf1;
  fmul q.(3) gf_X gf_Y;
  scalarmult p q s

(* ---- Scalar arithmetic mod L ---- *)

let l_const = [|
  0xed; 0xd3; 0xf5; 0x5c; 0x1a; 0x63; 0x12; 0x58;
  0xd6; 0x9c; 0xf7; 0xa2; 0xde; 0xf9; 0xde; 0x14;
  0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0x10
|]

(* x: int array 64 (mutated); writes 32-byte result into r *)
let mod_l (r : Bytes.t) (x : int array) =
  for i = 63 downto 32 do
    let carry = ref 0 in
    let j = ref (i - 32) in
    let k = i - 12 in
    while !j < k do
      x.(!j) <- x.(!j) + !carry - 16 * x.(i) * l_const.(!j - (i - 32));
      carry := (x.(!j) + 128) asr 8;
      x.(!j) <- x.(!j) - (!carry lsl 8);
      incr j
    done;
    x.(!j) <- x.(!j) + !carry;
    x.(i) <- 0
  done;
  let carry = ref 0 in
  for j = 0 to 31 do
    x.(j) <- x.(j) + !carry - (x.(31) asr 4) * l_const.(j);
    carry := x.(j) asr 8;
    x.(j) <- x.(j) land 255
  done;
  for j = 0 to 31 do
    x.(j) <- x.(j) - !carry * l_const.(j)
  done;
  for i = 0 to 31 do
    x.(i+1) <- x.(i+1) + (x.(i) asr 8);
    Bytes.set r i (Char.chr (x.(i) land 255))
  done

(* reduce a 64-byte string mod L -> 32-byte string *)
let reduce64 (h : string) : string =
  let x = Array.init 64 (fun i -> Char.code h.[i]) in
  let r = Bytes.create 32 in
  mod_l r x;
  Bytes.to_string r

(* ---- Key generation / sign / verify ---- *)

let clamp (d : int array) =
  d.(0)  <- d.(0)  land 248;
  d.(31) <- d.(31) land 127;
  d.(31) <- d.(31) lor 64

(* Derive the 32-byte public key from a 32-byte seed. *)
let pubkey_of_seed (seed : string) : string =
  if String.length seed <> 32 then invalid_arg "ed25519: seed must be 32 bytes";
  let d = sha512 seed in
  let ds = Array.init 32 (fun i -> Char.code d.[i]) in
  clamp ds;
  let p = point_new () in
  scalarbase p ds;
  let pk = Bytes.create 32 in
  point_pack pk p;
  Bytes.to_string pk

(* Detached signature (64 bytes: R || S) over msg with a 32-byte seed. *)
let sign (msg : string) (seed : string) : string =
  if String.length seed <> 32 then invalid_arg "ed25519: seed must be 32 bytes";
  let d = sha512 seed in
  let ds = Array.init 32 (fun i -> Char.code d.[i]) in
  clamp ds;
  let pk = pubkey_of_seed seed in
  let prefix = String.sub d 32 32 in
  let r = reduce64 (sha512 (prefix ^ msg)) in
  let rs = Array.init 32 (fun i -> Char.code r.[i]) in
  let p = point_new () in
  scalarbase p rs;
  let rb = Bytes.create 32 in
  point_pack rb p;
  let rstr = Bytes.to_string rb in
  let h = reduce64 (sha512 (rstr ^ pk ^ msg)) in
  let x = Array.make 64 0 in
  for i = 0 to 31 do x.(i) <- rs.(i) done;
  for i = 0 to 31 do
    for j = 0 to 31 do
      x.(i+j) <- x.(i+j) + Char.code h.[i] * ds.(j)
    done
  done;
  let s = Bytes.create 32 in
  mod_l s x;
  rstr ^ Bytes.to_string s

(* Point decompression to the NEGATIVE of the encoded point (TweetNaCl trick
   so that verify computes h*(-A) + s*B directly). Returns None if the
   encoding is not on the curve. *)
let unpackneg (p : string) : point option =
  let r = point_new () in
  let t = gf_new () and chk = gf_new () and num = gf_new () and den = gf_new () in
  let den2 = gf_new () and den4 = gf_new () and den6 = gf_new () in
  set25519 r.(2) gf1;
  unpack25519 r.(1) p;
  fsqr num r.(1);
  fmul den num gf_D;
  fsub num num r.(2);
  fadd den r.(2) den;
  fsqr den2 den;
  fsqr den4 den2;
  fmul den6 den4 den2;
  fmul t den6 num;
  fmul t t den;
  pow2523 t t;
  fmul t t num;
  fmul t t den;
  fmul t t den;
  fmul r.(0) t den;
  fsqr chk r.(0);
  fmul chk chk den;
  if neq25519 chk num then fmul r.(0) r.(0) gf_I;
  fsqr chk r.(0);
  fmul chk chk den;
  if neq25519 chk num then None
  else begin
    if par25519 r.(0) = (Char.code p.[31] lsr 7) then fsub r.(0) gf0 r.(0);
    fmul r.(3) r.(0) r.(1);
    Some r
  end

(* Verify a detached 64-byte signature over msg against a 32-byte public key. *)
let verify (msg : string) (signature : string) (pubkey : string) : bool =
  if String.length signature <> 64 || String.length pubkey <> 32 then false
  else
    match unpackneg pubkey with
    | None -> false
    | Some q ->
      let h = reduce64 (sha512 (String.sub signature 0 32 ^ pubkey ^ msg)) in
      let hs = Array.init 32 (fun i -> Char.code h.[i]) in
      let p = point_new () in
      scalarmult p q hs;                       (* p = h * (-A) *)
      let ss = Array.init 32 (fun i -> Char.code signature.[32 + i]) in
      let qb = point_new () in
      scalarbase qb ss;                        (* qb = s * B *)
      point_add p qb;
      let t = Bytes.create 32 in
      point_pack t p;
      Bytes.to_string t = String.sub signature 0 32
