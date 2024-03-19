%{

  open Lexing
  open Kawa

  let getatt l =
    l |> List.filter (fun x -> match x with Att _ -> true | _ -> false) 
    |> List.map (fun x -> match x with Att (s,t,b,a) -> s,t,b,a | _ -> assert false)

  let getmet l =
    l |> List.filter (fun x -> match x with Met _ -> true | _ -> false) 
    |> List.map (fun x -> match x with Met m -> m | _ -> assert false)


%}

%token <int> INT
%token <string> IDENT
%token <bool> BOOL
%token MAIN
%token FINAL PROTECTED PRIVATE PUBLIC
%token DOT COMMA LPAR RPAR BEGIN END SEMI
%token PRINT RETURN IF WHILE ELSE
%token EOF
%token CLASS NEW THIS SUPER

%token TINT TBOOL TVOID
%token PLUS MINUS STAR DIV MOD U_MINUS
%token INF INFE SUP SUPE OR AND EQ DIF 
%token NOT
%token AFF VAR
%token EXT ATT MET

%left OR
%left AND
%left NOT
%left EQ DIF
%left PLUS MINUS
%left STAR DIV MOD
%nonassoc INF INFE SUP SUPE
%nonassoc U_MINUS
%right DOT


%start program
%type <Kawa.program> program

%%

program:
| v=list(vardef) c=list(classdef) MAIN BEGIN main=list(instruction) END EOF
    { {classes=c; globals=List.concat v ; main} }
; 

instruction:
| PRINT LPAR e=expression RPAR SEMI { Print(e) }
| m=mem AFF e=expression SEMI   { Set (m, e) }
| RETURN e=expression SEMI      { Return e }
| WHILE LPAR e=expression RPAR BEGIN l=list(instruction) END { While(e, l) }
| IF LPAR e=expression RPAR BEGIN l1=list(instruction) END ELSE BEGIN l2=list(instruction) END { If (e, l1, l2) }
| e=expression SEMI {Expr e}
;

classdef:
| CLASS n=IDENT BEGIN atmet=list(metatt) END { {
    class_name=n;
    attributes= getatt atmet;
    methods=getmet atmet;
    parent = None;
  } }
| CLASS n=IDENT EXT p=IDENT BEGIN atmet=list(metatt) END { {
    class_name=n;
    attributes= getatt atmet;
    methods=getmet atmet;
    parent = Some p;
  } }
;

metatt:
| a=attribute {a}
| m=method_   {m}
;

attribute:
| ATT t=typ s=IDENT SEMI { Att (s, t, false, Public) }
| a=access ATT t=typ s=IDENT SEMI { Att (s, t, false, a) }
| ATT FINAL t=typ s=IDENT SEMI { Att (s, t, true, Public) }
| a=access ATT FINAL t=typ s=IDENT SEMI { Att (s, t, true, a) }
;

method_:
| MET t=typ s=IDENT LPAR l=separated_list(COMMA, typed_id) RPAR BEGIN loc=list(vardef) code=list(instruction) END { Met {
  access = Public;
  method_name = s;
  code = code;
  params = l;
  locals = List.concat loc;
  return = t;
} }
| a=access MET t=typ s=IDENT LPAR l=separated_list(COMMA, typed_id) RPAR BEGIN loc=list(vardef) code=list(instruction) END { Met {
  access = a;
  method_name = s;
  code = code;
  params = l;
  locals = List.concat loc;
  return = t;
} }

vardef:
| VAR t=typ l=separated_list(COMMA, var) SEMI { List.map (fun x->x,t) l }

var:
| s=IDENT { s, None }
| s=IDENT AFF e=expression { s, Some e }

access:
| PRIVATE { Private }
| PROTECTED { Protected }
| PUBLIC { Public }

typ:
| TINT    { TInt     }
| TBOOL   { TBool    }
| s=IDENT { TClass s }
| TVOID   { TVoid    }
;

typed_id:
| t=typ s=IDENT {(s,t)}

expression:
| n=INT  { Int(n) }
| b=BOOL { Bool(b) }
| LPAR e=expression RPAR { e }
//| e1=expression n=INT {if n<0 then Binop(Sub, e1, Int(-n)) else raise Error } // expr -5
| e1=expression PLUS  e2=expression { Binop(Add, e1, e2) }
| e1=expression MINUS e2=expression { Binop(Sub, e1, e2) }
| e1=expression STAR  e2=expression { Binop(Mul, e1, e2) }
| e1=expression DIF   e2=expression { Binop(Neq, e1, e2) }
| e1=expression EQ    e2=expression { Binop(Eq,  e1, e2) }
| e1=expression INF   e2=expression { Binop(Lt,  e1, e2) }
| e1=expression INFE  e2=expression { Binop(Le,  e1, e2) }
| e1=expression SUP   e2=expression { Binop(Gt,  e1, e2) }
| e1=expression SUPE  e2=expression { Binop(Ge,  e1, e2) }
| e1=expression AND   e2=expression { Binop(And, e1, e2) }
| e1=expression OR    e2=expression { Binop(Or,  e1, e2) }
| e1=expression MOD   e2=expression { Binop(Rem, e1, e2) }
| e1=expression DIV   e2=expression { Binop(Div, e1, e2) }
| MINUS e=expression                { Unop (Opp, e     ) } %prec U_MINUS
| NOT   e=expression                { Unop (Not, e     ) }

| NEW s=IDENT LPAR l=separated_list(COMMA, expression) RPAR    
                                    { NewCstr(s, l)      }
| NEW s=IDENT                       { New    (s)         }
| m=mem                             { Get (m) }
| e=expression DOT s=IDENT LPAR l=separated_list(COMMA, expression) RPAR
                                    { MethCall(e, s, l) }
| THIS { This }
| SUPER DOT s=IDENT LPAR l=separated_list(COMMA, expression) RPAR
                                    { SupCall (s, l)  }
;
// 1 -2
mem:
| s=IDENT { Var s }
| e=expression DOT s=IDENT { Field (e, s) }
;

(*
on devrait ajouter une fonction qui va permettre de faire la reconnaisance des attributs d'une classe
quelque soit l'endroit où elles sont placées.
Cette dernière va prendre l'entrée et faire une analyse plus poussé de cette entrée.
*)