open Types

type cbn_state = {
  ctx : term Lazy.t LList.t;    (*context*)
  term : term;                  (*term to reduce*)
  stack : cbn_state list;       (*stack*)
}

(*
 let dump_state (k,e,t,s) =
 Global.eprint ("k = "^string_of_int k^"\n");
 Global.eprint ("t = "^ Pp.string_of_term t^"\n");
 Global.eprint "e = [";
 List.iter (fun u -> Global.eprint (" ("^ Pp.string_of_term (Lazy.force u)^")")) e ;
 Global.eprint " ]\ns = [";
 List.iter (fun (_,_,u,_) -> Global.eprint (" {{ "^ Pp.string_of_term u^" }}")) s ;
 Global.eprint " ]\n"
 *)

let rec cbn_term_of_state {ctx;term;stack} : term =
  let t = ( if LList.is_empty ctx then term else Subst.psubst_l ctx 0 term ) in
    match stack with
      | [] -> t
      | a::lst ->
          mk_App t (cbn_term_of_state a) (List.map cbn_term_of_state lst)

let rec split_stack i = function
  | l  when i=0 -> Some ([],l)
  | []          -> None
  | x::l        -> ( match split_stack (i-1) l with
                       | None            -> None
                       | Some (s1,s2)    -> Some (x::s1,s2) )

let rec safe_find m v = function
  | []                  -> None
  | (_,m',v',tr)::tl       ->
      if ident_eq v v' && ident_eq m m' then Some tr
      else safe_find m v tl

let rec add_to_list lst s s' =
  match s,s' with
    | [] , []           -> Some lst
    | x::s1 , y::s2     -> add_to_list ((x,y)::lst) s1 s2
    | _ ,_              -> None

let rec cbn_reduce (config:cbn_state) : cbn_state =
  match config with
    (* Weak normal terms *)
    | {term=Type _}
    | {term=Kind}
    | {term=Pi _}
    | {term=Lam _; stack=[] } -> config
    | {ctx={LList.len=k}; term=DB (_,_,n)} when (n>=k) -> config
    (* Bound variable (to be substitute) *)
    | {ctx; term=DB (_,_,n); stack } (*when n<k*) ->
        cbn_reduce {ctx=LList.nil; term=Lazy.force (LList.nth ctx n); stack }
    (* Beta redex *)
    | {ctx; term=Lam (_,_,_,t); stack= p::s } ->
        cbn_reduce { ctx=LList.cons (lazy (cbn_term_of_state p)) ctx; term=t; stack=s }
    (* Application *)
    | {ctx; term=App (f,a,lst); stack=s } ->
        (* rev_map + rev_append to avoid map + append*)
        let tl' = List.rev_map ( fun t -> {ctx;term=t;stack=[]} ) (a::lst) in
        cbn_reduce { ctx; term=f; stack=List.rev_append tl' s; }
    (* Global variable*)
    | {term=Const (_,m,_)} when m==empty  -> config
    | {term=Const (_,m,v); stack=s }      ->
        begin
          match Env.get_infos dloc m v with
          | Def (te,_)        -> cbn_reduce { ctx=LList.nil; term=te; stack=s }
            | Decl _            -> config
            | Decl_rw (_,_,i,g) ->
                ( match split_stack i s with
                    | None                -> config
                    | Some (s1,s2)        ->
                        ( match rewrite (LList.make ~len:i s1) g with
                            | None              -> config
                            | Some (ctx,t)      -> cbn_reduce { ctx; term=t; stack= s2}
                        )
                )
        end
    | {term=Meta _}                       -> assert false

and rewrite (args:cbn_state LList.t) (g:dtree) =
  (* assert ( nargs = List.lenght args ); *)
  match g with
    | Switch (i,cases,def)      ->
        begin
          (* assert (i<Array.length args); *)
          match cbn_reduce (LList.nth args i) with
            | {term=Const (_,m,v); stack=s}  ->
                ( match safe_find m v cases , def with
                    | Some g , _        ->
                        rewrite (LList.append_l (LList.remove i args) s) g
                    | None , Some g     -> rewrite args g
                    | _ , _             -> None )
            | {stack=s} ->
                (match def with
                   | Some g     -> rewrite args g
                   | None       -> None )
        end
    | Test ([],te,def)          ->
        let ctx = LList.map (fun a -> lazy (cbn_term_of_state a)) args in
        Some ( ctx, te )
    | Test (lst,te,def)         ->
        begin
          let ctx = LList.map (fun st -> lazy (cbn_term_of_state st)) args in
          let conv_tests =
            List.map (fun (t1,t2) -> ( {ctx;term=t1;stack=[]} , {ctx;term=t2;stack=[]}) ) lst in
            if state_conv conv_tests then
              let ctx = LList.map (fun a -> lazy (cbn_term_of_state a)) args in
              Some (ctx, te)
            else
              match def with
                | None    -> None
                | Some g  -> rewrite args g
        end

and state_conv : (cbn_state*cbn_state) list -> bool = function
  | []                  -> true
  | (s1,s2)::lst        ->
      begin
        let t1 = cbn_term_of_state s1 in
        let t2 = cbn_term_of_state s2 in
          if term_eq t1 t2 then
            state_conv lst
          else
            let s1' = cbn_reduce s1 in
            let s2' = cbn_reduce s2 in
              match s1',s2' with (*states are beta-delta head normal*)
                | {term=Kind; stack=s} , {term=Kind; stack=s'}
                | {term=Type _; stack=s} , {term=Type _; stack=s'} ->
                    (* assert ( List.length s == 0 && List.length s' == 0 ) *)
                    state_conv lst
                | {ctx={LList.len=k}; term=DB (_,_,n); stack=s},
                  {ctx={LList.len=k'}; term=DB (_,_,n'); stack=s'} ->
                    ( (*assert (k<=n && k'<=n') ;*) (n-k)=(n'-k') &&
                      match (add_to_list lst s s') with
                        | None          -> false
                        | Some lst'     -> state_conv lst'
                    )
                | {term=Const (_,m,v); stack=s}, {term=Const (_,m',v'); stack=s'} ->
                    ( ident_eq v v' && ident_eq m m' &&
                      match (add_to_list lst s s') with
                        | None          -> false
                        | Some lst'     -> state_conv lst'
                    )
                | {ctx; term=Lam (_,_,a,f); stack=s}, {ctx=ctx'; term=Lam (_,_,a',f'); stack=s'}
                | {ctx; term=Pi (_,_,a,f); stack=s}, {ctx=ctx'; term=Pi (_,_,a',f');stack=s'} ->
                    let arg = Lazy.lazy_from_val (mk_Unique ()) in
                    let x = {ctx;term=a;stack=[]} , {ctx=ctx';term=a';stack=[]} in
                    let y = {ctx=LList.cons arg ctx; term=f; stack=[]},
                            {ctx=LList.cons arg ctx'; term=f'; stack=[]} in
                      ( match add_to_list (x::y::lst) s s' with
                          | None        -> false
                          | Some lst'   -> state_conv lst' )
                | {term=Meta _} , _
                | _ , {term=Meta _}     -> assert false
                | _, _                  -> false
      end

(* Weak Normal Form *)
let whnf t = cbn_term_of_state ( cbn_reduce {ctx=LList.nil; term=t; stack=[]} )

(* Head Normal Form *)
let rec hnf t =
  match whnf t with
    | Kind | Const _ | DB _ | Type _ | Pi (_,_,_,_) | Lam (_,_,_,_) as t' -> t'
    | App (f,a,lst) -> mk_App (hnf f) (hnf a) (List.map hnf lst)
    | Meta _  -> assert false

(* Convertibility Test *)
let are_convertible t1 t2 =
  state_conv [ ( {ctx=LList.nil;term=t1;stack=[]} , {ctx=LList.nil;term=t2;stack=[]} ) ]

(* Strong Normal Form *)
let rec snf (t:term) : term =
  match whnf t with
    | Kind | Const _
    | DB _ | Type _ as t' -> t'
    | App (f,a,lst)     -> mk_App (snf f) (snf a) (List.map snf lst)
    | Pi (_,x,a,b)        -> mk_Pi dloc x (snf a) (snf b)
    | Lam (_,x,a,b)       -> mk_Lam dloc x (snf a) (snf b)
    | Meta _            -> assert false

(* One-Step Reduction *)
let rec state_one_step = function
  (* Weak normal terms *)
  | {term=Type _}
  | {term=Kind}
  | {term=Pi _}                       -> None
  | {term=Lam _; stack=[]}            -> None
  | {ctx={LList.len=k}; term=DB (_,_,n)} when (n>=k)      -> None
  (* Bound variable (to be substitute) *)
  | {ctx; term=DB (_,_,n); stack} (*when n<k*)     ->
      Some {ctx=LList.nil; term=Lazy.force (LList.nth ctx n); stack}
  (* Beta redex *)
  | {ctx; term= Lam (_,_,_,t); stack=p::s}            ->
      Some {ctx=LList.cons (lazy (cbn_term_of_state p)) ctx; term=t; stack=s}
  (* Application *)
  | {ctx; term=App (f,a,args); stack=s }              ->
      let tl' = List.map ( fun t -> {ctx;term=t;stack=[]} ) (a::args) in
      state_one_step {ctx; term=f; stack=tl' @ s; }
  (* Global variable*)
  | {term=Const (_,m,_)} when m==empty  -> None
  | {term=Const (_,m,v); stack=s }      ->
      begin
        match Env.get_infos dloc m v with
          | Def (te,_)          -> Some {ctx=LList.nil; term=te; stack=s}
          | Decl _              -> None
          | Decl_rw (_,_,i,g)   ->
              ( match split_stack i s with
                  | None                -> None
                  | Some (s1,s2)        ->
                      ( match rewrite (LList.make ~len:i s1) g with
                          | None              -> None
                          | Some (ctx,t)      -> Some {ctx; term=t; stack=s2}
                      )
              )
      end
  | {term=Meta _}                       -> assert false

let one_step t =
  match state_one_step {ctx=LList.nil; term=t; stack=[]} with
    | None      -> None
    | Some st   -> Some ( cbn_term_of_state st )
