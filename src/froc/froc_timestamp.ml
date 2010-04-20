(*
 * This file is part of froc, a library for functional reactive programming
 * Copyright (C) 2009-2010 Jacob Donham
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
 * MA 02111-1307, USA
 *)

let debug = ref ignore
let set_debug f = debug := f

type t = {
  mutable spliced_out : bool;
  mutable next : t;
  mutable cleanup : (unit -> unit) list;
}

let is_spliced_out t = t.spliced_out

let check t =
  if t.spliced_out
  then raise (Invalid_argument "spliced out timestamp")

let empty () =
  let rec s = { spliced_out = false; next = s; cleanup = [] } in
  { spliced_out = false; next = s; cleanup = [] }

let timeline = ref (empty ())
let now = ref !timeline

let get_now () = !now
let set_now t = now := t

let init () =
  let rec loop t =
    if t != t.next
    then begin
      List.iter (fun c -> c ()) t.cleanup;
      loop t.next
    end in
  loop !timeline;
  timeline := empty ();
  now := !timeline

let tick () =
  let t = !now in
  check t;
  let t' = { spliced_out = false; next = t.next; cleanup = [] } in
  t.next <- t';
  now := t';
  t'

let add_cleanup t cleanup =
  check t;
  t.cleanup <- cleanup :: t.cleanup

let splice_out t1 t2 =
  check t1;
  check t2;
  let rec loop t =
    if t == t.next then raise (Invalid_argument "t1 >= t2");
    if t == t2 then ()
    else begin
      List.iter (fun c -> c ()) t.cleanup;
      t.cleanup <- [];
      t.spliced_out <- true;
      loop t.next
    end in
  loop t1.next;
  t1.next <- t2

let compare t1 t2 =
  check t1;
  check t2;
  if t1 == t2 then 0
  else 
    let rec loop t =
      if t == t.next then 1
      else if t == t2 then -1
      else loop t.next in
    loop t1.next

let eq t1 t2 =
  check t1;
  check t2;
  t1 == t2
