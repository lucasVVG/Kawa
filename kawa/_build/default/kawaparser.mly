%{

  open Lexing
  open Kawa

%}

%token <int> INT
%token <string> IDENT
%token <bool> BOOL
%token MAIN
%token FINAL
%token DOT COMMA LPAR RPAR BEGIN END SEMI
%token PRINT RETURN IF WHILE ELSE
%token EOF
%token CLASS NEW THIS

%token TINT TBOOL TVOID
%token PLUS MINUS STAR DIV MOD U_MINUS
%token INF INFE SUP SUPE OR AND EQ DIF 
%token NOT
%token AFF VAR
%token EXT ATT MET

//%left LPAR

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
    { {classes=c; globals=v; main} }
;

instruction:
| PRINT LPAR e=expression RPAR SEMI { Print(e) }
| m=mem AFF e=expression SEMI   { Set (m, e) }
| RETURN e=expression SEMI      { Return e }
| WHILE LPAR e=expression RPAR BEGIN l=list(instruction) END { While(e, l) }
| IF LPAR e=expression RPAR BEGIN l1=list(instruction) END ELSE BEGIN l2=list(instruction) END { If (e, l1, l2) }
;

classdef:
| CLASS n=IDENT BEGIN atr=list(attribute) met=list(method_) END { {
    class_name=n;
    attributes=atr;
    methods=met;
    parent = None;
  } }
| CLASS n=IDENT EXT p=IDENT BEGIN atr=list(attribute) met=list(method_) END { {
    class_name=n;
    attributes=atr;
    methods=met;
    parent = Some p;
  } }
;

attribute:
| ATT t=typ s=IDENT SEMI { s, t, false }
| ATT FINAL t=typ s=IDENT SEMI { s, t, true }
;

method_:
| MET t=typ s=IDENT LPAR l=separated_list(COMMA, typed_id) RPAR BEGIN loc=list(vardef) code=list(instruction) END { {
  method_name = s;
  code = code;
  params = l;
  locals = loc;
  return = t;
} }

vardef:
| VAR t=typ s=IDENT SEMI { s, t }

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