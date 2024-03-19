open Kawa

exception Error of string
let error s = raise (Error s)
let type_error ty_actual ty_expected =
  error (Printf.sprintf "expected %s, got %s"
          (typ_to_string ty_expected) (typ_to_string ty_actual))


module Env = Map.Make(String)
type tenv = typ Env.t

let add_env l tenv =
  List.fold_left (fun env (x, t) -> Env.add x t env) tenv l

let typecheck_prog p =
  let tenv = add_env p.globals Env.empty in

  let find_class cn = 
    List.find (fun c -> c.class_name=cn) p.classes 
  in

  let find_met c m = 
    let rec find c =
      try 
        List.find (fun me -> me.method_name=m) c.methods
      with Not_found -> match c.parent with 
      | Some sc -> find (find_class sc)
      | None -> raise Not_found
    in
    try find c 
    with Not_found -> error (Printf.sprintf "method %s not in %s" m c.class_name)
  in

  let rec add_att c env =
    let env1 =match c.parent with
    | Some sc -> add_att (find_class sc) env
    | None -> env 
    in
    List.fold_left (fun e (x,t,b) -> Env.add x (t,b) e) env1 c.attributes
  in

  let subclass t1 t2 =
    let rec loop c1 c2 =
      if (c1 = c2) then true
      else match c1.parent with
      | None -> false
      | Some c -> loop (find_class c) c2
    in 
    loop (find_class t1) (find_class t2)
  in 

  let rec check e typ tenv =
    let typ_e = type_expr e tenv in
    match typ_e, typ with
      | TClass se, TClass s -> if not (subclass se s) then type_error typ_e typ
      | _ -> if typ_e <> typ then type_error typ_e typ

  and type_expr e tenv = match e with
    | Int _  -> TInt
    | Bool _ -> TBool
    | Get m -> type_mem_access m tenv
    | This -> (
      try Env.find "this" tenv
      with Not_found -> 
        error (Printf.sprintf "no this :'(")
    )
    | Binop((Add|Mul|Sub|Div|Rem), e1, e2) -> check e1 TInt tenv; check e2 TInt tenv; TInt
    | Binop((Gt|Ge|Lt|Le), e1, e2) -> check e1 TInt tenv; check e2 TInt tenv; TBool
    | Binop((Or|And), e1, e2) -> check e1 TBool tenv; check e2 TBool tenv; TInt
    | Binop((Eq|Neq), e1, e2) -> TBool
    | Unop(Not, e) -> check e TBool tenv; TBool
    | Unop(Opp, e) -> check e TInt  tenv; TInt 

    | NewCstr(cn, a) -> 
      let c = find_class cn in
      let cons = List.find(fun m->m.method_name="constructor") c.methods in
      List.iter2 (fun a (_, t)-> check a t tenv ) a cons.params;
      TClass cn
    | New(cn) -> let _ = find_class cn in TClass cn
    | MethCall (e, s, l) -> 
      let tcd = type_expr e tenv in 
      match tcd with
      | TClass sc -> 
        let c = find_class sc in
        let met = find_met c s in 
        met.return
      | _ -> error "expected a class before '.'"
    (* | _ -> failwith "case not implemented in type_expr" *)
  and type_field_in a c = 
    let rec find c =
      try 
        let (_,v,_) = (List.find (fun (k,_,_) -> k=a) c.attributes) in 
        v
      with
        Not_found -> 
          match c.parent with
          | Some s -> 
            let cs = find_class s in
            find cs 
          | None -> raise Not_found
    in
    try find c 
    with Not_found -> error (Printf.sprintf "field %s not in %s" a c.class_name)
  and type_field_in_write a c =
    let rec find c =
      try 
        let (_,v,b) = (List.find (fun (k,_,_) -> k=a) c.attributes) in 
        if not b then v
        else error (Printf.sprintf "field %s is final in %s" a c.class_name)
      with
        Not_found -> 
          match c.parent with
          | Some s -> 
            let cs = find_class s in
            find cs 
          | None -> raise Not_found
    in
    try find c 
    with Not_found -> error (Printf.sprintf "field %s not in %s" a c.class_name)
  and type_mem_access m tenv = match m with
    | Var s -> 
      (
        try Env.find s tenv
        with Not_found -> 
          error (Printf.sprintf "Var %s is not declared nw" s)
      )
    | Field (e, s) -> (
      match (type_expr e tenv) with
      | TClass sc -> 
        let c = find_class sc in
        type_field_in s c
      | _  -> error "expected a class before '.'"
      )
    (* | _ -> failwith "case not implemented in type_mem_access" *)
  and type_mem_access_write m tenvbis tenv = match m with
  | Var s -> 
    (
      try 
      let t,b = Env.find s tenvbis in 
      if not b then t 
      else error (Printf.sprintf "field %s is final" s)
      with Not_found -> 
        error (Printf.sprintf "Var %s is not declared" s)
    )
  | Field (e, s) -> (
    match (type_expr e tenv) with
    | TClass sc -> 
      let c = find_class sc in
      type_field_in_write s c
    | _  -> error "expected a class before '.'"
    )
  in

  let rec check_instr i ret tenv = match i with
    | Print e -> check e TInt tenv
    | Set (m, e) -> check  e (type_mem_access m tenv) tenv
    | If (ec, s1, s2) -> check ec TBool tenv; check_seq s1 ret tenv; check_seq s2 ret tenv
    | While (ec, s) -> check ec TBool tenv; check_seq s ret tenv
    | Expr(e) -> ()
    | Return (e) -> check e ret tenv
    (* | _ -> failwith "case not implemented in check_instr" *)
  and check_seq s ret tenv =
    List.iter (fun i -> check_instr i ret tenv) s
  and check_mdef m t tenvbis =
    let is_cons = m.method_name = "constructor" in
    let rec check_instr_mdef i tenvbis tenv = match i with
      | Print e -> check e TInt tenv; false
      | Set (m, e) -> 
        if is_cons then check e (type_mem_access m tenv) tenv
        else check e (type_mem_access_write m tenvbis tenv) tenv; 
        false
      | If (ec, s1, s2) -> 
        List.fold_left (fun a i -> check_instr_mdef i tenvbis tenv || a) false s1
        && List.fold_left (fun a i -> check_instr_mdef i tenvbis tenv || a) false s2
      | While (ec, s) -> 
        check ec TBool tenv;
        List.fold_left (fun a i -> check_instr_mdef i tenvbis tenv || a) false s
      | Expr(e) -> false
      | Return (e) -> check e t tenv; true
    in  (* (typ * bool) Env *)
    let add_env_bis l b env =
      List.fold_left (fun env (x, t) -> Env.add x (t, b) env) env l
    in
    let tenvbis = tenvbis |> add_env_bis m.params false |> add_env_bis m.locals false in 
    let tenv = Env.map fst tenvbis in
    let b = List.fold_left (fun a i -> check_instr_mdef i tenvbis tenv || a) false m.code in
    if t<>TVoid && not b then type_error TVoid t
  in

  let check_all_classes cl tenv =
    let iter c = 
      let env = Env.add "this" (TClass c.class_name, false) tenv |> add_att c in 
      List.iter (fun m -> check_mdef m m.return env) c.methods
    in
    List.iter iter cl

  in
  check_all_classes p.classes (Env.map (fun t -> t,true) tenv);
  check_seq p.main TVoid tenv