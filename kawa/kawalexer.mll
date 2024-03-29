{

  open Lexing
  open Kawaparser

  exception Error of string

  let keyword_or_ident =
  let h = Hashtbl.create 18 in
  List.iter (fun (s, k) -> Hashtbl.add h s k)
    [ "print",     PRINT;
      "main",      MAIN;
      "true",      BOOL true;
      "false",     BOOL false;
      "var",       VAR;
      "class",     CLASS;
      "extends",   EXT;
      "attribute", ATT;
      "void",      TVOID;
      "int",       TINT;
      "bool",      TBOOL;
      "new",       NEW;
      "method",    MET;
      "return",    RETURN;
      "this",      THIS;
      "while",     WHILE;
      "if",        IF;
      "else",      ELSE;
      "final",     FINAL;
      "private",   PRIVATE;
      "protected", PROTECTED;
      "public",    PUBLIC;
      "super",     SUPER
    ] ;
  fun s ->
    try  Hashtbl.find h s
    with Not_found -> IDENT(s)
        
}

let digit = ['0'-'9']
let number = ['-']? digit+
let alpha = ['a'-'z' 'A'-'Z']
let ident = ['a'-'z' '_'] (alpha | '_' | digit)*
  
rule token = parse
  | ['\n']            { new_line lexbuf; token lexbuf }
  | [' ' '\t' '\r']+  { token lexbuf }

  | "//" [^ '\n']* "\n"  { new_line lexbuf; token lexbuf }
  | "/*"                 { comment lexbuf; token lexbuf }

  | number as n  { INT(int_of_string n) }
  | ident as id  { keyword_or_ident id }

  | "."  { DOT }
  | ","  { COMMA }
  | ";"  { SEMI }
  | "("  { LPAR }
  | ")"  { RPAR }
  | "{"  { BEGIN }
  | "}"  { END }

  | "+"  { PLUS }
  | "-"  { MINUS }
  | "*"  { STAR }
  | "%"  { MOD }
  | "/"  { DIV }

  | "<"  { INF }
  | "<=" { INFE }
  | ">"  { SUP }
  | ">=" { SUPE }
  | "!=" { DIF }
  | "!"  { NOT }
  | "==" { EQ }
  | "&&" { AND }
  | "||" { OR }


  | "="  { AFF }

  | _    { raise (Error ("unknown character : " ^ lexeme lexbuf)) }
  | eof  { EOF }

and comment = parse
  | "*/" { () }
  | _    { comment lexbuf }
  | eof  { raise (Error "unterminated comment") }
