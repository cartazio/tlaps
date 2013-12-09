-------------- MODULE load_v8_test ---------
THEOREM cantor ==
  \A S :
    \A f \in [S -> SUBSET S] :
      \E A \in SUBSET S :
        \A x \in S :
          f [x] # A
<1>1. SUFFICES
        ASSUME NEW S,
               NEW f \in [S -> SUBSET S]
        PROVE  \E A \in SUBSET S :
                 \A x \in S : f [x] # A
  OBVIOUS
<1>2. DEFINE T == {z \in S : z \notin f [z]}
<1>3. SUFFICES ASSUME NEW x \in S
               PROVE  f[x] # T
  <2>1. WITNESS T \in SUBSET S
  <2>2. QED OBVIOUS
<1>4. CASE x \in T
  <2>1. x \notin f [x] BY <1>4
  <2>2. QED BY <2>1
<1>5. CASE x \notin T
  <2>1. x \in f [x] BY <1>3, <1>5
  <2>2. QED BY <2>1
<1>6. QED
  BY <1>4, <1>5
===============================================
command: rm -rf load_v8_test.tlaps
command: cp -r load_v8_test.tlaps.testbase load_v8_test.tlaps
command: ${TLAPM} --toolbox 0 0 --isaprove ${FILE}
stdout: fingerprints written
stderr: Translating fingerprints from version 8
stderr: already:true
