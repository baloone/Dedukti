(** Dedukti's main functionnalities. *)
open Basics
open Term

val export         : bool ref
val verbose        : bool ref

val mk_prelude     : loc -> ident -> unit

val mk_declaration : loc -> ident -> term -> unit

val mk_definable   : loc -> ident -> term -> unit

val mk_definition  : loc -> ident -> term option -> term -> unit

val mk_opaque      : loc -> ident -> term option -> term -> unit

val mk_rules       : (Rule.rule * Preterm.ruletype) list -> unit

val mk_command     : loc -> Cmd.command -> unit

val mk_ending      : unit -> unit
