(*
 * Copyright (c) 2015 Wojciech Kordalski
 *
 * This code is under MIT license.
 *)
(*
 * Parses code into tokens.
 * Notice: dedent is emited after newline
 *         and it is not promissed that after dedent will be a newline.
 *         Number of newlines emitted is not greater then
 *         number of newlines in the code + 1.
 *)
(*
 * TODO:
 * 1) Testing and minor fixes
 *)

module StringMap = Map.Make(String)

let kwmap : Token.t StringMap.t =
  let add_kwd s a =
    StringMap.add s (Token.Keyword(s)) a
  in
  let map = StringMap.empty in
  let map = add_kwd "var" map in
  let map = add_kwd "namespace" map in
  let map = add_kwd "pass" map in
  let map = add_kwd "def" map in
  let map = add_kwd "return" map in
  map


let opmap : Token.t StringMap.t =
  let add_simple_op s a =
    StringMap.add s (Token.Operator(s)) a
  in
  let add_simple_ops l a = List.fold_left (fun a s -> add_simple_op s a) a l in
  let map = StringMap.empty in
  let map = add_simple_ops ["+"; "-"; "~"] map in
  let map = add_simple_ops ["*"; "/"; "%"] map in
  let map = add_simple_op "**" map in
  let map = add_simple_ops ["++"; "--"] map in
  let map = add_simple_ops ["."; ","; ":"] map in
  let map = add_simple_ops ["->"] map in
  let map = add_simple_op "=" map in
  (* SPECIAL TOKENS - COMMENTS AND PARENS *)
  let map = StringMap.add "#" Token.OperatorLineComment map in
  let map = StringMap.add "/#" Token.OperatorNestableComment map in
  let map = StringMap.add "/*" Token.OperatorBlockComment map in
  let map = StringMap.add "(" Token.ParenRoundLeft map in
  let map = StringMap.add ")" Token.ParenRoundRight map in
  let map = StringMap.add "[" Token.ParenSquareLeft map in
  let map = StringMap.add "]" Token.ParenSquareRight map in
  let map = StringMap.add "{" Token.ParenCurlyLeft map in
  let map = StringMap.add "}" Token.ParenCurlyRight map in
  let map = StringMap.add "\\" Token.OperatorLineJoiner map in
  map

exception Error of string

let is_digit c = (c >= '0' && c <= '9')
let is_vletter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_letter c =  (is_vletter c) || (c = '_')
let is_hexdigit c = is_digit c || is_vletter c
let is_alpha c = is_digit c || is_letter c
let is_newline c = (c = '\n')
let is_space c = (c = ' ') || (c = '\t')
let is_quotation c = (c = '\'') || (c = '"') || (c = '`')

let space_width c =
  match c with
  | ' '  -> 1
  | '\t' -> 2
  |  _   -> failwith "Not a space character"



let skip_indentation ch : int =
  let rec helper (acc : int) : int =
    match Stream.peek ch with
    | None -> 0
    | Some(cc)->
        if is_newline cc then (Stream.junk ch; helper 0) else
        if is_space cc then (Stream.junk ch; helper (acc + space_width cc))
        else acc
  in helper 0

let rec fix_indentation indent indents buffer = (* adds/removes indentation from parents and add tokens to buffer *)
  let h = List.hd (!indents) in
  if h < indent then
  (
    indents :=  indent::(!indents);
    Queue.push Token.Indent buffer
  )
  else
  if h > indent then
  (
    indents := List.tl (!indents);
    Queue.push Token.Dedent buffer;
    fix_indentation indent indents buffer
  )
let rec skip f ch : unit =
  match Stream.peek ch with
  | None -> ()
  | Some(cc) when f cc -> let _ = Stream.junk ch in skip f ch
  | _ -> ()

let rec skip_spaces = skip is_space



let read_identifier ch =
  let rec helper acc =
    match Stream.peek ch with
    | None -> acc
    | Some(c) when is_alpha c -> (Stream.junk ch; helper (acc^(String.make 1 c)))
    | Some(_) -> acc
  in
  match Stream.peek ch with
  | None -> assert false
  | Some(c) ->
      let _ = Stream.junk ch in
      let s = helper (String.make 1 c) in
      try Some(StringMap.find s kwmap) with Not_found -> Some(Token.Identifier(s))

let read_number ch =
  let rec read_based_number acc =
    match Stream.peek ch with
    | None -> acc
    | Some(c) when is_hexdigit c || c ='\'' ->
    (
      Stream.junk ch;
      read_based_number (acc^(String.make 1 c))
    )
    | Some(_) -> acc
  and read_decimal_number acc allow_dot =
    match Stream.peek ch with
    | None -> acc
    | Some(c) when is_digit c || c = '\'' ->
    (
      Stream.junk ch;
      read_decimal_number (acc^(String.make 1 c)) allow_dot
    )
    | Some(c) when c = '.' && allow_dot ->
    (
      Stream.junk ch;
      read_decimal_number (acc^".") false
    )
    | Some(_) -> acc
  in
  let read_exponential_number acc =
    let acc = read_decimal_number acc true
    in
    match Stream.peek ch with
    | None -> acc
    | Some(c) when c = 'e' || c = 'E' ->
    (
      let acc = acc ^ (String.make 1 c) in
      Stream.junk ch;
      match Stream.peek ch with
      | None -> failwith "Lexing error: number parsing error"
      | Some(c) when c = '+' || c = '-' ->
      (
        Stream.junk ch;
        read_decimal_number (acc^(String.make 1 c)) true
      )
      | Some(c) when is_digit c ->
      (
        read_decimal_number acc true
      )
      | Some(_) -> failwith "Lexing error: number parsing error"
    )
    | Some(_) -> acc
  in
  match Stream.peek ch with
  | None -> assert false
  | Some('0')->
  (
    Stream.junk ch;
    match Stream.peek ch with
    | None -> Some(Token.Number ("0"))
    | Some(c) when is_vletter c ->
    (
      Stream.junk ch;
      Some(Token.Number (read_based_number("0"^(String.make 1 c))))
    )
    | Some(c) when is_digit c || c = '\'' || c = '.' ->
    (
      Some(Token.Number (read_exponential_number "0"))
    )
    | Some(_) -> Some(Token.Number("0"))
  )
  | Some(c) when is_digit c ->
  (
    Some(Token.Number (read_exponential_number ""))
  )
  | Some(_) -> assert false



let is_opening_paren tok =
  match tok with
  | Token.ParenRoundLeft
  | Token.ParenSquareLeft
  | Token.ParenCurlyLeft -> true
  | _ -> false

let is_closing_paren_for tok opening =
  match opening, tok with
  | Token.ParenRoundLeft, Token.ParenRoundRight -> true
  | Token.ParenSquareLeft, Token.ParenSquareRight -> true
  | Token.ParenCurlyLeft, Token.ParenCurlyRight -> true
  | _ -> false

let read_operator ch : Token.t option =
  let rec helper acc =
    let _ = Stream.junk ch in
    match Stream.peek ch with
    | None -> Some(StringMap.find acc opmap)
    | Some(c) ->
        let nacc = acc^(String.make 1 c) in
        if StringMap.mem nacc opmap then helper nacc
        else Some(StringMap.find acc opmap)
  in
  match Stream.peek ch with
  | None -> None
  | Some(c) ->
      let nacc = String.make 1 c in
      if StringMap.mem nacc opmap then helper nacc else failwith ("Unknown character sequence: "^nacc)

let read_operator_or_comment ch =
  let read_line_comment ch =
    let rec helper acc =
      match Stream.peek ch with
      | None -> acc
      | Some(c) when is_newline c -> acc
      | Some(c) ->
          let _ = Stream.junk ch in
          helper (acc ^ (String.make 1 c))
    in
    Some(Token.LineComment(helper "#"))
  in
  let read_block_comment ch =
    let rec helper aster acc =
      match Stream.peek ch with
      | None -> failwith "Unclosed block comment!"
      | Some(c) ->
          let _ = Stream.junk ch in
          if aster && c = '/' then acc^"/" else
          helper (c = '*') (acc ^ (String.make 1 c))
    in
    Some(Token.BlockComment(helper false "/*"))
  in
  let read_nested_comment ch =
    let rec helper d h s acc =
      match Stream.peek ch with
      | Some('/') when d = 1 && h ->
          let _ = Stream.junk ch in acc ^ "/"
      | Some('/') when d > 1 && h ->
          let _ = Stream.junk ch in helper (d-1) false false (acc ^ "/")
      | Some('/') ->
          let _ = Stream.junk ch in helper d false true (acc ^ "/")
      | Some('#') when s ->
          let _ = Stream.junk ch in helper (d+1) false false (acc ^ "#")
      | Some('#') ->
          let _ = Stream.junk ch in helper d true false (acc ^ "#")
      | Some(c) ->
          let _ = Stream.junk ch in helper d false false (acc ^ (String.make 1 c))
      | None -> failwith "Unterminated nested comment!"
    in
    Some(Token.NestedComment(helper 1 false false "/#"))
  in
  match read_operator ch with
  | Some(Token.OperatorLineComment) -> read_line_comment ch
  | Some(Token.OperatorBlockComment) -> read_block_comment ch
  | Some(Token.OperatorNestableComment) -> read_nested_comment ch
  | res -> res

let read_string ch : Token.t option =
  let read_multiline_augumented_string ch =
    let rec helper cnt esc prn acc =
      match Stream.peek ch with
      | None -> failwith "Unterminated string literal!"
      | Some(c) when is_newline c && prn > 0 -> failwith "Newlines inside code block are forbidden!"
      | Some(c) when esc ->
          let _ = Stream.junk ch in helper 0 false prn (acc^(String.make 1 c))
      | Some('\"') when prn > 0 ->
          let _ = Stream.junk ch in helper 0 false prn (acc^"\"")
      | Some('\"') when cnt = 2 ->
          let _ = Stream.junk ch in acc^"\""
      | Some('\"') ->
          let _ = Stream.junk ch in helper (cnt+1) false 0 (acc^"\"")
      | Some('\\') ->
          let _ = Stream.junk ch in helper 0 true prn (acc^"\\")
      | Some('[') ->
          let _ = Stream.junk ch in helper 0 false (prn+1) (acc^"[")
      | Some(']') when prn > 0 ->
          let _ = Stream.junk ch in helper 0 false (prn-1) (acc^"]")
      | Some(']') -> failwith "Unmatching parenthesis inside string literal!"
      | Some(c) ->
          let _ = Stream.junk ch in helper 0 false prn (acc^(String.make 1 c))
    in
    let _ = Stream.junk ch in
    let _ = Stream.junk ch in
    let _ = Stream.junk ch in
    Some(Token.MultilineAugumentedStringLiteral(helper 0 false 0 "\"\"\""))
  in
  let read_multiline_usual_string ch =
    let rec helper cnt esc acc =
      match Stream.peek ch with
      | None -> failwith "Unterminated string literal!"
      | Some(c) when esc ->
          let _ = Stream.junk ch in
          helper 0 false (acc ^ (String.make 1 c))
      | Some('\'') when cnt = 2 -> let _ = Stream.junk ch in acc ^ "\'"
      | Some('\'') -> let _ = Stream.junk ch in helper (cnt+1) false (acc ^ "\'")
      | Some('\\') -> let _ = Stream.junk ch in helper 0 true (acc ^ "\\")
      | Some(c) ->
          let _ = Stream.junk ch in
          helper 0 false (acc ^ (String.make 1 c))
    in
    let _ = Stream.junk ch in
    let _ = Stream.junk ch in
    let _ = Stream.junk ch in
    Some(Token.MultilineUsualStringLiteral(helper 0 false "\'\'\'"))
  in
  let read_multiline_wysiwyg_string ch =
    let rec helper cnt acc =
      match Stream.peek ch with
      | Some('`') when cnt = 2 -> let _ = Stream.junk ch in acc ^ "`"
      | Some('`') -> let _ = Stream.junk ch in helper (cnt+1) (acc ^ "`")
      | Some(c) -> let _ = Stream.junk ch in helper 0 (acc ^ (String.make 1 c))
      | None -> failwith "Unterminated string literal!"
    in
    let _ = Stream.junk ch in
    let _ = Stream.junk ch in
    let _ = Stream.junk ch in
    Some(Token.MultilineWysiwygStringLiteral(helper 0 "```"))
  in
  let read_augumented_string ch =
    let rec helper esc prn acc =
      match Stream.peek ch with
      | None -> failwith "Unterminated string literal!"
      | Some(c) when is_newline c -> failwith "Unterminated string literal!"
      | Some(c) when esc ->
          let _ = Stream.junk ch in helper false prn (acc^(String.make 1 c))
      | Some('\\') ->
          let _ = Stream.junk ch in helper true prn (acc ^ "\\")
      | Some('[') ->
          let _ = Stream.junk ch in helper false (prn+1) (acc^"[")
      | Some(']') when prn > 0 ->
          let _ = Stream.junk ch in helper false (prn-1) (acc^"]")
      | Some(']') -> failwith "Unmatching parenthesis inside string literal!"
      | Some('\"') when prn = 0 -> let _ = Stream.junk ch in acc ^ "\""
      | Some('\"') -> (* Treat as usual letter - this is in the inside code *)
          let _ = Stream.junk ch in helper false prn (acc ^ "\"")
      | Some(c) ->
          let _ = Stream.junk ch in helper false prn (acc ^(String.make 1 c))
    in
    let _ = Stream.junk ch in
    Some(Token.AugumentedStringLiteral(helper false 0 "\""))
  in
  let read_usual_string ch =
    let rec helper esc acc =
      match Stream.peek ch with
      | None -> failwith "Unterminated string literal!"
      | Some(c) when is_newline c -> failwith "Unterminated string literal!"
      | Some(c) when esc ->
          let _ = Stream.junk ch in
          helper false (acc ^ (String.make 1 c))
      | Some('\\') ->
          let _ = Stream.junk ch in
          helper true (acc ^ "\\")
      | Some('\'') ->
          let _ = Stream.junk ch in
          acc ^ "\'"
      | Some(c) ->
          let _ = Stream.junk ch in
          helper false (acc ^ (String.make 1 c))
    in
    let _ = Stream.junk ch in
    Some(Token.UsualStringLiteral(helper false "\'"))
  in
  let read_wysiwyg_string ch =
    let rec helper acc =
      match Stream.peek ch with
      | Some('`') -> let _ = Stream.junk ch in acc ^ "`"
      | Some(c) when is_newline c -> failwith "Unterminated string literal!"
      | Some(c) -> let _ = Stream.junk ch in helper (acc ^ (String.make 1 c))
      | None -> failwith "Unterminated string literal!"
    in
    let _ = Stream.junk ch in
    Some(Token.WysiwygStringLiteral(helper "`"))
  in
  match Stream.npeek 3 ch with
  | ['\"';'\"';'\"'] -> read_multiline_augumented_string ch
  | ['\'';'\'';'\''] -> read_multiline_usual_string ch
  | ['`';'`';'`'] -> read_multiline_wysiwyg_string ch
  | '\"'::_ -> read_augumented_string ch
  | '\''::_ -> read_usual_string ch
  | '`'::_ -> read_wysiwyg_string ch
  | _ -> assert false


let mk_lexer ch =
  (* Some usefull state variables *)
  let buffer = Queue.create ()
  and is_newline_tag = ref true
  and indents = ref [0]
  and parens : Token.t list ref = ref []
  and do_last_newline = ref true in
  let rec next_token x =
    (* Something in buffer *)
    if not (Queue.is_empty buffer) then Some(Queue.pop buffer) else
    (* Newline so emit indent/dedent *)
    if !is_newline_tag then
    (
      let spaces = skip_indentation ch in
      if spaces <> List.hd (!indents) then
      (
        fix_indentation spaces indents buffer;
        is_newline_tag := false;
        Some(Queue.pop buffer)
      )
      else
      (
        is_newline_tag := false;
        next_token x
      )
    )
    else
    (
      (* Skip spaces *)
      skip_spaces ch;
      (* Is it newline? *)
      match Stream.peek ch with
      | None ->
      (
        if !do_last_newline then (do_last_newline := false; Some(Token.Newline)) else
        match !indents with
        | h::t when h > 0 -> (indents := t; Some(Token.Dedent))
        | _ -> None
      )
      | Some('\n') when (!parens) <> [] ->
      (
        let tind = skip_indentation ch in
        if tind < List.hd(!indents) then raise (Error "Indentation not working as it should.")
        else next_token x
      )
      | Some('\n') ->
      (
        Stream.junk ch;
        is_newline_tag := true;
        Some(Token.Newline)
      )
      | Some(c) when is_letter c -> read_identifier ch
      | Some(c) when is_digit c  -> read_number ch
      | Some(c) when is_quotation c -> read_string ch
      | Some(c) ->
      (
        match read_operator_or_comment ch with
        | Some(Token.OperatorLineJoiner) ->
            let tind = skip_indentation ch in
            if tind < List.hd(!indents) then raise (Error "Indentation not working as it should.")
            else next_token x
        | Some(tok) ->
            if is_opening_paren tok then
              let _ = parens := tok::!parens in Some(tok)
            else if (!parens)<>[] && is_closing_paren_for tok (List.hd (!parens)) then
              let _ = parens := List.tl (!parens) in Some(tok)
            else
              Some(tok)
        | None -> None
      )
    )
  in next_token

let append_eof_token ch =
  let he = ref false in
  let next x =
    match Stream.peek ch with
    | None when !he -> None
    | None -> let _ = he := true in let _ = Stream.junk ch in Some(Token.End)
    | Some(c) -> let _ = Stream.junk ch in Some(c)
  in next

let lex ch = (* stream of nodes *)
  (* Use Stream.next to get next character *)
  (* Then lex it to get tokens *)
  let ubogi = Stream.from (mk_lexer ch) in
  Stream.from (append_eof_token ubogi)
