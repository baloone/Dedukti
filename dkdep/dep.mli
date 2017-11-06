open Basic
open Term

val out                 : out_channel ref

val mk_prelude          : loc -> Name.mident -> unit

val mk_declaration      : loc -> Name.ident -> Signature.staticity -> term -> unit

val mk_definition       : loc -> Name.ident -> term option -> term -> unit

val mk_opaque           : loc -> Name.ident -> term option -> term -> unit

val mk_rules            : Rule.untyped_rule list -> unit

val mk_command          : loc -> Cmd.command -> unit

val mk_ending           : unit -> unit

val filename            : string ref

val verbose             : bool ref

val sorted              : bool ref

val sort                : unit -> string list
