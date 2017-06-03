Require Import
        Coq.Strings.String
        Coq.Arith.Mult
        Coq.Vectors.Vector.

Require Import
        Fiat.Examples.DnsServer.SimplePacket
        Fiat.Common.SumType
        Fiat.Common.BoundedLookup
        Fiat.Common.ilist
        Fiat.Common.DecideableEnsembles
        Fiat.Computation
        Fiat.QueryStructure.Specification.Representation.Notations
        Fiat.QueryStructure.Specification.Representation.Heading
        Fiat.QueryStructure.Specification.Representation.Tuple
        Fiat.BinEncoders.Env.BinLib.AlignedByteString
        Fiat.BinEncoders.Env.BinLib.AlignWord
        Fiat.BinEncoders.Env.Common.Specs
        Fiat.BinEncoders.Env.Common.Compose
        Fiat.BinEncoders.Env.Common.ComposeOpt
        Fiat.BinEncoders.Env.Automation.Solver
        Fiat.BinEncoders.Env.Lib2.WordOpt
        Fiat.BinEncoders.Env.Lib2.NatOpt
        Fiat.BinEncoders.Env.Lib2.StringOpt
        Fiat.BinEncoders.Env.Lib2.EnumOpt
        Fiat.BinEncoders.Env.Lib2.FixListOpt
        Fiat.BinEncoders.Env.Lib2.SumTypeOpt
        Fiat.BinEncoders.Env.Lib2.DomainNameOpt
        Fiat.Common.IterateBoundedIndex
        Fiat.Common.Tactics.CacheStringConstant.

Require Import
        Bedrock.Word.

Section DnsPacket.

  Open Scope Tuple_scope.

  Definition association_list K V := list (K * V).

  Fixpoint association_list_find_first {K V}
           {K_eq : Query_eq K}
           (l : association_list K V)
           (k : K) : option V :=
    match l with
    | (k', v) :: l' => if A_eq_dec k k' then Some v else association_list_find_first l' k
    | _ => None
    end.

  Fixpoint association_list_find_all {K V}
           {K_eq : Query_eq K}
           (l : association_list K V)
           (k : K) : list V :=
    match l with
    | (k', v) :: l' => if A_eq_dec k k' then v :: association_list_find_all l' k
                       else association_list_find_all l' k
    | _ => nil
    end.

  Fixpoint association_list_add {K V}
           {K_eq : DecideableEnsembles.Query_eq K}
           (l : association_list K V)
           (k : K) (v : V) : list (K * V)  :=
    (k, v) :: l.

  Instance dns_list_cache : Cache :=
    {| CacheEncode := option (word 17) * association_list string pointerT;
       CacheDecode := option (word 17) * association_list pointerT string;
       Equiv ce cd := fst ce = fst cd
                      /\ (snd ce) = (map (fun ps => match ps with (p, s) => (s, p) end) (snd cd))
                      /\ NoDup (map fst (snd cd))
    |}%type.

  Definition list_CacheEncode_empty : CacheEncode := (Some (wzero _), nil).
  Definition list_CacheDecode_empty : CacheDecode := (Some (wzero _), nil).

  Lemma list_cache_empty_Equiv : Equiv list_CacheEncode_empty list_CacheDecode_empty.
  Proof.
    simpl; intuition; simpl; econstructor.
  Qed.

  Local Opaque pow2.
  Arguments natToWord : simpl never.
  Arguments wordToNat : simpl never.

  (* pointerT2Nat (Nat2pointerT (NPeano.div (wordToNat w) 8)) *)

  Instance cacheAddNat : CacheAdd _ nat :=
    {| addE ce n := (Ifopt (fst ce) as m Then
                                         let n' := (wordToNat m) + n in
                     if Compare_dec.lt_dec n' (pow2 17)
                     then Some (natToWord _ n')
                     else None
                            Else None, snd ce);
       addD cd n := (Ifopt (fst cd) as m Then
                                         let n' := (wordToNat m) + n in
                     if Compare_dec.lt_dec n' (pow2 17)
                     then Some (natToWord _ n')
                     else None
                            Else None, snd cd) |}.
  Proof.
    simpl; intuition eauto; destruct a; destruct a0;
      simpl in *; eauto; try congruence.
    injections.
    find_if_inside; eauto.
  Defined.

  Instance Query_eq_string : Query_eq string :=
    {| A_eq_dec := string_dec |}.

  Instance : Query_eq pointerT :=
    {| A_eq_dec := pointerT_eq_dec |}.

  Instance cachePeekDNPointer : CachePeek _ (option pointerT) :=
    {| peekE ce := Ifopt (fst ce) as m Then Some (Nat2pointerT (wordToNat (wtl (wtl (wtl m))))) Else None;
       peekD cd := Ifopt (fst cd) as m Then Some
                                       (Nat2pointerT (wordToNat (wtl (wtl (wtl m)))))
                                       Else None |}.
  Proof.
    abstract (simpl; intros; intuition; rewrite H0; auto).
  Defined.

  Lemma cacheGetDNPointer_pf
    : forall (ce : CacheEncode) (cd : CacheDecode)
             (p : string) (q : pointerT),
      Equiv ce cd ->
      (association_list_find_first (snd cd) q = Some p <-> List.In q (association_list_find_all (snd ce) p)).
  Proof.
    intros [? ?] [? ?] ? ?; simpl; intuition eauto; subst.
    - subst; induction a0; simpl in *; try congruence.
      destruct a; simpl in *; find_if_inside; subst.
      + inversion H2; subst; intros.
        find_if_inside; subst; simpl; eauto.
      + inversion H2; subst; intros.
        find_if_inside; subst; simpl; eauto; congruence.
    - subst; induction a0; simpl in *; intuition.
      destruct a; simpl in *; find_if_inside.
      + inversion H2; subst; intros.
        find_if_inside; subst; simpl; eauto; try congruence.
        apply IHa0 in H1; eauto.
        elimtype False; apply H3; revert H1; clear.
        induction a0; simpl; intros; try congruence.
        destruct a; find_if_inside; injections; auto.
      + inversion H2; subst; intros.
        find_if_inside; subst; simpl; eauto; try congruence.
        simpl in H1; intuition eauto; subst.
        congruence.
  Qed.

  Instance cacheGetDNPointer : CacheGet dns_list_cache string pointerT :=
    {| getE ce p := @association_list_find_all string _ _ (snd ce) p;
       getD ce p := association_list_find_first (snd ce) p;
       get_correct := cacheGetDNPointer_pf |}.

  Lemma cacheAddDNPointer_pf
    : forall (ce : CacheEncode) (cd : CacheDecode) (t : string * pointerT),
   Equiv ce cd ->
   add_ptr_OK t ce cd ->
   Equiv (fst ce, association_list_add (snd ce) (fst t) (snd t))
     (fst cd, association_list_add (snd cd) (snd t) (fst t)).
  Proof.
    simpl; intuition eauto; simpl in *; subst; eauto.
    unfold add_ptr_OK in *.
    destruct t; simpl in *; simpl; econstructor; eauto.
    clear H3; induction b0; simpl.
    - intuition.
    - simpl in H0; destruct a; find_if_inside;
        try discriminate.
      intuition.
  Qed.

  Instance cacheAddDNPointer
    : CacheAdd_Guarded _ add_ptr_OK :=
    {| addE_G ce sp := (fst ce, association_list_add (snd ce) (fst sp) (snd sp));
       addD_G cd sp := (fst cd, association_list_add (snd cd) (snd sp) (fst sp));
       add_correct_G := cacheAddDNPointer_pf
    |}.

  Lemma IndependentCaches :
    forall env p (b : nat),
      getD (addD env b) p = getD env p.
  Proof.
    simpl; intros; eauto.
  Qed.

  Lemma IndependentCaches' :
    forall env p (b : nat),
      getE (addE env b) p = getE env p.
  Proof.
    simpl; intros; eauto.
  Qed.

  Lemma IndependentCaches''' :
    forall env b,
      peekE (addE_G env b) = peekE env.
  Proof.
    simpl; intros; eauto.
  Qed.

  Lemma getDistinct :
    forall env l p p',
      p <> p'
      -> getD (addD_G env (l, p)) p' = getD env p'.
  Proof.
    simpl; intros; eauto.
    find_if_inside; try congruence.
  Qed.

  Lemma getDistinct' :
    forall env l p p' l',
      List.In p (getE (addE_G env (l', p')) l)
      -> p = p' \/ List.In p (getE env l).
  Proof.
    simpl in *; intros; intuition eauto.
    find_if_inside; simpl in *; intuition eauto.
  Qed.

  Arguments NPeano.div : simpl never.

  Lemma mult_pow2 :
    forall m n,
      pow2 m * pow2 n = pow2 (m + n).
  Proof.
    Local Transparent pow2.
    induction m; simpl; intros.
    - omega.
    - rewrite <- IHm.
      rewrite <- !plus_n_O.
      rewrite Mult.mult_plus_distr_r; omega.
  Qed.

  Corollary mult_pow2_8 : forall n,
      8 * (pow2 n) = pow2 (3 + n).
  Proof.
    intros; rewrite <- mult_pow2.
    reflexivity.
  Qed.

  Local Opaque pow2.

  Lemma pow2_div
    : forall m n,
      lt (m + n * 8) (pow2 17)
      -> lt (NPeano.div m 8) (pow2 14).
  Proof.
    intros.
    eapply (NPeano.Nat.mul_lt_mono_pos_l 8); try omega.
    rewrite mult_pow2_8.
    eapply le_lt_trans.
    apply NPeano.Nat.mul_div_le; try omega.
    simpl.
    omega.
  Qed.

  Lemma addPeekNone :
    forall env n,
      peekD env = None
      -> peekD (addD env n) = None.
  Proof.
    simpl; intros.
    destruct (fst env); simpl in *; congruence.
  Qed.

  Lemma wtl_div
    : forall n (w : word (S (S (S n)))),
      wordToNat (wtl (wtl (wtl w))) = NPeano.div (wordToNat w) 8.
  Proof.
    intros.
    pose proof (shatter_word_S w); destruct_ex; subst.
    pose proof (shatter_word_S x0); destruct_ex; subst.
    pose proof (shatter_word_S x2); destruct_ex; subst.
    simpl wtl.
    rewrite <- (NPeano.Nat.div_div _ 2 4) by omega.
    rewrite <- (NPeano.Nat.div_div _ 2 2) by omega.
    rewrite <- !NPeano.Nat.div2_div.
    rewrite !div2_WS.
    reflexivity.
  Qed.

  Lemma mult_lt_compat_l'
    : forall (m n p : nat),
      lt 0 p
      -> lt (p * n)  (p * m)
      -> lt n m.
  Proof.
    induction m; simpl; intros; try omega.
    rewrite (mult_comm p 0) in H0; simpl in *; try omega.
    destruct p; try (elimtype False; auto with arith; omega).
    inversion H0.
    rewrite (mult_comm p (S m)) in H0.
    simpl in H0.
    destruct n; try omega.
    rewrite (mult_comm p (S n)) in H0; simpl in H0.
    apply plus_lt_reg_l in H0.
    rewrite <- NPeano.Nat.succ_lt_mono.
    eapply (IHm n p); try eassumption; try omega.
    rewrite mult_comm.
    rewrite (mult_comm p m); auto.
  Qed.

  Lemma mult_lt_compat_l''
    : forall (p m k n : nat),
      lt 0 p
      -> lt n m
      -> lt k p
      -> lt ((p * n) + k) (p * m).
  Proof.
    induction p; intros; try omega.
    simpl.
    inversion H; subst; simpl.
    inversion H1; subst; omega.
    destruct k; simpl.
    - rewrite <- plus_n_O.
      eapply (mult_lt_compat_l n m (S p)); auto.
    - assert (lt (p * n + k) (p * m)) by
          (apply IHp; try omega).
      omega.
  Qed.

  Lemma addPeekNone' :
    forall env n m,
      peekD env = Some m
      -> ~ lt (n + (pointerT2Nat m)) (pow2 14)
      -> peekD (addD env (n * 8)) = None.
  Proof.
    simpl; intros; subst.
    destruct (fst env); simpl in *; try discriminate.
    injections.
    find_if_inside; try reflexivity.
    unfold If_Opt_Then_Else.
    rewrite !wtl_div in *.
    elimtype False; apply H0.
    rewrite pointerT2Nat_Nat2pointerT in *;
      try (eapply pow2_div; eassumption).
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    destruct n; try omega.
    elimtype False; apply H0.
    simpl.
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    - eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      simpl in l.
      rewrite mult_pow2_8; simpl; omega.
    - rewrite mult_plus_distr_l.
      assert (8 <> 0) by omega.
      pose proof (NPeano.Nat.mul_div_le (wordToNat w) 8 H).
      apply le_lt_trans with (8 * S n + (wordToNat w)).
      omega.
      rewrite mult_pow2_8; simpl; omega.
  Qed.

  Lemma addPeekSome :
    forall env n m,
      peekD env = Some m
      -> lt (n + (pointerT2Nat m)) (pow2 14)
      -> exists p',
          peekD (addD env (n * 8)) = Some p'
          /\ pointerT2Nat p' = n + (pointerT2Nat m).
  Proof.
    simpl; intros; subst.
    destruct (fst env); simpl in *; try discriminate.
    injections.
    find_if_inside.
    - rewrite !wtl_div in *.
      rewrite pointerT2Nat_Nat2pointerT in *;
        try (eapply pow2_div; eassumption).
      unfold If_Opt_Then_Else.
      eexists; split; try reflexivity.
      rewrite wtl_div.
      rewrite wordToNat_natToWord_idempotent.
      rewrite pointerT2Nat_Nat2pointerT in *; try omega.
      rewrite NPeano.Nat.div_add; try omega.
      rewrite NPeano.Nat.div_add; try omega.
      apply Nomega.Nlt_in.
      rewrite Nnat.Nat2N.id, Npow2_nat; auto.
    - elimtype False; apply n0.
      rewrite !wtl_div in *.
      rewrite pointerT2Nat_Nat2pointerT in *.
      rewrite (NPeano.div_mod (wordToNat w) 8); try omega.
      pose proof (mult_pow2_8 14) as H'; simpl plus in H'; rewrite <- H'.
      replace (8 * NPeano.div (wordToNat w) 8 + NPeano.modulo (wordToNat w) 8 + n * 8)
      with (8 * (NPeano.div (wordToNat w) 8 + n) + NPeano.modulo (wordToNat w) 8)
        by omega.
      eapply mult_lt_compat_l''; try omega.
      apply NPeano.Nat.mod_upper_bound; omega.
      eapply (mult_lt_compat_l' _ _ 8); try omega.
      eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      rewrite mult_pow2_8; simpl.
      apply wordToNat_bound.
  Qed.

  Lemma addZeroPeek :
    forall xenv,
      peekD xenv = peekD (addD xenv 0).
  Proof.
    simpl; intros.
    destruct (fst xenv); simpl; eauto.
    find_if_inside; unfold If_Opt_Then_Else.
    rewrite <- plus_n_O, natToWord_wordToNat; auto.
    elimtype False; apply n.
    rewrite <- plus_n_O.
    apply wordToNat_bound.
  Qed.

  Local Opaque wordToNat.
  Local Opaque natToWord.

  Lemma boundPeekSome :
    forall env n m m',
      peekD env = Some m
      -> peekD (addD env (n * 8)) = Some m'
      -> lt (n + (pointerT2Nat m)) (pow2 14).
  Proof.
    simpl; intros; subst.
    destruct (fst env); simpl in *; try discriminate.
    injections.
    find_if_inside; unfold If_Opt_Then_Else in *; try congruence.
    injections.
    rewrite !wtl_div in *.
    rewrite pointerT2Nat_Nat2pointerT in *;
      try (eapply pow2_div; eassumption).
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    - rewrite mult_plus_distr_l.
      assert (8 <> 0) by omega.
      pose proof (NPeano.Nat.mul_div_le (wordToNat w) 8 H).
      apply le_lt_trans with (8 * n + (wordToNat w)).
      omega.
      rewrite mult_pow2_8.
      simpl plus at -1.
      omega.
  Qed.

  Lemma addPeekESome :
    forall env n m,
      peekE env = Some m
      -> lt (n + (pointerT2Nat m)) (pow2 14)%nat
      -> exists p',
          peekE (addE env (n * 8)) = Some p'
          /\ pointerT2Nat p' = n + (pointerT2Nat m).
  Proof.
        simpl; intros; subst.
    destruct (fst env); simpl in *; try discriminate.
    injections.
    find_if_inside.
    - rewrite !wtl_div in *.
      rewrite pointerT2Nat_Nat2pointerT in *;
        try (eapply pow2_div; eassumption).
      unfold If_Opt_Then_Else.
      eexists; split; try reflexivity.
      rewrite wtl_div.
      rewrite wordToNat_natToWord_idempotent.
      rewrite pointerT2Nat_Nat2pointerT in *; try omega.
      rewrite NPeano.Nat.div_add; try omega.
      rewrite NPeano.Nat.div_add; try omega.
      apply Nomega.Nlt_in.
      rewrite Nnat.Nat2N.id, Npow2_nat; auto.
    - elimtype False; apply n0.
      rewrite !wtl_div in *.
      rewrite pointerT2Nat_Nat2pointerT in *.
      rewrite (NPeano.div_mod (wordToNat w) 8); try omega.
      pose proof (mult_pow2_8 14) as H'; simpl plus in H'; rewrite <- H'.
      replace (8 * NPeano.div (wordToNat w) 8 + NPeano.modulo (wordToNat w) 8 + n * 8)
      with (8 * (NPeano.div (wordToNat w) 8 + n) + NPeano.modulo (wordToNat w) 8)
        by omega.
      eapply mult_lt_compat_l''; try omega.
      apply NPeano.Nat.mod_upper_bound; omega.
      eapply (mult_lt_compat_l' _ _ 8); try omega.
      eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      rewrite mult_pow2_8; simpl.
      apply wordToNat_bound.
  Qed.

  Lemma boundPeekESome :
    forall env n m m',
      peekE env = Some m
      -> peekE (addE env (n * 8)) = Some m'
      -> lt (n + (pointerT2Nat m)) (pow2 14).
  Proof.
    simpl; intros; subst.
    destruct (fst env); simpl in *; try discriminate.
    injections.
    find_if_inside; unfold If_Opt_Then_Else in *; try congruence.
    injections.
    rewrite !wtl_div in *.
    rewrite pointerT2Nat_Nat2pointerT in *;
      try (eapply pow2_div; eassumption).
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    - rewrite mult_plus_distr_l.
      assert (8 <> 0) by omega.
      pose proof (NPeano.Nat.mul_div_le (wordToNat w) 8 H).
      apply le_lt_trans with (8 * n + (wordToNat w)).
      omega.
      rewrite mult_pow2_8.
      simpl plus at -1.
      omega.
  Qed.

  Lemma addPeekENone :
      forall env n,
        peekE env = None
        -> peekE (addE env n) = None.
  Proof.
    simpl; intros.
    destruct (fst env); simpl in *; congruence.
  Qed.

  Lemma addPeekENone' :
    forall env n m,
      peekE env = Some m
      -> ~ lt (n + (pointerT2Nat m)) (pow2 14)%nat
      -> peekE (addE env (n * 8)) = None.
  Proof.
    simpl; intros; subst.
    destruct (fst env); simpl in *; try discriminate.
    injections.
    find_if_inside; try reflexivity.
    unfold If_Opt_Then_Else.
    rewrite !wtl_div in *.
    elimtype False; apply H0.
    rewrite pointerT2Nat_Nat2pointerT in *;
      try (eapply pow2_div; eassumption).
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    destruct n; try omega.
    elimtype False; apply H0.
    simpl.
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    - eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      simpl in l.
      rewrite mult_pow2_8; simpl; omega.
    - rewrite mult_plus_distr_l.
      assert (8 <> 0) by omega.
      pose proof (NPeano.Nat.mul_div_le (wordToNat w) 8 H).
      apply le_lt_trans with (8 * S n + (wordToNat w)).
      omega.
      rewrite mult_pow2_8; simpl; omega.
  Qed.

  Lemma addZeroPeekE :
    forall xenv,
      peekE xenv = peekE (addE xenv 0).
  Proof.
    simpl; intros.
    destruct (fst xenv); simpl; eauto.
    find_if_inside; unfold If_Opt_Then_Else.
    rewrite <- plus_n_O, natToWord_wordToNat; auto.
    elimtype False; apply n.
    rewrite <- plus_n_O.
    apply wordToNat_bound.
  Qed.

  Import Vectors.VectorDef.VectorNotations.

  Definition GoodCache (env : CacheDecode) :=
    forall domain p,
      getD env p = Some domain
      -> ValidDomainName domain
         /\ (String.length domain > 0)%nat
         /\ (getD env p = Some domain
             -> forall p' : pointerT, peekD env = Some p' -> lt (pointerT2Nat p) (pointerT2Nat p')).

  Lemma cacheIndependent_add
    : forall (b : nat) (cd : CacheDecode),
      GoodCache cd -> GoodCache (addD cd b).
  Proof.
    unfold GoodCache; intros.
    rewrite IndependentCaches in *;
      eapply H in H0; intuition eauto.
    simpl in *.
    destruct (fst cd); simpl in *; try discriminate.
    find_if_inside; simpl in *; try discriminate.
    injections.
    pose proof (H4 _ (eq_refl _)).
    eapply lt_le_trans; eauto.
    rewrite !pointerT2Nat_Nat2pointerT in *;
      rewrite !wtl_div in *.
    rewrite wordToNat_natToWord_idempotent.
    apply NPeano.Nat.div_le_mono; omega.
    apply Nomega.Nlt_in.
    rewrite Nnat.Nat2N.id, Npow2_nat; auto.
    eapply (mult_lt_compat_l' _ _ 8); try omega.
    + eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      rewrite wordToNat_natToWord_idempotent.
      rewrite mult_pow2_8; simpl; omega.
      apply Nomega.Nlt_in.
      rewrite Nnat.Nat2N.id, Npow2_nat; auto.
    + eapply (mult_lt_compat_l' _ _ 8); try omega.
      eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      rewrite mult_pow2_8; simpl; omega.
    + eapply (mult_lt_compat_l' _ _ 8); try omega.
      eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      rewrite mult_pow2_8; simpl; omega.
    + eapply (mult_lt_compat_l' _ _ 8); try omega.
      eapply le_lt_trans.
      apply NPeano.Nat.mul_div_le; omega.
      rewrite mult_pow2_8; simpl; omega.
  Qed.

  Lemma cacheIndependent_add_2
    : forall cd p (b : nat) domain,
      GoodCache cd
      -> getD (addD cd b) p = Some domain
      -> forall pre label post : string,
          domain = (pre ++ label ++ post)%string ->
          ValidLabel label -> (String.length label <= 63)%nat.
  Proof.
    unfold GoodCache; intros.
    rewrite IndependentCaches in *; eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_3
    : forall cd p (b : nat) domain,
      GoodCache cd
      -> getD (addD cd b) p = Some domain
      -> ValidDomainName domain.
  Proof.
    unfold GoodCache; intros.
    rewrite IndependentCaches in *; eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_4
    : forall cd p (b : nat) domain,
      GoodCache cd
      -> getD (addD cd b) p = Some domain
      -> gt (String.length domain) 0.
  Proof.
    unfold GoodCache; intros.
    rewrite IndependentCaches in *; eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_5
    : forall cd p domain,
      GoodCache cd
      -> getD cd p = Some domain
      -> ValidDomainName domain.
  Proof.
    unfold GoodCache; intros.
    eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_6
    : forall cd p domain,
      GoodCache cd
      -> getD cd p = Some domain
      -> gt (String.length domain) 0.
  Proof.
    unfold GoodCache; intros.
    eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_7
    : forall cd p domain,
      GoodCache cd
      -> getD cd p = Some domain
      -> forall pre label post : string,
          domain = (pre ++ label ++ post)%string ->
          ValidLabel label -> (String.length label <= 63)%nat.
  Proof.
    unfold GoodCache; intros.
    eapply H; eauto.
  Qed.

  Lemma ptr_eq_dec :
    forall (p p' : pointerT),
      {p = p'} + {p <> p'}.
  Proof.
    decide equality.
    apply weq.
    destruct a; destruct s; simpl in *.
    destruct (weq x x0); subst.
    left; apply ptr_eq; reflexivity.
    right; unfold not; intros; apply n.
    congruence.
  Qed.

  Lemma cacheIndependent_add_8
    : forall cd p p0 domain domain',
      GoodCache cd
      -> ValidDomainName domain' /\ (String.length domain' > 0)%nat
      -> getD (addD_G cd (domain', p0)) p = Some domain
      -> forall pre label post : string,
          domain = (pre ++ label ++ post)%string ->
          ValidLabel label -> (String.length label <= 63)%nat.
  Proof.
    unfold GoodCache; simpl; intros.
    destruct (pointerT_eq_dec p p0); subst.
    - injections; intuition.
      eapply H1; eauto.
    - eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_9
    : forall cd p p0 domain domain',
      GoodCache cd
      -> ValidDomainName domain' /\ (String.length domain' > 0)%nat
      -> getD (addD_G cd (domain', p0)) p = Some domain
      -> ValidDomainName domain.
  Proof.
    unfold GoodCache; simpl; intros.
    destruct (pointerT_eq_dec p p0); subst.
    - injections; intuition.
    - eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_10
    : forall cd p p0 domain domain',
      GoodCache cd
      -> ValidDomainName domain' /\ (String.length domain' > 0)%nat
      -> getD (addD_G cd (domain', p0)) p = Some domain
      -> gt (String.length domain) 0.
  Proof.
    unfold GoodCache; simpl; intros.
    destruct (pointerT_eq_dec p p0); subst.
    - injections; intuition.
    - eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_11
    : forall (b : nat)
             (cd : CacheDecode)
             (domain : string)
             (p : pointerT),
      GoodCache cd
      -> getD (addD cd b) p = Some domain ->
      forall p' : pointerT, peekD (addD cd b) = Some p' -> lt (pointerT2Nat p) (pointerT2Nat p').
  Proof.
    intros.
    eapply (cacheIndependent_add b) in H.
    eapply H; eauto.
  Qed.

  Lemma cacheIndependent_add_12
      : forall (p : pointerT) (cd : CacheDecode) (domain : string),
        GoodCache cd ->
        getD cd p = Some domain
        -> forall p' : pointerT,
            peekD cd = Some p'
            -> lt (pointerT2Nat p) (pointerT2Nat p').
    Proof.
      unfold GoodCache; simpl; intros; intuition eauto.
      eapply H; eauto.
    Qed.

    Lemma cacheIndependent_add_13
      : forall  (env : CacheDecode)
                (p : pointerT)
                (domain : string)
                (H : GoodCache env)
                (H0 : ValidDomainName domain /\ (String.length domain > 0)%nat)
                (H1 : getD env p = None)
                (H2 : forall p' : pointerT, peekD env = Some p' -> lt (pointerT2Nat p) (pointerT2Nat p'))
                (domain0 : string)
                (p0 : pointerT)
                (H3 : getD (addD_G env (domain, p)) p0 = Some domain0)
                (p' : pointerT),
        peekD (addD_G env (domain, p)) = Some p'
        -> lt (pointerT2Nat p0) (pointerT2Nat p').
    Proof.
      simpl; intros.
      destruct (fst env) eqn: ?; simpl in *; try discriminate.
      find_if_inside; subst.
      - injections.
        apply (H2 _ (eq_refl _)).
      - injections.
        pose proof (H2 _ (eq_refl _)).
        unfold GoodCache in *; intuition.
        eapply H; simpl.
        eassumption.
        eassumption.
        rewrite Heqo; simpl; reflexivity.
    Qed.

    Ltac solve_GoodCache_inv foo :=
    lazymatch goal with
      |- cache_inv_Property ?Z _ =>
      unify Z GoodCache;
      unfold cache_inv_Property; repeat split;
      eauto using cacheIndependent_add, cacheIndependent_add_2, cacheIndependent_add_4, cacheIndependent_add_6, cacheIndependent_add_7, cacheIndependent_add_8, cacheIndependent_add_10, cacheIndependent_add_11, cacheIndependent_add_12, cacheIndependent_add_13;
      try match goal with
            H : _ = _ |- _ =>
            try solve [ eapply cacheIndependent_add_3 in H; intuition eauto ];
            try solve [ eapply cacheIndependent_add_9 in H; intuition eauto ];
            try solve [ eapply cacheIndependent_add_5 in H; intuition eauto ]
          end;
      try solve [instantiate (1 := fun _ => True); exact I]
    end.

  Definition transformer : Transformer ByteString := ByteStringQueueTransformer.

  Opaque pow2. (* Don't want to be evaluating this. *)

  Lemma validDomainName_proj1_OK
    : forall domain,
      ValidDomainName domain
      -> decides true
                 (forall pre label post : string,
                     domain = (pre ++ label ++ post)%string ->
                     ValidLabel label -> (String.length label <= 63)%nat).
  Proof.
    simpl; intros; eapply H; eauto.
  Qed.

  Lemma validDomainName_proj2_OK
    : forall domain,
      ValidDomainName domain
      ->
      decides true
              (forall pre post : string,
                  domain = (pre ++ "." ++ post)%string ->
                  post <> ""%string /\
                  pre <> ""%string /\
                  ~ (exists s' : string, post = String "." s') /\
                  ~ (exists s' : string, pre = (s' ++ ".")%string)).
  Proof.
    simpl; intros; apply H; eauto.
  Qed.

  Hint Resolve validDomainName_proj1_OK : decide_data_invariant_db.
  Hint Resolve validDomainName_proj2_OK : decide_data_invariant_db.
  Hint Resolve FixedList_predicate_rest_True : data_inv_hints.

  Definition resourceRecord_OK (rr : resourceRecord) :=
    ith
      (icons (B := fun T => T -> Prop) (fun a : DomainName => ValidDomainName a)
      (icons (B := fun T => T -> Prop) (fun _ : Memory.W => True)
      (icons (B := fun T => T -> Prop) (fun a : DomainName => ValidDomainName a)
      (icons (B := fun T => T -> Prop) (fun a : SOA_RDATA =>
                                          (True /\ ValidDomainName a!"contact_email") /\ ValidDomainName a!"sourcehost") inil))))
      (SumType_index
         (DomainName
            :: (Memory.W : Type)
            :: DomainName
            :: [SOA_RDATA])
         rr!sRDATA)
      (SumType_proj
         (DomainName
            :: (Memory.W : Type)
            :: DomainName
            :: [SOA_RDATA])
         rr!sRDATA)
    /\ ValidDomainName rr!sNAME.

  Lemma resourceRecordOK_1
    : forall data : resourceRecord,
      resourceRecord_OK data -> (fun domain : string => ValidDomainName domain) data!sNAME.
  Proof.
    unfold resourceRecord_OK; intuition eauto.
  Qed.
  Hint Resolve resourceRecordOK_1 : data_inv_hints.

  Lemma resourceRecordOK_3
    : forall rr : resourceRecord,
      resourceRecord_OK rr ->
      ith
        (icons (B := fun T => T -> Prop) (fun a : DomainName => ValidDomainName a)
        (icons (B := fun T => T -> Prop) (fun _ : Memory.W => True)
        (icons (B := fun T => T -> Prop) (fun a : DomainName => ValidDomainName a)
        (icons (B := fun T => T -> Prop) (fun a : SOA_RDATA =>
                                                                 (True /\ ValidDomainName a!"contact_email") /\ ValidDomainName a!"sourcehost") inil))))        (SumType_index ResourceRecordTypeTypes rr!sRDATA)
        (SumType_proj ResourceRecordTypeTypes rr!sRDATA).
    intros ? H; apply H.
  Qed.
  Hint Resolve resourceRecordOK_3 : data_inv_hints.

  Lemma length_app_3 {A}
    : forall n1 n2 n3 (l1 l2 l3 : list A),
      length l1 = n1
      -> length l2 = n2
      -> length l3 = n3
      -> length (l1 ++ l2 ++ l3) = n1 + n2 + n3.
  Proof.
    intros; rewrite !app_length; subst; omega.
  Qed.
  Hint Resolve length_app_3 : data_inv_hints .

  Definition DNS_Packet_OK (data : packet) :=
    lt (|data!"answers" |) (pow2 16)
    /\ lt (|data!"authority" |) (pow2 16)
    /\ lt (|data!"additional" |) (pow2 16)
    /\ ValidDomainName (data!"question")!"qname"
    /\ forall (rr : resourceRecord),
        In rr (data!"answers" ++ data!"additional" ++ data!"authority")
        -> resourceRecord_OK rr.

  Ltac decompose_parsed_data :=
    repeat match goal with
           | H : (?x ++ ?y ++ ?z)%list = _ |- _ =>
             eapply firstn_skipn_self in H; try eassumption;
             destruct H as [? [? ?] ]
           | H : WS _ WO = _ |- _ =>
             apply (f_equal (@whd 0)) in H;
             simpl in H; rewrite H in *; clear H
           | H : length _ = _ |- _ => clear H
           end;
    subst.

  Lemma decides_resourceRecord_OK
    : forall l n m o,
      length l = n + m + o
      -> (forall x : resourceRecord, In x l -> resourceRecord_OK x)
      -> decides true
                 (forall rr : resourceRecord,
                     In rr
                        (firstn n l ++
                                firstn m (skipn n l) ++ firstn o (skipn (n + m) l)) ->
                     resourceRecord_OK rr).
  Proof.
    simpl; intros.
    rewrite firstn_skipn_self' in H1; eauto.
  Qed.

  Hint Resolve decides_resourceRecord_OK : decide_data_invariant_db .

  (* Resource Record <character-string>s are a byte, *)
  (* followed by that many characters. *)
  Definition encode_characterString_Spec (s : string) :=
    encode_nat_Spec 8 (String.length s)
                    ThenC encode_string_Spec s
                    DoneC.

  Definition encode_question_Spec (q : question) :=
    encode_DomainName_Spec q!"qname"
                           ThenC encode_enum_Spec QType_Ws q!"qtype"
                           ThenC encode_enum_Spec QClass_Ws q!"qclass"
                           DoneC.

  Definition encode_SOA_RDATA_Spec (soa : SOA_RDATA) :=
    encode_unused_word_Spec 16 (* Unusued RDLENGTH Field *)
                            ThenC encode_DomainName_Spec soa!"sourcehost"
                            ThenC encode_DomainName_Spec soa!"contact_email"
                            ThenC encode_word_Spec soa!"serial"
                            ThenC encode_word_Spec soa!"refresh"
                            ThenC encode_word_Spec soa!"retry"
                            ThenC encode_word_Spec soa!"expire"
                            ThenC encode_word_Spec soa!"minTTL"
                            DoneC.

  Definition encode_A_Spec (a : Memory.W) :=
    encode_unused_word_Spec 16 (* Unused RDLENGTH Field *)
                            ThenC encode_word_Spec a
                            DoneC.

  Definition encode_NS_Spec (domain : DomainName) :=
    encode_unused_word_Spec 16 (* Unused RDLENGTH Field *)
                            ThenC encode_DomainName_Spec domain
                            DoneC.

  Definition encode_CNAME_Spec (domain : DomainName) :=
    encode_unused_word_Spec 16 (* Unused RDLENGTH Field *)
                            ThenC encode_DomainName_Spec domain
                            DoneC.

  Definition encode_rdata_Spec :=
    encode_SumType_Spec ResourceRecordTypeTypes
                        (icons (encode_CNAME_Spec)  (* CNAME; canonical name for an alias 	[RFC1035] *)
                        (icons encode_A_Spec (* A; host address 	[RFC1035] *)
                        (icons (encode_NS_Spec) (* NS; authoritative name server 	[RFC1035] *)
                        (icons encode_SOA_RDATA_Spec  (* SOA rks the start of a zone of authority 	[RFC1035] *) inil)))).

  Definition encode_resource_Spec(r : resourceRecord) :=
    encode_DomainName_Spec r!sNAME
                           ThenC encode_enum_Spec RRecordType_Ws (RDataTypeToRRecordType r!sRDATA)
                           ThenC encode_enum_Spec RRecordClass_Ws r!sCLASS
                           ThenC encode_word_Spec r!sTTL
                           ThenC encode_rdata_Spec r!sRDATA
                           DoneC.

  Definition encode_packet_Spec (p : packet) :=
    encode_word_Spec p!"id"
                     ThenC encode_word_Spec (WS p!"QR" WO)
                     ThenC encode_enum_Spec Opcode_Ws p!"Opcode"
                     ThenC encode_word_Spec (WS p!"AA" WO)
                     ThenC encode_word_Spec (WS p!"TC" WO)
                     ThenC encode_word_Spec (WS p!"RD" WO)
                     ThenC encode_word_Spec (WS p!"RA" WO)
                     ThenC encode_word_Spec (WS false (WS false (WS false WO))) (* 3 bits reserved for future use *)
                     ThenC encode_enum_Spec RCODE_Ws p!"RCODE"
                     ThenC encode_nat_Spec 16 1 (* length of question field *)
                     ThenC encode_nat_Spec 16 (|p!"answers"|)
                     ThenC encode_nat_Spec 16 (|p!"authority"|)
                     ThenC encode_nat_Spec 16 (|p!"additional"|)
                     ThenC encode_question_Spec p!"question"
                     ThenC (encode_list_Spec encode_resource_Spec (p!"answers" ++ p!"additional" ++ p!"authority"))
                     DoneC.

  Ltac decode_DNS_rules g :=
    (* Processes the goal by either: *)
    lazymatch goal with
    | |- appcontext[encode_decode_correct_f _ _ _ _ encode_DomainName_Spec _ _ ] =>
      eapply (DomainName_decode_correct
                IndependentCaches IndependentCaches' IndependentCaches'''
                getDistinct getDistinct' addPeekSome
                boundPeekSome addPeekNone addPeekNone'
                addZeroPeek addPeekESome boundPeekESome
                addPeekENone addPeekENone' addZeroPeekE)
    | |- appcontext [encode_decode_correct_f _ _ _ _ (encode_list_Spec encode_resource_Spec) _ _] =>
      intros; apply FixList_decode_correct with (A_predicate := resourceRecord_OK)
    end.

  Lemma addD_addD_plus :
    forall (cd : CacheDecode) (n m : nat), addD (addD cd n) m = addD cd (n + m).
    simpl; intros.
    destruct (fst cd); simpl; eauto.
    repeat (find_if_inside; simpl); eauto.
    f_equal; f_equal.
    rewrite !natToWord_plus.
    rewrite !natToWord_wordToNat.
    rewrite wplus_assoc; reflexivity.
    rewrite !natToWord_plus in l0.
    rewrite !natToWord_wordToNat in l0.
    elimtype False.
    apply n0.
    rewrite <- (natToWord_wordToNat w) in l0.
    rewrite <- natToWord_plus in l0.
    rewrite wordToNat_natToWord_idempotent in l0.
    omega.
    apply Nomega.Nlt_in; rewrite Nnat.Nat2N.id, Npow2_nat; assumption.
    elimtype False.
    apply n0.
    rewrite <- (natToWord_wordToNat w).
    rewrite !natToWord_plus.
    rewrite !wordToNat_natToWord_idempotent.
    rewrite <- natToWord_plus.
    rewrite !wordToNat_natToWord_idempotent.
    omega.
    apply Nomega.Nlt_in; rewrite Nnat.Nat2N.id, Npow2_nat; assumption.
    apply Nomega.Nlt_in; rewrite Nnat.Nat2N.id, Npow2_nat; omega.
    omega.
  Qed.

Ltac synthesize_decoder_ext
     transformer
     decode_step'
     determineHooks
     synthesize_cache_invariant' :=
  (* Combines tactics into one-liner. *)
  start_synthesizing_decoder;
  [ normalize_compose transformer;
    repeat first [decode_step' idtac | decode_step determineHooks]
  | cbv beta; synthesize_cache_invariant' idtac
  |  ].

Definition ByteAlignedCorrectDecoderFor {A} {cache : Cache}
           Invariant FormatSpec :=
  { decodePlusCacheInv |
      exists P_inv,
        (cache_inv_Property (snd decodePlusCacheInv) P_inv
         -> encode_decode_correct_f (A := A) cache transformer Invariant (fun _ _ => True)
                                    FormatSpec
                                    (fst decodePlusCacheInv)
                                    (snd decodePlusCacheInv))
        /\ cache_inv_Property (snd decodePlusCacheInv) P_inv}.

  Arguments split1' : simpl never.
  Arguments split2' : simpl never.
  Arguments weq : simpl never.
  Arguments word_indexed : simpl never.

  Definition packet_decoder
    : CorrectDecoderFor DNS_Packet_OK encode_packet_Spec.
  Proof.
    synthesize_decoder_ext transformer
                           decode_DNS_rules
                           decompose_parsed_data
                           solve_GoodCache_inv.
    unfold resourceRecord_OK.
    clear; intros.
    apply (proj2 H).
    simpl.
    simpl; intros;
      repeat (try rewrite !DecodeBindOpt2_assoc;
              try rewrite !Bool.andb_true_r;
              try rewrite !Bool.andb_true_l;
              try rewrite !optimize_if_bind2;
              try rewrite !optimize_if_bind2_bool).

    first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
    unfold decode_enum at 1.
    repeat (try rewrite !DecodeBindOpt2_assoc;
            try rewrite !Bool.andb_true_r;
            try rewrite !Bool.andb_true_l;
            try rewrite !optimize_if_bind2;
            try rewrite !optimize_if_bind2_bool).
    etransitivity.
    first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
    rewrite !DecodeBindOpt2_assoc.
    first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
    rewrite (If_Opt_Then_Else_DecodeBindOpt_swap (cache := dns_list_cache)).
    first [ apply DecodeBindOpt2_under_bind; simpl; intros
          | eapply optimize_under_if_bool; simpl; intros
          | eapply optimize_under_if; simpl; intros].
    rewrite (If_Opt_Then_Else_DecodeBindOpt_swap (cache := dns_list_cache)).
    first [ apply DecodeBindOpt2_under_bind; simpl; intros
          | eapply optimize_under_if_bool; simpl; intros
          | eapply optimize_under_if; simpl; intros].
    rewrite (If_Opt_Then_Else_DecodeBindOpt_swap (cache := dns_list_cache)).
    first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
    rewrite (If_Opt_Then_Else_DecodeBindOpt_swap (cache := dns_list_cache)).
  first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
  rewrite (If_Opt_Then_Else_DecodeBindOpt_swap (cache := dns_list_cache)).
  first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
  etransitivity.
  first [ apply DecodeBindOpt2_under_bind; simpl; intros
            | eapply optimize_under_if_bool; simpl; intros
            | eapply optimize_under_if; simpl; intros].
  rewrite (If_Then_Else_Bind (cache := dns_list_cache)).
  unfold decode_enum at 1.
  repeat (try rewrite !DecodeBindOpt2_assoc;
          try rewrite !Bool.andb_true_r;
          try rewrite !Bool.andb_true_l;
          try rewrite !optimize_if_bind2;
          try rewrite !optimize_if_bind2_bool).
  higher_order_reflexivity.
  set_refine_evar.
  rewrite (If_Opt_Then_Else_DecodeBindOpt_swap (cache := dns_list_cache)).
  unfold H; higher_order_reflexivity.
  collapse_word addD_addD_plus.
  collapse_word addD_addD_plus.
  collapse_word addD_addD_plus.
  collapse_word addD_addD_plus.
  first [ apply DecodeBindOpt2_under_bind; simpl; intros
        | eapply optimize_under_if_bool; simpl; intros
        | eapply optimize_under_if; simpl; intros].
  collapse_word addD_addD_plus.
  collapse_word addD_addD_plus.
  simpl.
  higher_order_reflexivity.
  Defined.

  Definition packetDecoderImpl
    := Eval simpl in (projT1 packet_decoder).

  Lemma AlignedDecodeChar {C}
        {numBytes}
    : forall (v : Vector.t (word 8) (S numBytes))
             (k : (word 8) -> ByteString -> CacheDecode -> option (C * ByteString * CacheDecode))
             cd,
    (`(a, b0, d) <- decode_word
      (transformerUnit := ByteString_QueueTransformerOpt) (sz := 8) (build_aligned_ByteString v) cd;
       k a b0 d) =
    Let n := (Vector.nth v Fin.F1) in
        k n (build_aligned_ByteString (snd (Vector_split 1 _ v))) (addD cd 8).
Proof.
  unfold LetIn; intros.
  unfold decode_word, WordOpt.decode_word.
  rewrite aligned_decode_char_eq; simpl.
  f_equal.
  pattern numBytes, v; apply Vector.caseS; simpl; intros.
  reflexivity.
Qed.

Lemma AlignedDecode2Char {C}
        {numBytes}
    : forall (v : Vector.t (word 8) (S (S numBytes)))
             (k : (word 16) -> ByteString -> CacheDecode -> option (C * ByteString * CacheDecode))
             cd,
    (`(a, b0, d) <- decode_word
      (transformerUnit := ByteString_QueueTransformerOpt) (sz := 16) (build_aligned_ByteString v) cd;
       k a b0 d) =
    Let n := Core.append_word (Vector.nth v (Fin.FS Fin.F1)) (Vector.nth v Fin.F1) in
        k n (build_aligned_ByteString (snd (Vector_split 2 _ v))) (addD cd 16).
Proof.
  unfold LetIn; intros.
  unfold decode_word, WordOpt.decode_word.
  match goal with
    |- context[Ifopt ?Z as _ Then _ Else _] => replace Z with
                                               (let (v', v'') := Vector_split 2 numBytes v in Some (VectorByteToWord v', build_aligned_ByteString v'')) by (symmetry; apply (@aligned_decode_char_eq' _ 1 v))
  end.
  unfold Vector_split, If_Opt_Then_Else, DecodeBindOpt2 at 1, If_Opt_Then_Else.
  f_equal.
  rewrite !Vector_nth_tl, !Vector_nth_hd.
  erewrite VectorByteToWord_cons.
  rewrite <- !Eqdep_dec.eq_rect_eq_dec; eauto using Peano_dec.eq_nat_dec.
  f_equal.
  erewrite VectorByteToWord_cons.
  rewrite <- !Eqdep_dec.eq_rect_eq_dec; eauto using Peano_dec.eq_nat_dec.
  Grab Existential Variables.
  omega.
  omega.
Qed.

Corollary AlignedDecode2Nat {C}
        {numBytes}
    : forall (v : Vector.t (word 8) (S (S numBytes)))
             (k : nat -> ByteString -> CacheDecode -> option (C * ByteString * CacheDecode))
             cd,
    (`(a, b0, d) <- decode_nat
      (transformerUnit := ByteString_QueueTransformerOpt) 16 (build_aligned_ByteString v) cd;
       k a b0 d) =
    Let n := wordToNat (Core.append_word (Vector.nth v (Fin.FS Fin.F1)) (Vector.nth v Fin.F1)) in
        k n (build_aligned_ByteString (snd (Vector_split 2 _ v))) (addD cd 16).
Proof.
  unfold decode_nat; intros.
  rewrite DecodeBindOpt2_assoc.
  unfold DecodeBindOpt2 at 2, If_Opt_Then_Else.
  rewrite AlignedDecode2Char.
  reflexivity.
Qed.

Lemma optimize_under_if_opt {A ResultT}
  : forall (a_opt : option A) (t t' : A -> ResultT) (e e' : ResultT),
    (forall a, t a = t' a) -> e = e' ->
    Ifopt a_opt as a Then t a Else e = Ifopt a_opt as a Then t' a Else e'.
Proof.
  intros; subst; eauto.
  destruct a_opt; eauto.
Qed.

Lemma rewrite_under_LetIn
      {A B}
  : forall (a : A) (k k' : A -> B),
    (forall a, k a = k' a) -> LetIn a k = LetIn a k'.
Proof.
  intros; unfold LetIn; eauto.
Qed.

Fixpoint Guarded_Vector_split
         (sz n : nat)
         {struct sz}
  : Vector.t (word 8) n
    -> Vector.t (word 8) (sz + (n - sz)) :=
  match sz, n return
        Vector.t _ n
        -> Vector.t (word 8) (sz + (n - sz))
  with
  | 0, _ => fun v => (eq_rect _ (Vector.t _) v _ (minus_n_O n))
  | S n', 0 =>
    fun v =>
      Vector.cons _ (wzero _) _ (Guarded_Vector_split n' _ v)
  | S n', S sz' =>
    fun v =>
      Vector.cons _ (Vector.hd v) _ (Guarded_Vector_split n' _ (Vector.tl v))
  end .

Lemma le_B_Guarded_Vector_split
      {n}
      (b : Vector.t _ n)
      (m : nat)
  : {b' : ByteString | le_B b' (build_aligned_ByteString b)}.
  eexists (build_aligned_ByteString
             (snd (Vector_split _ _ (Guarded_Vector_split m n b)))).
  abstract (unfold build_aligned_ByteString, le_B; simpl; omega).
Defined.

Lemma Decode_w_Measure_le_eq'':
  forall (A B : Type) (cache : Cache) (transformer : Transformer B)
         (A_decode : B -> CacheDecode -> option (A * B * CacheDecode))
         (b : B) (cd : CacheDecode)
         (A_decode_le : forall (b0 : B) (cd0 : CacheDecode) (a : A) (b' : B) (cd' : CacheDecode),
             A_decode b0 cd0 = Some (a, b', cd') -> le_B b' b0),
    Decode_w_Measure_le A_decode b cd A_decode_le = None ->
    A_decode b cd = None.
Proof.
  clear; intros ? ? ? ? ? ? ? ?; unfold Decode_w_Measure_le in *.
  remember (A_decode_le b cd); clear Heql.
  destruct (A_decode b cd) as [ [ [? ?] ? ] | ]; eauto.
  intros; discriminate.
Qed.

Lemma build_aligned_ByteString_eq_split
  : forall m n b H0,
    (m <= n)%nat
    -> build_aligned_ByteString b =
       (build_aligned_ByteString (eq_rect (m + (n - m)) (t (word 8)) (Guarded_Vector_split m n b) n H0)).
Proof.
  intros.
  intros; eapply ByteString_f_equal; simpl.
  instantiate (1 := eq_refl _); reflexivity.
  instantiate (1 := eq_refl _).
  simpl.
  revert n b H0 H; induction m; simpl.
  intros ? ?; generalize (minus_n_O n).
  intros; rewrite <- Equality.transport_pp.
  apply Eqdep_dec.eq_rect_eq_dec; auto with arith.
  intros.
  inversion H; subst.
  - revert b H0 IHm; clear.
    intro; pattern m, b; apply Vector.caseS; simpl; intros.
    assert ((n + (n - n)) = n) by omega.
    rewrite eq_rect_Vector_cons with (H' := H).
    f_equal.
    erewrite <- IHm; eauto.
  - revert b H0 IHm H1; clear.
    intro; pattern m0, b; apply Vector.caseS; simpl; intros.
    assert ((m + (n - m)) = n) by omega.
    erewrite eq_rect_Vector_cons with (H' := H).
    f_equal.
    erewrite <- IHm; eauto.
    omega.
Qed.

Lemma ByteAlign_Decode_w_Measure_le {A}
  : forall (dec_a : ByteString -> CacheDecode -> option (A * ByteString * CacheDecode))
           (n m : nat)
           (dec_a' : Vector.t (word 8) (m + (n - m)) -> A)
           (cd : CacheDecode)
           (f : CacheDecode -> CacheDecode)
           (b : Vector.t (word 8) n)
           decode_a_le
           (dec_fail : ~ (m <= n)%nat
                       -> forall b cd, dec_a (build_aligned_ByteString (numBytes := n) b) cd = None),
    (forall b cd, dec_a (build_aligned_ByteString b) cd =
                  Some (dec_a' b, build_aligned_ByteString (snd (Vector_split m (n - m) b)), f cd))
    -> Decode_w_Measure_le dec_a (build_aligned_ByteString b) cd decode_a_le =
       match Compare_dec.le_dec m n with
       | left e => (Let a := dec_a' (Guarded_Vector_split m n b) in
                        Some (a, le_B_Guarded_Vector_split b m, f cd))
       | right _ => None
       end.
Proof.
  intros.
  destruct (Compare_dec.le_dec m n).
  assert (m + (n - m) = n) by omega.
  assert (forall b, Decode_w_Measure_le dec_a (build_aligned_ByteString b) cd decode_a_le
                    = Decode_w_Measure_le dec_a (build_aligned_ByteString ( eq_rect _ _ (Guarded_Vector_split m n b) _ H0)) cd decode_a_le).
  { revert l; clear; intros.
    destruct (Decode_w_Measure_le dec_a (build_aligned_ByteString b) cd decode_a_le)
      as [ [ [? [? ?] ] ?] | ] eqn: ?.
    apply Decode_w_Measure_le_eq' in Heqo.
    simpl in Heqo.
    destruct (Decode_w_Measure_le dec_a
                                  (build_aligned_ByteString (eq_rect (m + (n - m)) (t (word 8)) (Guarded_Vector_split m n b) n H0)) cd decode_a_le) as [ [ [? [? ?] ] ?] | ] eqn: ?.
    apply Decode_w_Measure_le_eq' in Heqo0.
    simpl in *.
    rewrite <- build_aligned_ByteString_eq_split in Heqo0 by eauto.
    rewrite Heqo0 in Heqo.
    injection Heqo; intros.
    rewrite H, H2;
      repeat f_equal.
    revert l0 l1. rewrite H1; intros; f_equal.
    f_equal; apply Core.le_uniqueness_proof.
    apply ByteString_id.
    eapply Decode_w_Measure_le_eq'' in Heqo0.
    rewrite <- build_aligned_ByteString_eq_split in Heqo0 by eauto.
    rewrite Heqo0 in Heqo.
    discriminate.
    apply ByteString_id.
    erewrite build_aligned_ByteString_eq_split in Heqo by eauto.
    rewrite Heqo; reflexivity.
  }
  rewrite H1.
  match goal with
    |- ?a = _ => destruct a as [ [ [? ?] ? ] | ] eqn: ?
  end.
  eapply Decode_w_Measure_le_eq' in Heqo.
  assert (dec_a (build_aligned_ByteString (Guarded_Vector_split m n b)) cd
          = Some (a, projT1 s, c)).
  { destruct s; simpl in *.
    rewrite <- Heqo.
    unfold build_aligned_ByteString; repeat f_equal; simpl.
    eapply ByteString_f_equal; simpl.
    instantiate (1 := eq_refl _); reflexivity.
    instantiate (1 := sym_eq H0).
    clear H1.
    destruct H0; reflexivity.
  }
  rewrite H in H2; injection H2; intros.
  rewrite H3, H5; unfold LetIn; simpl.
  repeat f_equal.
  destruct s; simpl in *.
  unfold le_B_Guarded_Vector_split; simpl.
  clear H1; revert l0.
  rewrite <- H4; intros.
  f_equal; apply Core.le_uniqueness_proof.
  apply ByteString_id.
  apply Decode_w_Measure_le_eq'' in Heqo.
  pose proof (H (Guarded_Vector_split m n b) cd).
  assert (Some (dec_a' (Guarded_Vector_split m n b),
                build_aligned_ByteString (snd (Vector_split m (n - m) (Guarded_Vector_split m n b))),
                f cd) = None).
  { rewrite <- Heqo.
    rewrite <- H.
    repeat f_equal.
    eapply ByteString_f_equal; simpl.
    instantiate (1 := eq_refl _); reflexivity.
    instantiate (1 := sym_eq H0).
    clear H1.
    destruct H0; reflexivity.
  }
  discriminate.
  eapply dec_fail in n0; simpl.
  eapply Specs.Decode_w_Measure_le_eq' in n0.
  apply n0.
Qed.

Lemma lt_B_Guarded_Vector_split
      {n}
      (b : Vector.t _ n)
      (m : nat)
      (m_OK : lt 0 m)
      (_ : ~ lt n m)
  : {b' : ByteString | lt_B b' (build_aligned_ByteString b)}.
  eexists (build_aligned_ByteString
             (snd (Vector_split _ _ (Guarded_Vector_split m n b)))).
  abstract (unfold build_aligned_ByteString, lt_B; simpl; omega).
Defined.

Lemma Decode_w_Measure_lt_eq'':
  forall (A B : Type) (cache : Cache) (transformer : Transformer B)
         (A_decode : B -> CacheDecode -> option (A * B * CacheDecode))
         (b : B) (cd : CacheDecode)
         (A_decode_lt : forall (b0 : B) (cd0 : CacheDecode) (a : A) (b' : B) (cd' : CacheDecode),
             A_decode b0 cd0 = Some (a, b', cd') -> lt_B b' b0),
    Decode_w_Measure_lt A_decode b cd A_decode_lt = None ->
    A_decode b cd = None.
Proof.
  clear; intros ? ? ? ? ? ? ? ?; unfold Decode_w_Measure_lt in *.
  remember (A_decode_lt b cd); clear Heql.
  destruct (A_decode b cd) as [ [ [? ?] ? ] | ]; eauto.
  discriminate.
Qed.

Arguments Guarded_Vector_split : simpl never.

  Fixpoint BytesToString {sz}
             (b : Vector.t (word 8) sz)
    : string :=
    match b with
    | Vector.nil => EmptyString
    | Vector.cons a _ b' => String (Ascii.ascii_of_N (wordToN a)) (BytesToString b')
    end.

  Arguments addD : simpl never.

  Lemma decode_string_aligned_ByteString
        {sz sz'}
    : forall (b : t (word 8) (sz + sz'))
        (cd : CacheDecode),
  FixStringOpt.decode_string sz (build_aligned_ByteString b) cd =
  Some (BytesToString (fst (Vector_split sz sz' b)),
        build_aligned_ByteString (snd (Vector_split sz sz' b)),
        addD cd (8 * sz)).
  Proof.
    induction sz; intros.
    - simpl; repeat f_equal.
      destruct cd as [ [? | ] ? ]; unfold addD; simpl.
      pose proof (wordToNat_bound w); find_if_inside; try omega.
      rewrite plus_comm; simpl; rewrite natToWord_wordToNat; reflexivity.
      reflexivity.
    - simpl.
      assert (forall A n b, exists a b', b = Vector.cons A a n b')
             by (clear; intros; pattern n, b; apply caseS; eauto).
      destruct (H _ _ b) as [? [? ?] ]; subst; simpl.
      unfold AsciiOpt.decode_ascii.
      rewrite DecodeBindOpt2_assoc; simpl.
      etransitivity.
      rewrite AlignedDecodeChar; simpl.
      rewrite IHsz. higher_order_reflexivity.
      simpl.
      destruct (Vector_split sz sz' x0); simpl.
      unfold LetIn.
      rewrite addD_addD_plus;
        repeat f_equal.
      omega.
  Qed.

  Lemma decode_string_aligned_ByteString_overflow
        {sz}
    : forall {sz'}
             (b : t (word 8) sz')
             (cd : CacheDecode),
             lt sz' sz
             -> FixStringOpt.decode_string sz (build_aligned_ByteString b) cd = None.
  Proof.
    induction sz; intros.
    - omega.
    - simpl.
      assert (forall A n b, exists a b', b = Vector.cons A a n b')
             by (clear; intros; pattern n, b; apply caseS; eauto).
      destruct sz'.
      + reflexivity.
      + destruct (H0 _ _ b) as [? [? ?] ]; subst; simpl.
        unfold AsciiOpt.decode_ascii.
        rewrite DecodeBindOpt2_assoc; simpl.
        etransitivity.
        rewrite AlignedDecodeChar; simpl.
        rewrite IHsz. higher_order_reflexivity.
        omega.
        reflexivity.
  Qed.

Lemma ByteAlign_Decode_w_Measure_lt {A}
  : forall (dec_a : nat -> ByteString -> CacheDecode -> option (A * ByteString * CacheDecode))
           (n m : nat)
           (dec_a' : forall m n, Vector.t (word 8) (m + n) -> A)
           (cd : CacheDecode)
           (f : nat -> CacheDecode -> CacheDecode)
           (b : Vector.t (word 8) n)
           (m_OK : lt 0 m)
           decode_a_le
           (dec_fail : (lt n m)%nat
                       -> forall b cd, dec_a m (build_aligned_ByteString (numBytes := n) b) cd = None),
    (forall n m b cd, dec_a m (build_aligned_ByteString b) cd =
                      Some (dec_a' _ _ b, build_aligned_ByteString (snd (Vector_split m n b)), f m cd))
    -> Decode_w_Measure_lt (dec_a m) (build_aligned_ByteString b) cd decode_a_le =
       match Compare_dec.lt_dec n m with
       | left _ => None
       | right n' => (Let a := dec_a' _ _ (Guarded_Vector_split m n b) in
                         Some (a, lt_B_Guarded_Vector_split b m m_OK n' , f m cd))
       end.
Proof.
  intros.
  destruct (Compare_dec.lt_dec m n);
    destruct (Compare_dec.lt_dec n m); try omega.
  - assert (m + (n - m) = n) by omega.
    assert (forall b, Decode_w_Measure_lt (dec_a m) (build_aligned_ByteString b) cd decode_a_le
                      = Decode_w_Measure_lt (dec_a m)(build_aligned_ByteString ( eq_rect _ _ (Guarded_Vector_split m n b) _ H0)) cd decode_a_le).
    { revert l; clear; intros.
      destruct (Decode_w_Measure_lt (dec_a m) (build_aligned_ByteString b) cd decode_a_le)
        as [ [ [? [? ?] ] ?] | ] eqn: ?.
      apply Decode_w_Measure_lt_eq' in Heqo.
      simpl in Heqo.
      destruct (Decode_w_Measure_lt (dec_a m)
                                    (build_aligned_ByteString (eq_rect _ (t (word 8)) (Guarded_Vector_split m n b) n H0)) cd decode_a_le) as [ [ [? [? ?] ] ?] | ] eqn: ?.
      apply Decode_w_Measure_lt_eq' in Heqo0.
      unfold proj1_sig in Heqo0.
      rewrite <- build_aligned_ByteString_eq_split in Heqo0.
      rewrite Heqo0 in Heqo.
      injection Heqo; intros.
      rewrite H, H2;
        repeat f_equal.
      revert l1 l0. rewrite H1; intros; f_equal.
      f_equal; apply Core.le_uniqueness_proof.
      omega.
      apply ByteString_id.
      eapply Decode_w_Measure_lt_eq'' in Heqo0.
      rewrite <- build_aligned_ByteString_eq_split in Heqo0 by omega.
      rewrite Heqo0 in Heqo.
      discriminate.
      apply ByteString_id.
      erewrite (build_aligned_ByteString_eq_split m n) in Heqo by omega.
      rewrite Heqo; reflexivity.
    }
    rewrite H1.
    match goal with
      |- ?a = _ => destruct a as [ [ [? ?] ? ] | ] eqn: ?
    end.
    eapply Decode_w_Measure_lt_eq' in Heqo.
    assert (dec_a m (build_aligned_ByteString (Guarded_Vector_split m n b)) cd
            = Some (a, projT1 s, c)).
    { destruct s; simpl in *.
      rewrite <- Heqo.
      unfold build_aligned_ByteString; repeat f_equal; simpl.
      eapply ByteString_f_equal; simpl.
      instantiate (1 := eq_refl _); reflexivity.
      instantiate (1 := sym_eq H0).
      clear H1.
      destruct H0; reflexivity.
    }
    rewrite H in H2; injection H2; intros.
    rewrite H3, H5; unfold LetIn; simpl.
    repeat f_equal.
    destruct s; simpl in *.
    unfold lt_B_Guarded_Vector_split; simpl.
    clear H1; revert l0.
    rewrite <- H4; intros.
    f_equal. apply Core.le_uniqueness_proof.
    apply ByteString_id.
    apply Decode_w_Measure_lt_eq'' in Heqo.
    pose proof (H _ _ (Guarded_Vector_split m n b) cd).
    assert (Some (dec_a' _ _ (Guarded_Vector_split m n b),
                  build_aligned_ByteString (snd (Vector_split m (n - m) (Guarded_Vector_split m n b))),
                  f m cd) = None).
    { rewrite <- Heqo.
      rewrite <- H.
      repeat f_equal.
      eapply ByteString_f_equal; simpl.
      instantiate (1 := eq_refl _); reflexivity.
      instantiate (1 := sym_eq H0).
      clear H1.
      destruct H0; reflexivity.
    }
    discriminate.
  - eapply dec_fail in l; simpl.
    eapply Specs.Decode_w_Measure_lt_eq' in l.
    apply l.
  - assert (m = n) by omega; subst.
    assert (n + (n - n) = n) by omega.
    assert (forall b, Decode_w_Measure_lt (dec_a n) (build_aligned_ByteString b) cd decode_a_le
                      = Decode_w_Measure_lt (dec_a n)(build_aligned_ByteString ( eq_rect _ _ (Guarded_Vector_split n n b) _ H0)) cd decode_a_le).
    { clear; intros.
      destruct (Decode_w_Measure_lt (dec_a n) (build_aligned_ByteString b) cd decode_a_le)
        as [ [ [? [? ?] ] ?] | ] eqn: ?.
      apply Decode_w_Measure_lt_eq' in Heqo.
      simpl in Heqo.
      destruct (Decode_w_Measure_lt (dec_a n)
                                    (build_aligned_ByteString (eq_rect _ (t (word 8)) (Guarded_Vector_split n n b) n H0)) cd decode_a_le) as [ [ [? [? ?] ] ?] | ] eqn: ?.
    apply Decode_w_Measure_lt_eq' in Heqo0.
    unfold proj1_sig in Heqo0.
    rewrite <- build_aligned_ByteString_eq_split in Heqo0.
    rewrite Heqo0 in Heqo.
    injection Heqo; intros.
    rewrite H, H2;
      repeat f_equal.
    revert l l0. rewrite H1; intros; f_equal.
    f_equal; apply Core.le_uniqueness_proof.
    omega.
    apply ByteString_id.
    eapply Decode_w_Measure_lt_eq'' in Heqo0.
    rewrite <- build_aligned_ByteString_eq_split in Heqo0 by omega.
    rewrite Heqo0 in Heqo.
    discriminate.
    apply ByteString_id.
    erewrite (build_aligned_ByteString_eq_split n n) in Heqo by omega.
    rewrite Heqo; reflexivity.
  }
  rewrite H1.
  match goal with
    |- ?a = _ => destruct a as [ [ [? ?] ? ] | ] eqn: ?
  end.
  eapply Decode_w_Measure_lt_eq' in Heqo.
  assert (dec_a n (build_aligned_ByteString (Guarded_Vector_split n n b)) cd
          = Some (a, projT1 s, c)).
  { destruct s; simpl in *.
    rewrite <- Heqo.
    unfold build_aligned_ByteString; repeat f_equal; simpl.
    eapply ByteString_f_equal; simpl.
    instantiate (1 := eq_refl _); reflexivity.
    instantiate (1 := sym_eq H0).
    clear H1.
    destruct H0; reflexivity.
  }
  rewrite H in H2; injection H2; intros.
  rewrite H3, H5; unfold LetIn; simpl.
  repeat f_equal.
  destruct s; simpl in *.
  unfold lt_B_Guarded_Vector_split; simpl.
  clear H1; revert l.
  rewrite <- H4; intros.
  f_equal. apply Core.le_uniqueness_proof.
  apply ByteString_id.
  apply Decode_w_Measure_lt_eq'' in Heqo.
  pose proof (H _ _ (Guarded_Vector_split n n b) cd).
  assert (Some (dec_a' _ _ (Guarded_Vector_split n n b),
                build_aligned_ByteString (snd (Vector_split n (n - n) (Guarded_Vector_split n n b))),
                f n cd) = None).
  { rewrite <- Heqo.
    rewrite <- H.
    repeat f_equal.
    eapply ByteString_f_equal; simpl.
    instantiate (1 := eq_refl _); reflexivity.
    instantiate (1 := sym_eq H0).
    clear H1.
    destruct H0; reflexivity.
  }
  discriminate.
Qed.

  Lemma optimize_If_bind2_bool {A A' B B' C}
    : forall (c : bool)
             (t e : option (A * B * C))
             (k : A -> B -> C -> option (A' * B' * C)),
      (`(a, b, env) <- (If c Then t Else e); k a b env) =
      If c Then `(a, b, env) <- t; k a b env Else (`(a, b, env) <- e; k a b env).
  Proof.
    destruct c; simpl; intros; reflexivity.
  Qed.

  Lemma optimize_under_match {A B} {P}
    : forall (a a' : A) (f : {P a a'} + {~P a a'}) (t t' : _ -> B)
             (e e' : _ -> B),
      (forall (a a' : A) (a_eq : _), t a_eq = t' a_eq)
      -> (forall (a a' : A) (a_neq : _), e a_neq = e' a_neq)
      -> match f with
          | left e => t e
          | right n => e n
         end =
         match f with
         | left e => t' e
         | right n => e' n
         end.
  Proof.
    destruct f; simpl; intros; eauto.
  Qed.

Lemma optimize_Fix {A}
  : forall
    (body : forall x : ByteString,
        (forall y : ByteString,
            lt_B y x -> (fun _ : ByteString => CacheDecode -> option (A * ByteString * CacheDecode)) y) ->
        (fun _ : ByteString => CacheDecode -> option (A * ByteString * CacheDecode)) x)
    (body' : forall x : nat,
        (forall y : nat,
            (lt y x)%nat ->
            (fun m : nat =>
               t (word 8) m -> CacheDecode ->
               option (A * {n : _ & Vector.t _ n} * CacheDecode)) y) ->
        t (word 8) x -> CacheDecode -> option (A * {n : _ & Vector.t _ n} * CacheDecode) )
    n (b : Vector.t _ n) (cd : CacheDecode)
    (body_Proper :
       forall (x0 : ByteString)
              (f g : forall y : ByteString, lt_B y x0 -> CacheDecode -> option (A * ByteString * CacheDecode)),
         (forall (y : ByteString) (p : lt_B y x0), f y p = g y p) -> body x0 f = body x0 g)
    (body'_Proper :
       forall (x0 : nat)
              (f
                 g : forall y : nat,
                  (lt y x0)%nat -> t (word 8) y -> CacheDecode -> option (A * {n0 : nat & t Core.char n0} * CacheDecode)),
         (forall (y : nat) (p : (lt y x0)%nat), f y p = g y p) -> body' x0 f = body' x0 g)
  ,
    (forall n (b : Vector.t (word 8) n)
            (rec : forall x : ByteString,
                lt_B x (build_aligned_ByteString b) -> CacheDecode -> option (A * ByteString * CacheDecode))
            (rec' : forall x : nat,
                (lt x n)%nat -> t Core.char x -> CacheDecode ->
                option (A * {n : _ & Vector.t _ n} * CacheDecode))
            cd,
        (forall m cd b a b' cd' b_lt b_lt' ,
            rec' m b_lt' b cd = Some (a, b', cd')
            -> rec (build_aligned_ByteString b) b_lt cd = Some (a, build_aligned_ByteString (projT2 b'), cd'))
        -> (forall m cd b b_lt b_lt' ,
            rec' m b_lt' b cd = None
            -> rec (build_aligned_ByteString b) b_lt cd = None)
        -> body (build_aligned_ByteString b) rec cd
           = match (body' n rec' b cd) with
             | Some (a, b', cd') => Some (a, build_aligned_ByteString (projT2 b'), cd')
             | None => None
             end)
    -> Fix well_founded_lt_b (fun _ : ByteString => CacheDecode -> option (A * ByteString * CacheDecode)) body (build_aligned_ByteString b) cd =
       match Fix Wf_nat.lt_wf (fun m : nat => Vector.t (word 8) m -> CacheDecode -> option (A * { n : _ & Vector.t _ n} * CacheDecode)) body' n b cd with
       | Some (a, b', cd') => Some (a, build_aligned_ByteString (projT2 b'), cd')
       | None => None
       end.
Proof.
  intros.
  revert cd b; pattern n.
  eapply (well_founded_ind Wf_nat.lt_wf); intros.
  rewrite Init.Wf.Fix_eq, Init.Wf.Fix_eq.
  apply H; intros.
  erewrite H0, H1; eauto.
  rewrite H0, H1; eauto.
  eauto.
  eauto.
Qed.

Lemma If_sumbool_Then_Else_DecodeBindOpt {A B B' ResultT ResultT'} {P}
  : forall (a_eq_dec : forall a a' : A, {P a a'} + {~ P a a'})
           a a'
           (k : _ -> _ -> _ -> option (ResultT' * B' * CacheDecode))
           (t : P a a' ->  option (ResultT * B * CacheDecode))
           (e : ~ P a a' -> option (ResultT * B * CacheDecode)),
    (`(w, b', cd') <- match a_eq_dec a a' with
                      | left e => t e
                      | right n => e n
                      end;
       k w b' cd') =
    match a_eq_dec a a' with
    | left e => `(w, b', cd') <- t e; k w b' cd'
    | right n => `(w, b', cd') <- e n; k w b' cd'
    end.
Proof.
  intros; destruct (a_eq_dec a a'); simpl; intros; reflexivity.
Qed.

Lemma optimize_under_DecodeBindOpt2_both {A B C D E} {B' }
  : forall (a_opt : option (A * B * C))
           (a_opt' : option (A * B' * C))
           (g : B' -> B)
           (a_opt_eq_Some : forall a' b' c,
               a_opt' = Some (a', b', c) ->
               a_opt = Some (a', g b', c))
           (a_opt_eq_None : a_opt' = None -> a_opt = None)
           (k : _ -> _ -> _ -> option (D * E * C))
           (k' : _ -> _ -> _ -> _)
           (k_eq_Some :
              forall a' b' c,
                a_opt' = Some (a', b', c) ->
                k a' (g b') c = k' a' b' c),
    DecodeBindOpt2 a_opt k = DecodeBindOpt2 a_opt' k'.
Proof.
  destruct a_opt' as [ [ [? ?] ?] | ]; simpl; intros.
  erewrite a_opt_eq_Some; simpl; eauto.
  erewrite a_opt_eq_None; simpl; eauto.
  Qed.

  Lemma rec_aligned_decode_DomainName_OK
    : forall (x : nat) (x0 : t (word 8) x),
      (le 1 x) ->
      ~ (lt (x - 1) (wordToNat (Vector.hd (Guarded_Vector_split 1 x x0))))%nat ->
      (lt (x - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 x x0))) x)%nat.
  Proof.
    clear; intros; omega.
  Qed.

  Definition byte_aligned_decode_DomainName {sz}
             (b : Vector.t (word 8) sz)
             (cd : CacheDecode) :=
    let body :=
        fun n0
                  (rec' : forall x : nat,
                      (lt x n0)%nat ->
                      t Core.char x -> CacheDecode -> option (RRecordTypes.DomainName * {n1 : nat & t Core.char n1} * CacheDecode))
                  b cd =>
          match Compare_dec.le_dec 1 n0 with
       | left e1 =>
     match wlt_dec (natToWord 8 191) (Vector.hd (Guarded_Vector_split 1 n0 b)) with
     | left e =>
         if match n0 - 1 with
            | 0 => false
            | S _ => true
            end
         then
          match
            association_list_find_first (snd cd)
              (exist (wlt (natToWord 8 191)) (Vector.hd (Guarded_Vector_split 1 n0 b)) e,
              Vector.hd (Guarded_Vector_split 1 (n0 - 1) (Vector.tl (Guarded_Vector_split 1 n0 b))))
          with
          | Some ""%string => None
          | Some (String _ _ as domain) =>
              Some
                (domain,
                 existT (fun n => Vector.t (word 8) n) _ (Vector.tl (Guarded_Vector_split 1 (n0 - 1) (Vector.tl (Guarded_Vector_split 1 n0 b)))),
                addD (addD cd 8) 8)
          | None => None
          end
         else None
     | right n1 =>
         if bool_of_sumbool (wlt_dec (Vector.hd (Guarded_Vector_split 1 n0 b)) (natToWord 8 64))
         then
          match weq (Vector.hd (Guarded_Vector_split 1 n0 b)) (wzero 8) with
          | in_left => Some (""%string, existT (fun n => Vector.t (word 8) n) _ (Vector.tl (Guarded_Vector_split 1 n0 b)), addD cd 8)
          | right n2 =>
              (fun a_neq0 : Vector.hd (Guarded_Vector_split 1 n0 b) <> wzero 8 =>
               match Compare_dec.lt_dec (n0 - 1) (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b))) with
               | left e => (fun _ : lt (n0 - 1) (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))%nat => None) e
               | right n3 =>
                   (fun a_neq1 : ~ lt (n0 - 1) (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))%nat =>
                    Ifopt index 0 "."
                            (BytesToString
                               (fst
                                  (Vector_split (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                     (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                     (Guarded_Vector_split
                                        (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                        (n0 - 1) (Vector.tl (Guarded_Vector_split 1 n0 b)))))) as a8 Then
                    (fun _ : nat => None) a8
                    Else (`(d, s, c) <- rec' (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                          (rec_aligned_decode_DomainName_OK n0 b e1 n3)
                                          (snd
                                             (Vector_split
                                                (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                (Guarded_Vector_split
                                                  (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                  (n0 - 1)
                                                  (Vector.tl (Guarded_Vector_split 1 n0 b)))))
                                          (addD (addD cd 8) (8 * wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b))));
                          If string_dec d ""
                          Then Some
                                 (BytesToString
                                    (fst
                                       (Vector_split
                                          (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                          (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                          (Guarded_Vector_split
                                             (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                             (n0 - 1)
                                             (Vector.tl (Guarded_Vector_split 1 n0 b))))),
                                  s,
                                 Ifopt Ifopt fst cd as m Then Some (Nat2pointerT (wordToNat (wtl (wtl (wtl m))))) Else None
                                 as curPtr
                                 Then (fst c,
                                      ((curPtr,
                                       BytesToString
                                         (fst
                                            (Vector_split
                                               (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                               (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                               (Guarded_Vector_split
                                                  (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                  (n0 - 1)
                                                  (Vector.tl (Guarded_Vector_split 1 n0 b)))))) ::
                                       snd c)%list) Else c)
                          Else Some
                                 ((BytesToString
                                     (fst
                                        (Vector_split
                                           (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                           (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                           (Guarded_Vector_split
                                              (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                              (n0 - 1)
                                              (Vector.tl (Guarded_Vector_split 1 n0 b))))) ++
                                   String "." d)%string,
                                  s,
                                 Ifopt Ifopt fst cd as m Then Some (Nat2pointerT (wordToNat (wtl (wtl (wtl m))))) Else None
                                 as curPtr
                                 Then (fst c,
                                      ((curPtr,
                                       (BytesToString
                                          (fst
                                             (Vector_split
                                                (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                (n0 - 1 - wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                (Guarded_Vector_split
                                                  (wordToNat (Vector.hd (Guarded_Vector_split 1 n0 b)))
                                                  (n0 - 1)
                                                  (Vector.tl (Guarded_Vector_split 1 n0 b))))) ++
                                        String "." d)%string) ::
                                       snd c)%list) Else c))) n3
               end) n2
          end
         else None
     end
       | right e => None
          end in
    Fix Wf_nat.lt_wf (fun m : nat => Vector.t (word 8) m -> CacheDecode -> option (_ * { n : _ & Vector.t _ n} * CacheDecode)) body sz b cd.

    Lemma byte_align_decode_DomainName {sz}
      : forall (b : Vector.t (word 8) sz) cd,
      decode_DomainName(build_aligned_ByteString b) cd =
      Ifopt byte_aligned_decode_DomainName b cd as p Then
    (match p with
     | (a, b', cd') => Some (a, build_aligned_ByteString (projT2 b'), cd')
     end)
    Else None.
     Proof.
       unfold If_Opt_Then_Else,decode_DomainName,
       byte_aligned_decode_DomainName; simpl; intros.
      eapply optimize_Fix.
      Focus 3.
      etransitivity.
      simpl; intros.
      erewrite ByteAlign_Decode_w_Measure_le with (m := 1)
                                                    (dec_a' := Vector.hd)
                                                    (f := fun cd => addD cd 8);
        try (intros; unfold decode_word; rewrite aligned_decode_char_eq;
             reflexivity).
      Focus 2.
      intros; assert (n = 0) by omega; subst.
      revert b1; clear.
      apply case0; reflexivity.
      set_refine_evar.
      etransitivity;
        [eapply If_sumbool_Then_Else_DecodeBindOpt | ]; simpl.
      apply optimize_under_match; intros.
      simpl.

      apply optimize_under_match; intros.
      simpl.
      erewrite ByteAlign_Decode_w_Measure_le with (m := 1)
                                                    (dec_a' := Vector.hd)
                                                    (f := fun cd => addD cd 8);
        try (intros; unfold decode_word; rewrite aligned_decode_char_eq;
             reflexivity).
      Focus 2.
      intros; assert (n - 1 = 0) by omega.
      revert b1; rewrite H3; clear.
      apply case0; reflexivity.
      set_refine_evar.
      simpl.
      etransitivity;
        [eapply If_sumbool_Then_Else_DecodeBindOpt | ]; simpl.
      apply optimize_under_match; intros.
      simpl.
      reflexivity.
      simpl.
      reflexivity.
      eapply optimize_under_if_bool.
      apply optimize_under_match.
      simpl.
      intros; higher_order_reflexivity.
      intros.
      simpl.
      2: reflexivity.
      2: reflexivity.
      2: simpl.
      erewrite ByteAlign_Decode_w_Measure_lt with (m := (wordToNat (Vector.hd (Guarded_Vector_split 1 n b0)))) (m_OK := n_eq_0_lt _ a_neq0).
      Focus 3.

      intros.
      rewrite decode_string_aligned_ByteString.
      repeat f_equal.
  higher_order_reflexivity.
  higher_order_reflexivity.

  etransitivity;
    [eapply If_sumbool_Then_Else_DecodeBindOpt | ]; simpl.
  etransitivity.
  apply optimize_under_match; intros.
  subst_refine_evar; simpl; higher_order_reflexivity.
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  subst_refine_evar; simpl; higher_order_reflexivity.
  apply optimize_under_match; intros.
  simpl; higher_order_reflexivity.
  unfold LetIn.
  apply optimize_under_if_opt.
  intros; higher_order_reflexivity.
  eapply optimize_under_DecodeBindOpt2_both.
  unfold lt_B_Guarded_Vector_split; simpl.
  intros; apply H with (b_lt' := rec_aligned_decode_DomainName_OK _ _ a_eq a_neq1).
  apply H2.
  intros; eapply H0; eauto.
  intros; simpl.
  higher_order_reflexivity.
  intros; eauto using decode_string_aligned_ByteString_overflow.
  destruct n; eauto.
  destruct (wlt_dec (natToWord 8 191) (Vector.hd (Guarded_Vector_split 1 (S n) b0)));
    eauto.
  find_if_inside; eauto.
  simpl.
  find_if_inside; eauto.
  destruct n; try omega; simpl; eauto.
  match goal with
    |- match ?z with _ => _ end = match match ?z' with _ => _ end with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  clear; induction s; simpl; eauto.
  destruct n; simpl; auto; try omega.
  match goal with
    |- match ?z with _ => _ end = match match ?z' with _ => _ end with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  match goal with
    |- match ?z with _ => _ end = match match ?z' with _ => _ end with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  find_if_inside; simpl; eauto.
  match goal with
    |- match ?z with _ => _ end = match match ?z' with _ => _ end with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  match goal with
    |- (Ifopt ?c as a Then _ Else _) = _ => destruct c as [ ? | ]; simpl; eauto
  end.
  match goal with
    |- DecodeBindOpt2 ?z _ = _ => destruct z as [ [ [? ?] ?] | ]; simpl; eauto
  end.
  find_if_inside; simpl; eauto.
  simpl; intros; apply functional_extensionality; intros.
  f_equal.
  simpl; intros; repeat (apply functional_extensionality; intros).
  destruct (wlt_dec (natToWord 8 191) x1).
  reflexivity.
  destruct (wlt_dec x1 (natToWord 8 64)); simpl.
  destruct (weq x1 (wzero 8)); eauto.
  match goal with
    |- DecodeBindOpt2 ?z _ = _ => destruct z as [ [ [? ?] ?] | ]; simpl; eauto
  end.
  match goal with
    |- (Ifopt ?c as a Then _ Else _) = _ => destruct c as [ ? | ]; simpl; eauto
  end.
  rewrite H.
  reflexivity.
  eauto.
  simpl; intros; apply functional_extensionality; intros.
  f_equal.
  simpl; intros; repeat (apply functional_extensionality; intros).
  match goal with
    |- match ?z with _ => _ end = match ?z' with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  match goal with
    |- match ?z with _ => _ end = match ?z' with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  find_if_inside; simpl.
  find_if_inside; simpl; eauto.
    match goal with
    |- match ?z with _ => _ end = match ?z' with _ => _ end =>
    replace z' with z by reflexivity; destruct z; eauto
  end.
  match goal with
    |- (Ifopt ?c as a Then _ Else _) = _ => destruct c as [ ? | ]; simpl; eauto
  end.
  rewrite H; reflexivity.
  eauto.
  Qed.

  Lemma lift_match_if_ByteAlign
        {T1}
        {T2 T3 T4 A : T1 -> Type}
        {B B' C}
    : forall (b : bool)
             (t1 : T1)
             (t e : option (A t1 * B * C))
             (b' : forall t1, T2 t1 -> T3 t1 -> T4 t1 -> bool)
             (t' e' : forall t1, T2 t1 -> T3 t1 -> T4 t1 -> option (A t1 * B' * C))
             (f : B' -> B)
             (t2 : T2 t1)
             (t3 : T3 t1)
             (t4 : T4 t1),
      (b = b' t1 t2 t3 t4)
      -> (t = match t' t1 t2 t3 t4 with
       | Some (a, b', c) => Some (a, f b', c)
       | None => None
           end)
      -> (e = match e' t1 t2 t3 t4 with
       | Some (a, b', c) => Some (a, f b', c)
       | None => None
              end)
      -> (if b then t else e) =
      match (fun t1 t2 t3 t4 => if b' t1 t2 t3 t4 then t' t1 t2 t3 t4 else e' t1 t2 t3 t4) t1 t2 t3 t4 with
      | Some (a, b', c) => Some (a, f b', c)
      | None => None
      end.
  Proof.
    intros; destruct b; eauto; rewrite <- H; simpl; eauto.
  Qed.

  Lemma lift_match_if_sumbool_ByteAlign
        {T1}
        {T3 : T1 -> Type}
        {P : forall t1 (t3 : T3 t1), Prop}
        {T2 T4 A : T1 -> Type}
        {B B' C}
    : forall (t1 : T1)
             (t3 : T3 t1)
             (b : forall t1 t3, {P t1 t3} + {~P t1 t3})
             (t : _ -> option (A t1 * B * C))
             (e : _ -> option (A t1 * B * C))
             (b' : forall t1 t3, T2 t1 -> T4 t1 -> {P t1 t3} + {~P t1 t3})
             (t' : forall t1 t3, T2 t1 -> T4 t1 -> _ -> option (A t1 * B' * C))
             (e' : forall t1 t3, T2 t1 -> T4 t1 -> _ -> option (A t1 * B' * C))
             (f : B' -> B)
             (t2 : T2 t1)
             (t4 : T4 t1),
      (b t1 t3 = b' t1 t3 t2 t4)
      -> (forall e'',
             t e'' = match t' t1 t3 t2 t4 e'' with
                    | Some (a, b', c) => Some (a, f b', c)
                    | None => None
              end)
      -> (forall e'',
             e e'' = match e' t1 t3 t2 t4 e'' with
                     | Some (a, b', c) => Some (a, f b', c)
                     | None => None
                     end)
      -> (match b t1 t3 with
            left e'' => t e''
          | right e'' => e e''
          end) =
         match (fun t1 t2 t3 t4 =>
                  match b' t1 t3 t2 t4 with
                  | left e'' => t' t1 t3 t2 t4 e''
                  | right e'' => e' t1 t3 t2 t4 e''
                  end) t1 t2 t3 t4 with
      | Some (a, b', c) => Some (a, f b', c)
      | None => None
      end.
  Proof.
    intros; destruct b; eauto; rewrite <- H; simpl; eauto.
  Qed.

    Lemma decode_word_aligned_ByteString_overflow
        {sz}
    : forall {sz'}
             (b : t (word 8) sz')
             (cd : CacheDecode),
      lt sz' sz
      -> decode_word (sz := 8 * sz) (build_aligned_ByteString b) cd = None.
  Proof.
  Admitted.

  Lemma build_aligned_ByteString_eq_split'
    : forall n sz v,
      (n <= sz)%nat
      ->
      build_aligned_ByteString v
      = build_aligned_ByteString (Guarded_Vector_split n sz v).
  Proof.
    intros; eapply ByteString_f_equal; simpl.
    instantiate (1 := eq_refl _); reflexivity.
    instantiate (1 := (le_plus_minus_r _ _ H)).
    generalize (le_plus_minus_r n sz H); clear.
    revert sz v; induction n; simpl; intros.
    unfold Guarded_Vector_split.
    rewrite <- Equality.transport_pp.
    generalize (eq_trans (minus_n_O sz) e); clear;
      intro.
    apply Eqdep_dec.eq_rect_eq_dec; auto with arith.
    destruct v; simpl in *.
    omega.
    unfold Guarded_Vector_split; fold Guarded_Vector_split;
      simpl.
    erewrite eq_rect_Vector_cons; eauto.
    f_equal.
    apply IHn.
    Grab Existential Variables.
    omega.
  Qed.

  Lemma optimize_Guarded_Decode {sz} {A C} n
    : forall (a_opt : ByteString -> option (A * ByteString * C)) v,
      (~ (n <= sz)%nat
              -> a_opt (build_aligned_ByteString v) = None)
      -> a_opt (build_aligned_ByteString v) =
         If NPeano.leb n sz Then
            a_opt (build_aligned_ByteString (Guarded_Vector_split n sz v))
            Else None.
  Proof.
    intros; destruct (NPeano.leb n sz) eqn: ?.
    - apply NPeano.leb_le in Heqb.
      simpl; rewrite <- build_aligned_ByteString_eq_split'; eauto.
    - rewrite H; simpl; eauto.
      intro.
      rewrite <- NPeano.leb_le in H0; congruence.
  Qed.

  Arguments Core.append_word : simpl never.

  Lemma nth_Vector_split {A}
    : forall {sz} n v idx,
      (snd (Vector_split (A := A) n sz v))[@idx]
      = v[@(Fin.R n idx)].
  Proof.
    induction n; simpl; intros; eauto.
    assert (forall A n b, exists a b', b = Vector.cons A a n b')
      by (clear; intros; pattern n, b; apply caseS; eauto).
    pose proof (H _ _ v); destruct_ex; subst.
    simpl.
    destruct (Vector_split n sz x0) as [? ?] eqn: ?.
    rewrite <- IHn.
    rewrite Heqp; reflexivity.
  Qed.

  Lemma Vector_split_merge {A}
    : forall sz m n (v : Vector.t A _),
      snd (Vector_split m _ (snd (Vector_split n (m + sz) v))) =
      snd (Vector_split (n + m) _ (eq_rect _ _ v _ (plus_assoc _ _ _))).
  Proof.
    induction m; intros; simpl.
    - induction n; simpl.
      + simpl in *.
        apply Eqdep_dec.eq_rect_eq_dec; auto with arith.
      + simpl in v.
        assert (forall A n b, exists a b', b = Vector.cons A a n b')
          by (clear; intros; pattern n, b; apply caseS; eauto).
        pose proof (H _ _ v); destruct_ex; subst.
        simpl.
        pose proof (IHn x0).
        destruct (Vector_split n sz x0) eqn: ?.
        simpl in *.
        rewrite H0.
        erewrite eq_rect_Vector_cons with (H' := (plus_assoc n 0 sz)); eauto; simpl.
        destruct (Vector_split (n + 0) sz (eq_rect (n + sz) (Vector.t A) x0 (n + 0 + sz) (plus_assoc n 0 sz))); reflexivity.
    -
  Admitted.

  Arguments Vector_split : simpl never.

  Definition ByteAligned_packetDecoderImpl n
  : {impl : _ & forall (v : Vector.t _ (12 + n)),
         fst packetDecoderImpl (build_aligned_ByteString v) (Some (wzero 17), @nil (pointerT * string)) =
         impl v (Some (wzero 17) , @nil (pointerT * string))%list}.
Proof.
  eexists _; intros.
  etransitivity.
  set_refine_evar; simpl.
  rewrite (@AlignedDecode2Char _ ).
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  rewrite (@AlignedDecodeChar _ ).
  rewrite !nth_Vector_split.
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  rewrite (@AlignedDecodeChar _ ).
  rewrite !nth_Vector_split.
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  subst_refine_evar.
  etransitivity;
    [eapply (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache))
    | ].
  Global Opaque Vector_split.
  simpl.
  eapply optimize_under_if_opt; simpl; intros.
  etransitivity;
    [eapply (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache))
    | ].
  eapply optimize_under_if_opt; simpl; intros.
  eapply optimize_under_if; simpl; intros.
  rewrite (@AlignedDecode2Nat _).
  repeat first  [rewrite <- !Vector_nth_tl
                | rewrite !nth_Vector_split].
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  eapply optimize_under_if; simpl; intros.
  rewrite (@AlignedDecode2Nat _).
  rewrite !nth_Vector_split.
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  rewrite (@AlignedDecode2Nat _).
  rewrite !nth_Vector_split.
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  rewrite (@AlignedDecode2Nat _).
  rewrite !nth_Vector_split.
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  rewrite DecodeBindOpt2_assoc.
  rewrite byte_align_decode_DomainName.
  etransitivity;
    [match goal with
       |- DecodeBindOpt2 (If_Opt_Then_Else ?a_opt ?t ?e) ?k = _ =>
       pose proof (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache) a_opt t e k) as H'; apply H'; clear H'
     end | ].
  subst H0.
  eapply optimize_under_if_opt; simpl; intros.
  destruct a8 as [ [? [ ? ?] ] ? ]; simpl.
  rewrite DecodeBindOpt2_assoc.
  simpl.
  etransitivity.
  match goal with
    |- ?b = _ =>
    let b' := (eval pattern (build_aligned_ByteString t) in b) in
    let b' := match b' with ?f _ => f end in
    eapply (@optimize_Guarded_Decode x _ _ 4 b')
  end.
  intros.
  unfold decode_enum.
  rewrite DecodeBindOpt2_assoc.
  destruct (Compare_dec.lt_dec x 2).
  pose proof (@decode_word_aligned_ByteString_overflow 2) as H';
    simpl in H'; rewrite H'; try reflexivity; auto.
  destruct x as [ | [ | [ | ?] ] ]; try omega.
  rewrite AlignedDecode2Char; unfold LetIn; simpl.
  etransitivity;
    [match goal with
       |- DecodeBindOpt2 (If_Opt_Then_Else ?a_opt ?t ?e) ?k = _ =>
       pose proof (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache) a_opt t e k) as H'; apply H'; clear H'
     end | ].
  simpl.
  match goal with
    |- If_Opt_Then_Else ?b _ _ = _ => destruct b; reflexivity
  end.
  rewrite AlignedDecode2Char; unfold LetIn; simpl.
  etransitivity;
    [match goal with
       |- DecodeBindOpt2 (If_Opt_Then_Else ?a_opt ?t ?e) ?k = _ =>
       pose proof (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache) a_opt t e k) as H'; apply H'; clear H'
     end | ].
  simpl.
  match goal with
    |- If_Opt_Then_Else ?b _ _ = _ => destruct b; simpl; try eauto
  end.
  repeat rewrite DecodeBindOpt2_assoc.
  pose proof (@decode_word_aligned_ByteString_overflow 2) as H';
    simpl in H'; rewrite H'; try reflexivity; auto.
  omega.
  etransitivity.
  eapply optimize_under_if_bool; simpl; intros.
  unfold decode_enum.
  set_refine_evar; repeat rewrite DecodeBindOpt2_assoc.
  rewrite (@AlignedDecode2Char _ ).
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  etransitivity;
    [match goal with
       |- DecodeBindOpt2 (If_Opt_Then_Else ?a_opt ?t ?e) ?k = _ =>
       pose proof (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache) a_opt t e k) as H'; apply H'; clear H'
     end | ].
  simpl.
  subst_refine_evar;
    eapply optimize_under_if_opt; simpl; intros;
      set_refine_evar.
  repeat rewrite DecodeBindOpt2_assoc.
  rewrite (@AlignedDecode2Char _ ).
  subst_refine_evar; apply rewrite_under_LetIn; intros; set_refine_evar.
  etransitivity;
    [match goal with
       |- DecodeBindOpt2 (If_Opt_Then_Else ?a_opt ?t ?e) ?k = _ =>
       pose proof (If_Opt_Then_Else_DecodeBindOpt (cache := dns_list_cache) a_opt t e k) as H'; apply H'; clear H'
     end | ].
  simpl.
  subst_refine_evar;
    eapply optimize_under_if_opt; simpl; intros;
      set_refine_evar.
  (* Still need to do byte-aligned lists. *)
  higher_order_reflexivity.
  unfold H0. higher_order_reflexivity.
  unfold H0. higher_order_reflexivity.
  higher_order_reflexivity.
  match goal with
    |- ?z = ?f (?d, existT _ ?x ?t, ?p) =>
    let z' := (eval pattern d, x, t, p in z) in
    let z' := match z' with ?f' _ _ _ _ => f' end in
    unify f (fun a => z' (fst (fst a)) (projT1 (snd (fst a)))
                         (projT2 (snd (fst a)))
                         (snd a));
      cbv beta; reflexivity
  end.
  reflexivity.
  reflexivity.
  reflexivity.
  reflexivity.
  reflexivity.
  simpl.
  repeat (rewrite Vector_split_merge,
          <- Eqdep_dec.eq_rect_eq_dec;
          eauto using Peano_dec.eq_nat_dec ).
  simpl.
  higher_order_reflexivity.
Defined.

Check ByteAligned_packetDecoderImpl.
Definition ByteAligned_packetDecoderImpl' n :=
  Eval simpl in (projT1 (ByteAligned_packetDecoderImpl n)).

Lemma ByteAligned_packetDecoderImpl'_OK
  : forall n,
    forall (v : Vector.t _ (12 + n)),
      fst packetDecoderImpl (build_aligned_ByteString v) (Some (wzero 17), @nil (pointerT * string)) =
      ByteAligned_packetDecoderImpl' n v (Some (wzero 17) , @nil (pointerT * string))%list.
Proof.
  intros.
  pose proof (projT2 (ByteAligned_packetDecoderImpl n));
    cbv beta in H.
  rewrite H.
  set (H' := (Some (wzero 17), @nil (pointerT * string))).
  simpl.
  unfold ByteAligned_packetDecoderImpl'.
  reflexivity.
Qed.

End DnsPacket.