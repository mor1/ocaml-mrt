(*
 * Copyright (c) 2012 Richard Mortier <mort@cantab.net>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Printf
open Operators

cenum tc {
  OSPF2     = 11;
  TABLE     = 12;
  TABLE2    = 13;
  BGP4MP    = 16;
  BGP4MP_ET = 17;
  ISIS      = 32;
  ISIS_ET   = 33;
  OSPF3     = 48;
  OSPF3_ET  = 49
} as uint8_t

cstruct h {
  uint32_t ts_sec;
  uint16_t mrttype;
  uint16_t subtype;
  uint32_t len
} as big_endian

cstruct et {
  uint32_t ts_usec
} as big_endian
    
type header = {
  ts_sec: int32;
  ts_usec: int32;
}

let header_to_string h = sprintf "%ld.%06ld" h.ts_sec h.ts_usec

type payload = 
  | Bgp4mp of Bgp4mp.t
  | Table of Table.t
  | Table2 of Table2.t
  | Unknown of Cstruct.buf

let payload_to_string p = sprintf "%s" (match p with 
  | Bgp4mp p  -> Bgp4mp.to_string p
  | Table p   -> Table.to_string p
  | Table2 p  -> Table2.to_string p
  | Unknown p -> "UNKNOWN()"
)

type t = header * payload

let to_string (h,p) =
  sprintf "%s|%s" (header_to_string h) (payload_to_string p)

let parse buf = 
  let lenf buf = 
    let hlen = match buf |> get_h_mrttype |> int_to_tc with
      | None -> failwith "lenf: bad MRT header"
      | Some (BGP4MP_ET|OSPF3_ET|ISIS_ET) -> sizeof_h + sizeof_et
      | Some (OSPF2|OSPF3|ISIS|TABLE|TABLE2|BGP4MP) -> sizeof_h
    in
    let plen = Int32.to_int (get_h_len buf) - hlen in
    hlen, plen
  in
  let pf hlen buf = 
    let h,p = Cstruct.split buf hlen in 
    let header =
      let usec = 
        if hlen = sizeof_h + sizeof_et then get_et_ts_usec h else 0l 
      in
      { ts_sec = get_h_ts_sec h;
        ts_usec = usec;
      }
    in
    let subtype = get_h_subtype h in
    header, (match h |> get_h_mrttype |> int_to_tc with
      | None -> failwith "pf: bad MRT header"
      | Some BGP4MP -> (match Bgp4mp.parse subtype p () with
          | Some v -> Bgp4mp v
          | None -> failwith "pf: bad BGP4MP packet"
      )
      | Some TABLE -> (match Table.parse subtype p () with
          | Some v -> Table v
          | None -> failwith "pf: bad TABLE packet"
      )
      | Some TABLE2 -> (match Table2.parse subtype p () with
          | Some v -> Table2 v
          | None -> failwith "pf: bad TABLE2 packet"
      )
      | Some (OSPF3_ET|OSPF3|ISIS_ET|ISIS|BGP4MP_ET|OSPF2)
        -> failwith (sprintf "pf: unsupported type %d" (get_h_mrttype h))
    )
  in
  Cstruct.(iter lenf pf buf)
