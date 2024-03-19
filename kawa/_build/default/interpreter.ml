open Kawa

type value =
  | VInt  of int
  | VBool of bool
  | VObj  of obj
  | Null
and obj = {
  cls:    string;
  fields: (string, value) Hashtbl.t;
}

exception Error of string
exception Return of value


let exec_prog (p: program): unit =
  let env = Hashtbl.create 16 in
  List.iter (fun (x, _) -> Hashtbl.add env x Null) p.globals;

  let set_fields obj =
    let rec add_att cd = 
      (match cd.parent with
      | Some sc -> add_att (List.find (fun c -> c.class_name=sc) p.classes)
      | None -> () );
      List.iter (fun (s,_,_) -> Hashtbl.add obj.fields s Null) cd.attributes;
    in
    let cd = List.find (fun c -> c.class_name=obj.cls) p.classes in
    add_att cd;
    Hashtbl.add obj.fields "this" (VObj obj)
  in 

  let rec eval_call f this args =
    let rec get_met f cd =
      try 
        List.find (fun m -> m.method_name=f) cd.methods
      with Not_found -> match cd.parent with 
      | Some sc -> get_met f (List.find (fun c -> c.class_name=sc) p.classes) 
      | None -> raise Not_found 
    in
    let cd = List.find (fun c -> c.class_name=this.cls) p.classes in
    let menv = Hashtbl.create 16 in
    let met = get_met f cd in
    List.iter (fun (x,_) -> Hashtbl.add menv x (Hashtbl.find env x)) p.globals;
    Hashtbl.iter (fun k v -> Hashtbl.add menv k v) this.fields;
    List.iter2 (fun (k, _) v -> Hashtbl.add menv k v) met.params args;
    List.iter (fun  (k, _) -> Hashtbl.add menv k Null) met.locals;
    try
      exec_seq met.code menv; Null
    with
      Return v -> v

  
  and exec_seq s lenv =
    let rec evali e = match eval e with
      | VInt n -> n
      | _ -> assert false
    and evalb e = match eval e with
      | VBool b -> b
      | _ -> assert false
    and evalo e = match eval e with
      | VObj o -> o
      | _ -> assert false

    and eval (e: expr): value = match e with
      | Int n  -> VInt n
      | Bool b -> VBool b
      | Get (Var s) -> Hashtbl.find lenv s
      | Get (Field (o, s)) -> 
        let obj = evalo o in
          Hashtbl.find obj.fields s
      | This -> Hashtbl.find lenv "this"
      | Binop(Add, e1, e2) -> VInt (evali e1 + evali e2)
      | Binop(Sub, e1, e2) -> VInt (evali e1 - evali e2)
      | Binop(Mul, e1, e2) -> VInt (evali e1 * evali e2)
      | Binop(Div, e1, e2) -> VInt (evali e1 / evali e2)
      | Binop(Rem, e1, e2) -> VInt (evali e1 mod evali e2)

      | Binop(Or , e1, e2) -> VBool(evalb e1 || evalb e2)
      | Binop(And, e1, e2) -> VBool(evalb e1 && evalb e2)
      | Binop(Eq,  e1, e2) -> VBool(eval e1  =  eval e2)
      | Binop(Neq, e1, e2) -> VBool(eval e1  <> eval e2)
      | Binop(Lt,  e1, e2) -> VBool(evali e1 <  evali e2)
      | Binop(Gt,  e1, e2) -> VBool(evali e1 >  evali e2)
      | Binop(Le,  e1, e2) -> VBool(evali e1 <= evali e2)
      | Binop(Ge,  e1, e2) -> VBool(evali e1 >= evali e2)

      | Unop (Not, e)      -> VBool (not (evalb e))
      | Unop (Opp, e)      -> VInt(-(evali e))

      | MethCall(e, s, l) -> eval_call s (evalo e) (List.map eval l)
      | New (s) -> 
        let obj = {
          cls = s;
          fields = Hashtbl.create 16
        } in
        set_fields obj;
        VObj obj
      | NewCstr(s, l) -> 
        let obj = {
          cls = s;
          fields = Hashtbl.create 16
        } in
        set_fields obj;
        let _ = eval_call "constructor" obj (List.map eval l) in
        VObj obj
      (* | _ -> failwith "case not implemented in eval" *)
    in

    let rec exec (i: instr): unit = match i with
      | Print e -> Printf.printf "%d\n" (evali e)
      | Set (Var s, e) -> 
        assert (Hashtbl.mem lenv s);
        Hashtbl.replace lenv s (eval e)
      | Set (Field(o, s), e) -> 
        let ob = evalo o in
        assert (Hashtbl.mem ob.fields s);
        Hashtbl.replace ob.fields s (eval e)
      | If (e, s1, s2) -> 
        if evalb e then exec_seq s1 else exec_seq s2
      | While (e, s) as i -> 
        if (evalb e) then begin exec_seq s; exec i end
      | Return e -> raise (Return (eval e))
      | Expr e -> let _ = eval e in ()
      (* | _ -> failwith "case not implemented in exec" *)
    and exec_seq s = 
      List.iter exec s
    in

    exec_seq s
  in

  exec_seq p.main env
