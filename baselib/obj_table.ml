(* Ocsigen
 * Copyright (C) 2011 Pierre Chambart
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

(* functions suffixed by _ must be called within protected, otherwise
   there is no guaranty that the hashtable is still valid *)

module AddrType =
struct
  type t = Obj.t
  let hash v =
    let v = Obj.repr v in
    if Obj.is_block v
    then (Obj.obj v:int)
    else failwith ("not a block "^(string_of_int (Obj.obj v))) 
  let equal = (==)
end

let compactions () = (Gc.stat ()).Gc.compactions

let with_no_heap_move f v =
  let gc_control = Gc.get () in
  (* disable heap compaction *)
  Gc.set { gc_control with Gc.max_overhead = max_int };
  (* promote all remaining parts of v to the major heap *)
  Gc.minor ();
  (* from now on, memory addresses of parts of v won't change *)
  let res =
    try `Data (f v)
    with e -> `Exn e
  in
  (* reset gc settings *)
  Gc.set gc_control;
  match res with
    | `Data v -> v
    | `Exn e -> raise e

let rec ( -- ) x y = if x > y then [] else x::((x+1) -- y)

let pos_sons_of_obj o =
  match Obj.tag o with
    | tag when tag = Obj.double_tag -> []
    | tag when tag = Obj.double_array_tag -> []
    | tag when tag = Obj.string_tag -> []
    | tag when tag = Obj.closure_tag -> (1 -- (Obj.size o - 1))
    | tag when tag = Obj.object_tag -> failwith "do not hande objects"
    | tag when tag = Obj.int_tag -> []
    | tag when tag = Obj.out_of_heap_tag -> failwith "out of heap value"
    | tag when tag = Obj.custom_tag -> []
    | tag when tag = Obj.infix_tag -> failwith "mutualy recursive function: TODO"
    | tag when tag < Obj.lazy_tag -> (0 -- (Obj.size o - 1))
    | t -> failwith (Printf.sprintf "tag not handled %i" t)

let sons_of_obj o =
  List.map (fun i -> Obj.field o i) (pos_sons_of_obj o)

let sons o =
  List.map (fun i -> i,Obj.field o i) (pos_sons_of_obj o)

module T = Hashtbl.Make(AddrType)

type entry =
    { v: Obj.t;
      mutable no_copy: bool;
      id : int; }

let new_id = let r = ref 0 in fun () -> incr r; !r

type table =
    { mutable table: entry T.t;
      mutable compactions: int;
      mutable root: Obj.t; }

let restore_table_ table =
  let new_t = T.create (T.length table) in
  let add _ v = T.add new_t v.v v in
  T.iter add table;
  new_t

let restore_ t =
  t.table <- restore_table_ t.table;
  t.compactions <- compactions ()

let check_and_restore_ t =
  if compactions () <> t.compactions
  then restore_ t

let protect f t v =
  let aux f t v =
    check_and_restore_ t;
    f t v
  in
  with_no_heap_move aux f t v

let rec add_ t v =
  if Obj.is_block v
  then
    if not ( T.mem t.table v )
    then
      begin
	let entry =
	  { v = v;
	    no_copy = false;
	    id = new_id (); }
	in
	T.add t.table v entry;
	List.iter (add_ t) (sons_of_obj v)
      end

let add t v = protect add_ t v

let make_  v =
  let table = T.create 0 in
  let t = { table = table;
	    compactions = compactions ();
	    root = v; } in
  add_ t v;
  t

let make v =
  with_no_heap_move make_ v

let copy_ t' =
  let t = make_ t'.root in
  let new_t = T.create (T.length t.table) in
  let copy key v =
    let new_v =
      if v.no_copy
      then { v with id = v.id } (* ensure that v is copied *)
      else { v with v = Obj.dup v.v }
    in
    T.add new_t key new_v
  in
  T.iter copy t.table;
  let restore_sons old_v new_entry =
    List.iter (fun i ->
      let old_son = (Obj.field old_v i) in
      if Obj.is_block old_son
      then
	let new_son = T.find new_t old_son in
	Obj.set_field new_entry.v i new_son.v)
      (pos_sons_of_obj new_entry.v)
  in
  T.iter restore_sons new_t;
  let t = { table = new_t;
	    root = (T.find new_t t.root).v;
	    compactions = compactions (); }
  in
  restore_ t;
  t

let copy t = protect (fun t () -> copy_ t) t ()

let mem_ t v = T.mem t.table v

let mem t v = protect mem_ t v

let find_ancessors_ t v =
  let acc = ref [] in
  T.iter (fun _ elt -> List.iter
    (fun i -> if (Obj.field elt.v i) == v then acc := (i,elt.v)::!acc)
    (pos_sons_of_obj elt.v)) t.table;
  !acc

let find_ancessors t v = protect find_ancessors_ t v

let root t = t.root

let replace_ t old_v new_v =
  if t.root == old_v
  then t.root <- new_v;
  add_ t new_v;
  List.iter (fun (i,father) -> Obj.set_field father i new_v)
    (find_ancessors_ t old_v)

let replace t a b = protect replace_ t a b

let no_copy t v = (T.find t.table v).no_copy <- true