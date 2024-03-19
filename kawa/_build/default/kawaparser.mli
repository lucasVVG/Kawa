
(* The type of tokens. *)

type token = 
  | WHILE
  | VAR
  | U_MINUS
  | TVOID
  | TINT
  | THIS
  | TBOOL
  | SUPE
  | SUP
  | STAR
  | SEMI
  | RPAR
  | RETURN
  | PRINT
  | PLUS
  | OR
  | NOT
  | NEW
  | MOD
  | MINUS
  | MET
  | MAIN
  | LPAR
  | INT of (int)
  | INFE
  | INF
  | IF
  | IDENT of (string)
  | FINAL
  | EXT
  | EQ
  | EOF
  | END
  | ELSE
  | DOT
  | DIV
  | DIF
  | COMMA
  | CLASS
  | BOOL of (bool)
  | BEGIN
  | ATT
  | AND
  | AFF

(* This exception is raised by the monolithic API functions. *)

exception Error

(* The monolithic API. *)

val program: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (Kawa.program)
