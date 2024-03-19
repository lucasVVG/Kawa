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

let add_env_aff l tenv = 
  List.fold_left (fun env ((x,_), t) -> Env.add x t env) tenv l

let typecheck_prog p =
  let tenv = add_env_aff p.globals Env.empty in

  let find_class cn = 
    try
    List.find (fun c -> c.class_name=cn) p.classes 
    with
    | Not_found -> error (Printf.sprintf "class %s does not exist" cn)
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

  and check_met m c tenv = 
    match m.access with 
    | Public -> ()
    | Private -> (
        try 
          let this = Env.find "this" tenv in 
          let sthis = (match this with TClass sc -> sc | _ -> assert false) in 
          if sthis <> c.class_name then raise Not_found 
        with Not_found -> error (Printf.sprintf "method %s is private in %s" m.method_name c.class_name)
    )
    | Protected -> (
      try 
        let this = Env.find "this" tenv in 
        let sthis = (match this with TClass sc -> sc | _ -> assert false) in 
        if subclass sthis c.class_name |> not then raise Not_found 
      with Not_found -> error (Printf.sprintf "method %s is protected in %s" m.method_name c.class_name)
  )
  
  and type_expr e tenv = match e with
    | Int _  -> TInt
    | Bool _ -> TBool
    | Get m -> type_mem_access m tenv
    | This -> (
      try Env.find "this" tenv
      with Not_found -> 
        error (Printf.sprintf "cannot call 'this' on main")
    )
    | Binop((Add|Mul|Sub|Div|Rem), e1, e2) -> check e1 TInt tenv; check e2 TInt tenv; TInt
    | Binop((Gt|Ge|Lt|Le), e1, e2) -> check e1 TInt tenv; check e2 TInt tenv; TBool
    | Binop((Or|And), e1, e2) -> check e1 TBool tenv; check e2 TBool tenv; TInt
    | Binop((Eq|Neq), e1, e2) -> check e1 (type_expr e2 tenv) tenv; TBool
    | Unop(Not, e) -> check e TBool tenv; TBool
    | Unop(Opp, e) -> check e TInt  tenv; TInt 

    | NewCstr(cn, a) -> (
      try
      let c = find_class cn in
      let cons = List.find(fun m->m.method_name="constructor") c.methods in
      List.iter2 (fun a (_, t)-> check a t tenv ) a cons.params;
      TClass cn
      with 
      | Not_found -> error (Printf.sprintf "class %s does not have a constructor" cn)
      | Invalid_argument _ -> error (Printf.sprintf "Invalid arguments in constructor of class %s" cn)
    )
    | New(cn) -> let _ = find_class cn in TClass cn
    | MethCall (e, s, l) -> 
      let tcd = type_expr e tenv in 
      (
      match tcd with
      | TClass sc -> 
        let c = find_class sc in
        let met = find_met c s in 
        check_met met c tenv;
        met.return
      | _ -> error "expected a class before '.'"
      )
    | SupCall (s,l) -> 
      try 
        let this = Env.find "this" tenv in 
        let sthis = ( match this with TClass s -> s | _ -> assert false ) in 
        let c = find_class sthis in 
        let ssuper = (
          match c.parent with
          | Some s -> s
          | None -> error (Printf.sprintf "cannot call super because class %s does not have a parent" sthis)
        ) in
        let cc = find_class ssuper in
        let met = find_met cc s in
        check_met met cc tenv;
        met.return
      with Not_found -> 
        error (Printf.sprintf "cannot call 'super' on main")
      
    (* | _ -> failwith "case not implemented in type_expr" *)
  and all_field_in a c =
    let rec find c =
      try 
        let q = (List.find (fun (k,_,_,_) -> k=a) c.attributes) in 
        q, c
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
  and type_field_in a c tenv = 
    let (_,t,_,acc),cc = all_field_in a c in
    match acc with 
      | Protected -> 
        (
        try 
          let this = Env.find "this" tenv in 
          let sthis = (match this with TClass sc -> sc | _ -> assert false) in 
          if subclass sthis cc.class_name then t
          else raise Not_found 
        with 
          Not_found -> error (Printf.sprintf "field %s is protected in %s" a cc.class_name)
        )
      | Private -> 
        (
        try 
          let this = Env.find "this" tenv in 
          let sthis = (match this with TClass sc -> sc | _ -> assert false) in 
          if sthis = cc.class_name then t
          else raise Not_found 
        with 
          Not_found -> error (Printf.sprintf "field %s is private in %s" a cc.class_name)
        )
      | Public -> t
  and type_field_in_write a c tenv =
    let (_,t,b,acc),cc = all_field_in a c in 
    if not b then begin
      match acc with 
      | Protected -> 
        (
        try 
          let this = Env.find "this" tenv in 
          let sthis = (match this with TClass sc -> sc | _ -> assert false) in 
          if subclass sthis cc.class_name then t
          else raise Not_found
        with 
          Not_found -> error (Printf.sprintf "field %s is protected in %s" a c.class_name)
        )
      | Private -> 
        (
        try 
          let this = Env.find "this" tenv in 
          let sthis = (match this with TClass sc -> sc | _ -> assert false) in 
          if sthis = cc.class_name then t
          else raise Not_found 
        with 
          Not_found -> error (Printf.sprintf "field %s is private in %s" a c.class_name)
        )
      | Public -> t
    end
    else error (Printf.sprintf "field %s is final in %s" a c.class_name)
  and type_mem_access m tenv = match m with
    | Var s -> 
      (
        try Env.find s tenv
        with Not_found -> (
          try 
            let this = Env.find "this" tenv in 
            let sthis = (match this with TClass sc -> sc | _ -> assert false) in
            type_field_in s (find_class sthis) tenv
            with Not_found -> error (Printf.sprintf "Var %s is not declared" s
          )
        )
      )
    | Field (e, s) -> (
      match (type_expr e tenv) with
      | TClass sc -> 
        let c = find_class sc in
        type_field_in s c tenv
      | _  -> error "expected a class before '.'"
      )
    (* | _ -> failwith "case not implemented in type_mem_access" *)
  and type_mem_access_write m tenv = match m with
  | Var s -> 
    (
      try 
        Env.find s tenv
      with Not_found -> (
        try 
          let this = Env.find "this" tenv in 
          let sthis = (match this with TClass sc -> sc | _ -> assert false) in
          type_field_in_write s (find_class sthis) tenv
        with Not_found -> error (Printf.sprintf "Var %s is not declared" s)
        )
    )
  | Field (e, s) -> (
    match (type_expr e tenv) with
    | TClass sc -> 
      let c = find_class sc in
      type_field_in_write s c tenv
    | _  -> error "expected a class before '.'"
    )
  in
  
  let rec check_instr i ret tenv = match i with
    | Print e -> check e TInt tenv
    | Set (m, e) -> check e (type_mem_access m tenv) tenv
    | If (ec, s1, s2) -> check ec TBool tenv; check_seq s1 ret tenv; check_seq s2 ret tenv
    | While (ec, s) -> check ec TBool tenv; check_seq s ret tenv
    | Expr(e) -> let _ = type_expr e tenv in ()
    | Return (e) -> check e ret tenv
    (* | _ -> failwith "case not implemented in check_instr" *)
  and check_seq s ret tenv =
    List.iter (fun i -> check_instr i ret tenv) s
  and check_mdef m t tenv =
    let is_cons = m.method_name = "constructor" in
    let rec check_instr_mdef i tenv = match i with (* Renvoie vrai ssi il y a un return dans tout les chemins possible*)
      | Print e -> check e TInt tenv; false
      | Set (m, e) -> 
        if is_cons then check e (type_mem_access m tenv) tenv
        else check e (type_mem_access_write m tenv) tenv; 
        false
      | If (ec, s1, s2) -> 
        let b1 = List.fold_left (fun a i -> check_instr_mdef i tenv || a) false s1 in
        let b2 = List.fold_left (fun a i -> check_instr_mdef i tenv || a) false s2 in 
        b1 && b2
      | While (ec, s) -> 
        check ec TBool tenv;
        List.iter (fun i -> let _= check_instr_mdef i tenv in ()) s; false
      | Expr(e) -> let _ = type_expr e tenv in false
      | Return (e) -> check e t tenv; true
    in
    check_all_dec (List.map (fun (_,t) -> t) m.locals);
    let tenv = tenv |> add_env m.params |> add_env_aff m.locals in 
    let b = List.fold_left (fun a i -> check_instr_mdef i  tenv || a) false m.code in
    if t<>TVoid && not b then type_error TVoid t;
    if b && t=TVoid then error ("A void method should not have a return")
  and check_class sc =
    if not (List.exists (fun x-> sc=x.class_name) p.classes) then error (Printf.sprintf "class %s does not exist" sc)
  and check_all_dec l =
    let iter t =
      match t with
      | TClass sc -> check_class sc 
      | _ -> ()
    in 
    List.iter iter l
  in

  let check_all_classes cl tenv =
    let iter c = 
      check_all_dec (List.map (fun (_,t,_,_) -> t) c.attributes);
      if c.parent <> None then check_class (Option.get c.parent);
      let env = Env.add "this" (TClass c.class_name) tenv in 
      List.iter (fun m -> check_mdef m m.return env) c.methods
    in
    List.iter iter cl
  
  in
  check_all_dec (List.map (fun ((_,_),t) -> t) p.globals);
  check_all_classes p.classes tenv;
  check_seq p.main TVoid tenv