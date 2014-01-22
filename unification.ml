
open Types

type substitution = (int*term)  list
type ustate = (term*term) list (* Terms to unify *)
            * (int*term)  list (* Variable to substitute *)
            * substitution 

let rec safe_assoc v = function
  | []                  -> None
  | (x,t)::_ when x=v   -> Some t
  | _::tl               -> safe_assoc v tl

let rec not_in n = function 
  | Meta k                      -> n<>k
  | Pi (_,a,b) | Lam (_,a,b)    -> not_in n a && not_in n b
  | App lst                     -> List.for_all (not_in n) lst
  | _                           -> true

let rec unify (lc:loc) : ustate -> substitution = function
  | ( [] , [] , s )             -> s
  | ( [] , (v,t0)::b , s)       ->
      let t = Subst.subst_meta 0 s t0 in
        if not_in v t then ( 
          match safe_assoc v s with
            | Some t'   -> unify lc ( [(t,t')] , b , s )
            | None      -> 
                let s' = List.map ( fun (z,te) -> ( z , Subst.subst_meta 0 [(v,t)] te ) ) s in
                  unify lc ( [] , b , (v,t)::s' ) ) 
        else
          raise (PatternError ( lc , "Cannot find a type." )) (*TODO error*)
  | ( a , b , s )      -> unify lc ( [] , Reduction.decompose_eq b a , s )

let rec check_meta = function
  | Meta _                      -> false
  | Pi (_,a,b) | Lam (_,a,b)    -> check_meta a && check_meta b
  | App lst                     -> List.for_all check_meta lst
  | _                           -> true

let resolve ty args eqs : term*pattern list =
  let s = unify dloc (eqs,[],[]) in
  let ty' = Subst.subst_meta 0 s ty in
    if check_meta ty' then
      ( ty' , List.map (Subst.subst_meta_p s) args )
    else
      raise (PatternError ( dloc , "Cannot find a type." ) ) (*TODO*)