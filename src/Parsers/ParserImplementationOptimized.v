(** * Implementation of simply-typed interface of the parser *)
Require Export ADTSynthesis.Parsers.ParserInterface.
Require Import ADTSynthesis.Parsers.BaseTypes ADTSynthesis.Parsers.BooleanBaseTypes.
Require Import ADTSynthesis.Parsers.BooleanRecognizerOptimized.
Require Import ADTSynthesis.Parsers.ParserImplementation.
Require Import ADTSynthesis.Parsers.ContextFreeGrammarNotations.
Require Import ADTSynthesis.Parsers.ContextFreeGrammarTransfer.
Require Import ADTSynthesis.Parsers.ContextFreeGrammarTransferProperties.
Require Import ADTSynthesis.Parsers.StringLike.String.

Set Implicit Arguments.

Local Open Scope list_scope.

Definition transfer_parser_keep_string {Char G} {HSL}
           (old : @Parser Char G HSL)
           (new : @String Char HSL -> bool)
           (H : forall s, new s = has_parse old s)
: @Parser Char G HSL.
Proof.
  refine {| has_parse := new |};
  abstract (
      intros;
      rewrite H in *;
        first [ apply (has_parse_sound old); assumption
              | eapply (has_parse_complete old); eassumption ]
    ).
Defined.

Arguments transfer_parser_keep_string {_ _ _} _ _ _.

Definition transfer_parser {Char G} {HSL1 HSL2}
           (old : @Parser Char G HSL1)
           (make_string : @String Char HSL2 -> @String Char HSL1)
           (new : @String Char HSL2 -> bool)
           (H : forall s, new s = has_parse old (make_string s))
           (R : @String Char HSL1 -> @String Char HSL2 -> Prop)
           (R_make : forall str, R (make_string str) str)
           (R_respectful : transfer_respectful R)
           (R_flip_respectful : transfer_respectful (Basics.flip R))
: @Parser Char G HSL2.
Proof.
  refine {| has_parse := new |}.
  { abstract (
        intros str H';
        rewrite H in H';
        refine (@transfer_parse_of_item Char _ _ G R R_respectful (make_string str) str (NonTerminal G) (R_make str) _);
        apply (has_parse_sound old); assumption
      ). }
  { abstract (
        intros str p H';
        rewrite H;
        pose (@transfer_parse_of_item Char _ _ G (Basics.flip R) R_flip_respectful str (make_string str) (NonTerminal G) (R_make str) p) as p';
        apply (has_parse_complete old p'); subst p';
        exact (transfer_forall_parse_of_item _ H')
      ). }
Defined.

Arguments transfer_parser {_ _ _ _} _ _ _ _ _ _ _ _.

Section implementation.
  Context {ls : list (String.string * productions Ascii.ascii)}.
  Local Notation G := (list_to_grammar (nil::nil) ls) (only parsing).
  Context (splitter : Splitter G).
  Context (make_string : String.string -> @String _ splitter)
          (R : @String _ splitter -> @String _ string_stringlike -> Prop)
          (R_make : forall str, R (make_string str) str)
          (R_respectful : transfer_respectful R)
          (R_flip_respectful : transfer_respectful (Basics.flip R)).

  Local Instance parser_data : @boolean_parser_dataT Ascii.ascii splitter := parser_data splitter.

  Definition parser : Parser G string_stringlike.
  Proof.
    let impl := (eval simpl in (fun str => proj1_sig (parse_nonterminal_opt (ls := ls) (data := parser_data) (make_string str) (Start_symbol G)))) in
    let impl' := (eval cbv beta iota zeta delta [RDPList.rdp_list_remove_nonterminal RDPList.rdp_list_nonterminals_listT RDPList.rdp_list_is_valid_nonterminal RDPList.rdp_list_ntl_wf RDPList.rdp_list_nonterminals_listT_R] in impl) in
    let impl := (eval simpl in impl') in
    refine (transfer_parser (parser splitter) make_string impl (fun str => proj2_sig (parse_nonterminal_opt (ls := ls) (data := parser_data) (make_string str) (Start_symbol G))) R R_make _ _).
  Defined.
End implementation.