use context starter2024

# Checks every behavioural claim made in docs.md, one check block per
# section of the docs (several where a section makes distinct claims), so
# that a library change that falsifies a sentence in the docs fails a test
# that names the section.
# Run from this directory:  pyret -q docs-examples.arr
# docs.md writes the library's names as Z.int-var and so on; this file uses
# `include`, so the same names appear without the prefix.

include file("../z3.arr")

x = int-var("x")
y = int-var("y")
z = int-var("z")
p = bool-var("p")
q = bool-var("q")
s = bool-var("s")
r = real-var("r")
r2 = real-var("r2")

students = [list: 17, 18]
labs = [list: 1, 2]
items = [list: "a", "b"]
seated = bool-family2("seated", students, labs)
age = int-family("age", students)
cost = int-family("cost", items)

# ---------------------------------------------------------------------------
# Overview

check "docs: Overview: the first example":
  got = cases (Result) solve([constraints: x > 2, (x + y).eq(10)]):
    | sat(m) => {m.num(x); m.num(y)}
    | unsat => raise("no solution")
    | unknown(why) => raise(why)
  end
  got.{0} is%(_ > _) 2
  (got.{0} + got.{1}) is 10
end

check "docs: Overview: sorts, and exact numbers":
  int-sort satisfies is-Sort
  bool-sort satisfies is-Sort
  real-sort satisfies is-Sort
  int-sort is-not real-sort
  # sorts are checked as terms are built, before anything reaches Z3
  [conj: p, x] raises "should be a Bool term, but x is an Int"
  # integers and rationals go to Z3 exactly and come back exactly
  solve([constraints: x.eq(12345678901234567890)]).model.num(x) is 12345678901234567890
  solve([constraints: r.eq(-1/2)]).model.num(r) is -1/2
  to-smt(lift(-1/2)) is "(- (/ 1 2))"
  # a RoughNum becomes an exact rational
  to-smt(lift(~0.5)) is "(/ 1 2)"
  to-smt(x + ~2.5) is "(+ x (/ 5 2))"
end

# ---------------------------------------------------------------------------
# Variables

check "docs: Variables: three kinds, named for Z3":
  to-smt(int-var("x")) is "x"
  to-smt(bool-var("p")) is "p"
  to-smt(real-var("r")) is "r"
  [constraints: x > 0].script() satisfies string-contains(_, "(declare-const x Int)")
  [constraints: p].script() satisfies string-contains(_, "(declare-const p Bool)")
  [constraints: r > 0].script() satisfies string-contains(_, "(declare-const r Real)")
  # a variable is identified by its name: two calls denote one variable
  int-var("x") is x
  solve([constraints: int-var("n") > 2, int-var("n") < 4]).model.names() is [list: "n"]
  solve([constraints: int-var("n") > 2, int-var("n") < 4]).model.num(int-var("n")) is 3
end

check "docs: Variables: legal names":
  int-var("a|b") raises "may not contain"
  int-var("a\\b") raises "may not contain"
  int-var("") raises "non-empty"
  bool-var("") raises "non-empty"
  to-smt(int-var("CSCI 0190")) is "|CSCI 0190|"
  to-smt(int-var("a-b_c?")) is "a-b_c?"
  model-num(solve([constraints: int-var("CSCI 0190").eq(190)]).model, "CSCI 0190") is 190
end

check "docs: Variables: one name with two sorts is an error":
  # building the terms is fine; the problem is rejected when solved
  [constraints: int-var("v").eq(1), bool-var("v")].length() is 2
  solve([constraints: int-var("v").eq(1), bool-var("v")]) raises "two sorts"
  [constraints: int-var("v").eq(1), bool-var("v")].script() raises "two sorts"
  satisfiable([constraints: int-var("v").eq(1), real-var("v") > 0]) raises "two sorts"
end

# ---------------------------------------------------------------------------
# Variable Families

check "docs: Variable Families: six constructors, and the generated names":
  to-smt(cost("a")) is "|cost[a]|"
  to-smt(seated(17, 2)) is "|seated[17,2]|"
  # seated(17, 2) is the same variable as bool-var("seated[17,2]")
  seated(17, 2) is bool-var("seated[17,2]")
  solve([constraints: seated(17, 2), bool-var("seated[17,2]").negate()]) is unsat
  solve([constraints: seated(17, 2)]).model.names() is [list: "seated[17,2]"]
  # one constructor per sort, for one and for two indices
  [constraints: int-family("i1", items)("a") > 0].script() satisfies string-contains(_, "(declare-const |i1[a]| Int)")
  [constraints: bool-family("b1", items)("a")].script() satisfies string-contains(_, "(declare-const |b1[a]| Bool)")
  [constraints: real-family("r1", items)("a") > 0].script() satisfies string-contains(_, "(declare-const |r1[a]| Real)")
  [constraints: int-family2("i2", items, labs)("a", 1) > 0].script() satisfies string-contains(_, "(declare-const |i2[a,1]| Int)")
  [constraints: bool-family2("b2", items, labs)("b", 2)].script() satisfies string-contains(_, "(declare-const |b2[b,2]| Bool)")
  [constraints: real-family2("r2", items, labs)("a", 2) > 0].script() satisfies string-contains(_, "(declare-const |r2[a,2]| Real)")
end

check "docs: Variable Families: indices are checked, and may be any values":
  cost("c") raises "is not in the family's index set"
  seated(19, 1) raises "is not in the family's index set"
  seated(17, 3) raises "is not in the family's index set"
  age(17) satisfies is-Term
  # three or more indices: a one-index family over tuples
  slots = [list: {17; 1; 9}, {18; 2; 10}]
  busy = bool-family("busy", slots)
  busy({17; 1; 9}) satisfies is-Term
  busy({17; 1; 10}) raises "is not in the family's index set"
  solve([constraints: busy({17; 1; 9})]).model.bool(busy({17; 1; 9})) is true
end

# ---------------------------------------------------------------------------
# Terms: Literals

check "docs: Literals: explicit lift":
  to-smt(lift(3)) is "3"
  to-smt(lift(1/2)) is "(/ 1 2)"
  to-smt(lift(true)) is "true"
  to-smt(lift(false)) is "false"
  lift(x) is x
  lift("no") raises "the argument of lift cannot be used as a Z3 term"
  lift(3) satisfies is-Term
end

check "docs: Literals: automatic lifting":
  to-smt(x + 1) is "(+ x 1)"
  to-smt(x.eq(3)) is "(= x 3)"
  to-smt(p.and-also(true)) is "(and p true)"
  to-smt([sum: x, y, 1]) is "(+ x y 1)"
  to-smt([conj: p, true]) is "(and p true)"
  to-smt(ite(p, 1, 2)) is "(ite p 1 2)"
  # on the left of an operator, lift explicitly (or reorder)
  to-smt(lift(3) * x) is "(* 3 x)"
  to-smt(x * 3) is "(* x 3)"
  # not inside constraints, whose elements must be terms
  [constraints: true] raises "is the Pyret Boolean true"
  [constraints: 3] raises "is not a constraint"
  [constraints: lift(true)].length() is 1
end

# ---------------------------------------------------------------------------
# Terms: Arithmetic

check "docs: Arithmetic: operators, and Int with Real":
  to-smt(x + y) is "(+ x y)"
  to-smt(x - 1) is "(- x 1)"
  to-smt(x * 3) is "(* x 3)"
  to-smt(x / 2) is "(div x 2)"
  to-smt(x.neg()) is "(- x)"
  to-smt(x.modulo(3)) is "(mod x 3)"
  # the right operand may be a term, a number, or a Boolean
  to-smt(x + r) is "(+ x r)"
  to-smt(x + 1/2) is "(+ x (/ 1 2))"
  to-smt(x + true) is "(+ x (ite true 1 0))"
  (x + "one") raises "the right side of + cannot be used as a Z3 term"
  (x * p.and-also("no")) raises "the right side of .and-also cannot be used as a Z3 term"
  # Int and Real mix; the result is Real if anything in it is
  to-smt((x + r) / 2) is "(/ (+ x r) 2)"
  to-smt((x + 1) / 2) is "(div (+ x 1) 2)"
  to-smt((x * r2) - r) is "(- (* x r2) r)"
  (x + r).eq(y) satisfies is-Term
end

check "docs: Arithmetic: division and modulo":
  to-smt(x / y) is "(div x y)"
  to-smt(r / 2) is "(/ r 2)"
  to-smt(x / r) is "(/ x r)"
  to-smt(x / 1/2) is "(/ x (/ 1 2))"
  # integer division rounds so that the remainder is non-negative
  solve([constraints: x.eq(-7), (x / 3).eq(y)]).model.num(y) is -3
  solve([constraints: x.eq(-7), x.modulo(3).eq(y)]).model.num(y) is 2
  solve([constraints: x.eq(7), (x / 2).eq(y)]).model.num(y) is 3
  # real division is exact
  solve([constraints: r.eq(1), (r / 2).eq(r2)]).model.num(r2) is 1/2
  solve([constraints: (x / 2).eq(3), x > 6]).model.num(x) is 7
  # modulo is defined only on Ints
  to-smt(x.modulo(y)) is "(mod x y)"
  r.modulo(2) raises "needs Int operands, but one is a Real"
  x.modulo(r) raises "needs Int operands, but one is a Real"
  x.modulo("a") raises "the argument of .modulo cannot be used as a Z3 term"
end

check "docs: Arithmetic: a Bool term counts as 0 or 1":
  to-smt(p + q) is "(+ (ite p 1 0) (ite q 1 0))"
  to-smt((p + q) <= 1) is "(<= (+ (ite p 1 0) (ite q 1 0)) 1)"
  to-smt(p * 3) is "(* (ite p 1 0) 3)"
  to-smt(p.modulo(2)) is "(mod (ite p 1 0) 2)"
  to-smt(p.neg()) is "(- (ite p 1 0))"
  # "at most one of p and q"
  solve([constraints: (p + q) <= 1, p]).model.bool(q) is false
  satisfiable([constraints: (p + q) <= 1, p, q]) is false
  # counting the students in lab 1
  in-lab-1 = for sum-over(st from students): seated(st, 1) end
  to-smt(in-lab-1) is "(+ (ite |seated[17,1]| 1 0) (ite |seated[18,1]| 1 0))"
  m = solve([constraints: in-lab-1.eq(2)]).model
  m.bool(seated(17, 1)) is true
  m.bool(seated(18, 1)) is true
  solve([constraints: in-lab-1.eq(3)]) is unsat
end

# ---------------------------------------------------------------------------
# Terms: Comparisons

check "docs: Comparisons: order comparisons need numeric operands":
  to-smt(x < y) is "(< x y)"
  to-smt(x <= 10) is "(<= x 10)"
  to-smt(x > 0) is "(> x 0)"
  to-smt(x >= y) is "(>= x y)"
  to-smt(x < r) is "(< x r)"
  to-smt(r >= 1/2) is "(>= r (/ 1 2))"
  # no chaining: x > y > 2 is (x > y) > 2, and the Bool term is refused
  (x > y > 2) raises "chained comparisons such as x > y > 2 are not supported"
  (x > y > 2) raises "the left side of > is the Bool term (> x y)"
  (x < y < 2) raises "the left side of < is the Bool term (< x y)"
  (x <= y <= 2) raises "the left side of <="
  (x >= y >= 0) raises "the left side of >="
  (x < p) raises "the right side of < is the Bool term p"
  (p <= 1) raises "the left side of <= is the Bool term p"
  (x >= true) raises "the right side of >= is the Bool term true"
  to-smt((x > y).and-also(y > 2)) is "(and (> x y) (> y 2))"
end

check "docs: Comparisons: eq and neq":
  # == compares Pyret values and yields a Pyret Boolean
  (x == y) is false
  (x == x) is true
  is-boolean(x == 3) is true
  is-Term(x == y) is false
  to-smt(x.eq(y)) is "(= x y)"
  to-smt(x.neq(0)) is "(not (= x 0))"
  to-smt(p.eq(q)) is "(= p q)"
  to-smt(p.eq(true)) is "(= p true)"
  to-smt(p.neq(q)) is "(not (= p q))"
  # any two terms of the same kind of sort: numeric with numeric, Bool with Bool
  to-smt(x.eq(r)) is "(= x r)"
  to-smt(r.neq(1/2)) is "(not (= r (/ 1 2)))"
  x.eq(p) raises "x is an Int but p is a Bool"
  x.eq(true) raises "x is an Int but true is a Bool"
  p.neq(x) raises "p is a Bool but x is an Int"
  p.eq(0) raises "p is a Bool but 0 is an Int"
  x.eq("a") raises "the argument of .eq cannot be used as a Z3 term"
  solve([constraints: x.eq(3), y.neq(3), y > 2, y < 5]).model.num(y) is 4
end

# ---------------------------------------------------------------------------
# Terms: Boolean Connectives

check "docs: Boolean Connectives: the six methods":
  to-smt(p.and-also(q)) is "(and p q)"
  to-smt(p.or-else(q)) is "(or p q)"
  to-smt(p.negate()) is "(not p)"
  to-smt(p.implies(q)) is "(=> p q)"
  to-smt(p.iff(q)) is "(= p q)"
  to-smt(p.xor(q)) is "(xor p q)"
  solve([constraints: p.implies(q), p]).model.bool(q) is true
  solve([constraints: p.or-else(q), p.negate()]).model.bool(q) is true
  satisfiable([constraints: p.iff(q), p, q.negate()]) is false
  satisfiable([constraints: p.xor(q), p, q]) is false
  satisfiable([constraints: p.and-also(q), q.negate()]) is false
end

check "docs: Boolean Connectives: the receiver is a Bool term, the argument may be a Pyret Boolean":
  to-smt(p.and-also(true)) is "(and p true)"
  to-smt(p.or-else(false)) is "(or p false)"
  to-smt(p.implies(false)) is "(=> p false)"
  to-smt(p.iff(true)) is "(= p true)"
  to-smt(p.xor(false)) is "(xor p false)"
  x.and-also(p) raises "the left side of .and-also should be a Bool term, but x is an Int"
  x.or-else(p) raises "the left side of .or-else should be a Bool term, but x is an Int"
  x.implies(p) raises "the left side of .implies should be a Bool term, but x is an Int"
  x.iff(p) raises "the left side of .iff should be a Bool term, but x is an Int"
  x.xor(p) raises "the left side of .xor should be a Bool term, but x is an Int"
  x.negate() raises "the term before .negate should be a Bool term, but x is an Int"
  r.negate() raises "the term before .negate should be a Bool term, but r is a Real"
  p.and-also(x) raises "the right side of .and-also should be a Bool term, but x is an Int"
  p.or-else(1) raises "the right side of .or-else should be a Bool term, but 1 is an Int"
  p.implies(1) raises "the right side of .implies should be a Bool term, but 1 is an Int"
  p.iff(r) raises "the right side of .iff should be a Bool term, but r is a Real"
  p.xor(x) raises "the right side of .xor should be a Bool term, but x is an Int"
  p.and-also("no") raises "the right side of .and-also cannot be used as a Z3 term"
  # a Pyret Boolean has no such methods: the receiver must be a term
  true.and-also(p) raises-satisfies lam(_): true end
end

# ---------------------------------------------------------------------------
# Terms: Constructors

check "docs: Constructors: the nine, and their serialisation":
  to-smt([conj: p, q, s]) is "(and p q s)"
  to-smt([disj: p, q, s]) is "(or p q s)"
  to-smt([sum: x, y, 1]) is "(+ x y 1)"
  to-smt([product: x, 2]) is "(* x 2)"
  to-smt([all-different: x, y, z]) is "(distinct x y z)"
  to-smt([exactly(1): p, q, s]) is "((_ pbeq 1 1 1 1) p q s)"
  to-smt([at-most(2): p, q, s]) is "((_ at-most 2) p q s)"
  to-smt([at-least(1): p, q, s]) is "((_ at-least 1) p q s)"
  to-smt(ite(p, x, y)) is "(ite p x y)"
  # meanings
  satisfiable([constraints: [conj: p, q], q.negate()]) is false
  solve([constraints: [disj: p, q], p.negate()]).model.bool(q) is true
  solve([constraints: [sum: x, y, 1].eq(10), x.eq(4)]).model.num(y) is 5
  solve([constraints: [product: x, 2].eq(10)]).model.num(x) is 5
  satisfiable([constraints: [all-different: x, y, z], x.eq(y)]) is false
  satisfiable([constraints: [exactly(1): p, q, s], p, q]) is false
  satisfiable([constraints: [at-most(2): p, q, s], p, q, s]) is false
  satisfiable([constraints: [at-least(1): p, q, s], p.negate(), q.negate(), s.negate()]) is false
  solve([constraints: ite(p, x, y).eq(5), p, y.eq(0)]).model.num(x) is 5
  solve([constraints: ite(p, x, y).eq(5), p.negate(), x.eq(0)]).model.num(y) is 5
end

check "docs: Constructors: element sorts":
  # conj, disj, and the cardinality constructors take Bool elements
  [conj: p, x] raises "element 2 of 2 of conj should be a Bool term, but x is an Int"
  [disj: p, 1] raises "element 2 of 2 of disj should be a Bool term, but 1 is an Int"
  [exactly(1): p, x] raises "element 2 of 2 of exactly(1) should be a Bool term, but x is an Int"
  [at-most(1): x] raises "element 1 of 1 of at-most(1) should be a Bool term, but x is an Int"
  [at-least(1): r] raises "element 1 of 1 of at-least(1) should be a Bool term, but r is a Real"
  [conj: p, "s", q] raises "element 2 of 3 of conj cannot be used as a Z3 term"
  # the count is a non-negative integer
  exactly(-1) raises "exactly needs a non-negative integer"
  at-most(1/2) raises "at-most needs a non-negative integer"
  at-least(-2) raises "at-least needs a non-negative integer"
  to-smt([exactly(0): p]) is "((_ pbeq 0 1) p)"
  # sum and product take numeric elements; a Bool counts as 0 or 1
  to-smt([sum: x, 1, p]) is "(+ x 1 (ite p 1 0))"
  to-smt([product: p, 2]) is "(* (ite p 1 0) 2)"
  to-smt([sum: x, r, 1/2]) is "(+ x r (/ 1 2))"
  [sum: x, "a"] raises "element 2 of 2 of sum cannot be used as a Z3 term"
  [product: x, "a"] raises "element 2 of 2 of product cannot be used as a Z3 term"
  # all-different: any sort, but all of one kind
  to-smt([all-different: x, r, 3]) is "(distinct x r 3)"
  to-smt([all-different: p, q]) is "(distinct p q)"
  to-smt([all-different: p, true]) is "(distinct p true)"
  [all-different: p, x] raises "p is a Bool but x is an Int"
  [all-different: x, y, p] raises "x is an Int but p is a Bool"
  [all-different: x, "a"] raises "element 2 of 2 of all-different cannot be used as a Z3 term"
  # ite: Bool condition, branches of one kind, result of that kind
  ite(x, x, y) raises "the condition of ite should be a Bool term, but x is an Int"
  ite(p, p, y) raises "p is a Bool but y is an Int"
  ite(p, x, q) raises "x is an Int but q is a Bool"
  to-smt(ite(p, x, r)) is "(ite p x r)"
  to-smt(ite(p, true, q)) is "(ite p true q)"
  to-smt(ite(p, x, y) + 1) is "(+ (ite p x y) 1)"
  to-smt(ite(p, q, s).negate()) is "(not (ite p q s))"
  ite(p, x, y).negate() raises "should be a Bool term, but (ite p x y) is an Int"
  (ite(p, q, s) < 1) raises "the left side of < is the Bool term (ite p q s)"
  to-smt(ite(p, x, r) / 2) is "(/ (ite p x r) 2)"
end

check "docs: Constructors: empty constructors have their mathematical meaning":
  to-smt([conj: ]) is "true"
  to-smt([disj: ]) is "false"
  to-smt([sum: ]) is "0"
  to-smt([product: ]) is "1"
  to-smt([all-different: ]) is "true"
  to-smt([at-most(0): ]) is "true"
  to-smt([at-most(3): ]) is "true"
  to-smt([at-least(0): ]) is "true"
  to-smt([at-least(1): ]) is "false"
  to-smt([exactly(0): ]) is "true"
  to-smt([exactly(1): ]) is "false"
  to-smt([exactly(2): ]) is "false"
  # the same through .over on an empty list
  to-smt(for conj.over(st from empty): seated(st, 1) end) is "true"
  to-smt(for sum.over(st from empty): age(st) end) is "0"
  to-smt(for at-least(1).over(st from empty): seated(st, 1) end) is "false"
end

# ---------------------------------------------------------------------------
# Terms: Building Terms from Lists

check "docs: Building Terms from Lists: .over on every constructor":
  to-smt(for conj.over(st from students): seated(st, 1) end) is "(and |seated[17,1]| |seated[18,1]|)"
  to-smt(for disj.over(st from students): seated(st, 1) end) is "(or |seated[17,1]| |seated[18,1]|)"
  to-smt(for sum.over(st from students): age(st) end) is "(+ |age[17]| |age[18]|)"
  to-smt(for product.over(v from [list: x, y]): v end) is "(* x y)"
  to-smt(for all-different.over(st from students): age(st) end) is "(distinct |age[17]| |age[18]|)"
  one-lab-for-17 = for exactly(1).over(l from labs): seated(17, l) end
  to-smt(one-lab-for-17) is "((_ pbeq 1 1 1) |seated[17,1]| |seated[17,2]|)"
  to-smt(for at-most(1).over(l from labs): seated(17, l) end) is "((_ at-most 1) |seated[17,1]| |seated[17,2]|)"
  to-smt(for at-least(1).over(l from labs): seated(17, l) end) is "((_ at-least 1) |seated[17,1]| |seated[17,2]|)"
  # the body's values are checked like elements
  (for conj.over(st from students): age(st) end) raises "element 1 of 2 of conj should be a Bool term"
  satisfiable([constraints: one-lab-for-17, seated(17, 1), seated(17, 2)]) is false
end

check "docs: Building Terms from Lists: the aggregators":
  total-age = for sum-over(st from students): age(st) end
  all-adults = for all-of(st from students): age(st) >= 18 end
  lab-1-used = for any-of(st from students): seated(st, 1) end
  to-smt(total-age) is "(+ |age[17]| |age[18]|)"
  to-smt(all-adults) is "(and (>= |age[17]| 18) (>= |age[18]| 18))"
  to-smt(lab-1-used) is "(or |seated[17,1]| |seated[18,1]|)"
  # each is a single term
  total-age satisfies is-Term
  all-adults satisfies is-Term
  to-smt(all-adults.negate()) is "(not (and (>= |age[17]| 18) (>= |age[18]| 18)))"
  to-smt(total-age / 2) is "(div (+ |age[17]| |age[18]|) 2)"
  # over the pairs from two lists
  to-smt(for sum-over2(st from students, l from labs): seated(st, l) end)
    is "(+ (ite |seated[17,1]| 1 0) (ite |seated[17,2]| 1 0) (ite |seated[18,1]| 1 0) (ite |seated[18,2]| 1 0))"
  to-smt(for all-of2(st from students, l from labs): seated(st, l) end)
    is "(and |seated[17,1]| |seated[17,2]| |seated[18,1]| |seated[18,2]|)"
  to-smt(for any-of2(st from students, l from labs): seated(st, l) end)
    is "(or |seated[17,1]| |seated[17,2]| |seated[18,1]| |seated[18,2]|)"
  to-smt(for sum-over(st from empty): age(st) end) is "0"
  to-smt(for all-of(st from empty): seated(st, 1) end) is "true"
  to-smt(for any-of(st from empty): seated(st, 1) end) is "false"
  (for all-of(st from students): age(st) end) raises "element 1 of 2 of all-of should be a Bool term"
  (for any-of2(st from students, l from labs): l end) raises "element 1 of 4 of any-of2 should be a Bool term"
  (for sum-over(st from students): "a" end) raises "element 1 of 2 of sum-over cannot be used as a Z3 term"
  solve([constraints: total-age.eq(40), age(17).eq(18)]).model.num(age(18)) is 22
end

check "docs: Building Terms from Lists: each-of produces Constraints, not a term":
  one-lab-each = for each-of(st from students):
    for exactly(1).over(l from labs): seated(st, l) end
  end
  is-Term(one-lab-each) is false
  one-lab-each.length() is 2
  (one-lab-each + [constraints: p]).length() is 3
  one-lab-each.solve() satisfies is-sat
  (for each-of2(st from students, l from labs): seated(st, l) end).length() is 4
  (for each-of(st from students): seated(st, 1) end).solve().model.bool(seated(18, 1)) is true
end

# ---------------------------------------------------------------------------
# Terms: Inspecting Terms

check "docs: Inspecting Terms":
  x.to-smt() is "x"
  to-smt(x) is "x"
  (x + 1).to-smt() is "(+ x 1)"
  to-smt(x + 1) is (x + 1).to-smt()
  is-Term(x) is true
  is-Term(x + 1) is true
  is-Term(lift(3)) is true
  is-Term(3) is false
  is-Term("x") is false
  is-Term([constraints: p]) is false
  fun in-lab(st :: Number, l :: Number) -> Term: seated(st, l) end
  in-lab(17, 1) is seated(17, 1)
end

# ---------------------------------------------------------------------------
# Constraints

check "docs: Constraints: the constraints constructor":
  cs = [constraints: x > 2, (x + y).eq(10), [at-most(1): p, q]]
  cs.length() is 3
  [constraints: ].length() is 0
  # elements are Bool terms, or Constraints values spliced in
  [constraints: x > 2, [constraints: p, q]].length() is 3
  [constraints: [constraints: p, [constraints: q, s]], x > 1].length() is 4
  [constraints: x + y] raises "element 1 of 1 of constraints should be a Bool term, but (+ x y) is an Int"
  [constraints: p, r] raises "element 2 of 2 of constraints should be a Bool term, but r is a Real"
  [constraints: p, 3] raises "element 2 of 2 of constraints is not a constraint: 3"
  [constraints: p, "q"] raises "is not a constraint"
  # a Pyret Boolean is refused, with a hint about .eq
  [constraints: x == 3] raises "element 1 of 1 of constraints is the Pyret Boolean false, not a Z3 constraint"
  [constraints: x == 3] raises "use .eq, not =="
  [constraints: p, x == x] raises "element 2 of 2 of constraints is the Pyret Boolean true"
end

check "docs: Constraints: combining, each-of, length, and script":
  one-value-per-cell = [constraints: x > 0]
  each-value-once-per-row = [constraints: y > 0]
  each-value-once-per-column = [constraints: p, q]
  rules = one-value-per-cell + each-value-once-per-row + each-value-once-per-column
  rules.length() is 4
  rules.solve() satisfies is-sat
  ([constraints: p] + p) raises "Only constraints can be added"
  ([constraints: p] + [list: q]) raises "Only constraints can be added"
  # each-of: one constraint per element, or per pair
  one-lab-each = for each-of(st from students):
    for exactly(1).over(l from labs): seated(st, l) end
  end
  one-lab-each.length() is 2
  (for each-of2(st from students, l from labs): seated(st, l) end).length() is 4
  # a body producing Constraints is joined in
  (for each-of(st from students): [constraints: age(st) > 0, age(st) < 100] end).length() is 4
  (for each-of2(st from students, l from labs): [constraints: seated(st, l), age(st) > 0] end).length() is 8
  (for each-of(i from [list: 1, 2]): i == 1 end) raises "element 1 of 2 of each-of is the Pyret Boolean true"
  (for each-of(st from students): age(st) end) raises "element 1 of 2 of each-of should be a Bool term"
  # the script solve would send, declarations included
  [constraints: x > 2].script() is "(declare-const x Int)\n(assert (> x 2))\n(check-sat)"
  one-lab-each.script() satisfies string-contains(_, "(declare-const |seated[17,1]| Bool)")
  one-lab-each.script() satisfies string-contains(_, "(assert ((_ pbeq 1 1 1) |seated[17,1]| |seated[17,2]|))")
end

# ---------------------------------------------------------------------------
# Solving

check "docs: Solving: functions and methods":
  cs = [constraints: x >= 0, x <= 10, y >= 0, y <= 10]
  solve(cs) satisfies is-sat
  cs.solve() satisfies is-sat
  maximize(cs, x + y).model.num(x) is 10
  maximize(cs, x + y).model.num(y) is 10
  cs.maximize(x + y).model.num(x) is 10
  minimize(cs, x + y).model.num(x) is 0
  cs.minimize(x + y).model.num(y) is 0
  satisfiable(cs) is true
  cs.satisfiable() is true
  satisfiable([constraints: x > 5, x < 5]) is false
  [constraints: x > 5, x < 5].satisfiable() is false
  ss = [softs: soft(x.eq(3), 1)]
  solve-soft(cs, ss).model.num(x) is 3
  cs.solve-soft(ss).model.num(x) is 3
  # valid is a function only
  valid(p.or-else(p.negate())) is true
  valid(p) is false
  valid((x + 1) > x) is true
  valid(x) raises "the argument of valid should be a Bool term"
  # valid(t) asks whether t.negate() is unsatisfiable
  valid(p.implies(p)) is not(satisfiable([constraints: p.implies(p).negate()]))
  valid(p.implies(q)) is not(satisfiable([constraints: p.implies(q).negate()]))
end

check "docs: Solving: objectives, and which variables are declared":
  # the objective is a numeric term, or a Bool term counting as 0/1
  maximize([constraints: r > 0, r < 1, (r * 4).eq(3)], r).model.num(r) is 3/4
  maximize([constraints: (p + q) <= 1], q).model.bool(q) is true
  minimize([constraints: [at-least(1): p, q]], p).model.bool(p) is false
  maximize([constraints: x <= 10], 3) raises "The objective of maximize must be a Z3 term"
  minimize([constraints: x <= 10], "x") raises "The objective of minimize must be a Z3 term"
  # only the variables that occur in the problem are declared and in the model
  m = solve([constraints: x > 2, (x + y).eq(10)]).model
  m.names().sort() is [list: "x", "y"]
  m.num(z) raises "does not occur in the problem"
  [constraints: x > 2].script() satisfies string-contains(_, "(declare-const x Int)")
  string-contains([constraints: x > 2].script(), "y") is false
end

# ---------------------------------------------------------------------------
# Results

check "docs: Results":
  cs = [constraints: x > 2, x < 4]
  res = solve(cs)
  res satisfies is-sat
  res.model.num(x) is 3
  solve([constraints: x > 5, x < 5]) is unsat
  solve([constraints: x > 5, x < 5]) satisfies is-unsat
  is-sat(unsat) is false
  is-unknown(unsat) is false
  unknown("why") satisfies is-unknown
  unknown("why").reason is "why"
  sat(res.model) is res
  # solve-soft, maximize, and minimize also return a Result
  solve-soft(cs, [softs: soft(p, 1)]) satisfies is-sat
  maximize(cs, x) satisfies is-sat
  minimize(cs, x) satisfies is-sat
  maximize([constraints: x > 5, x < 5], x) is unsat
  cases (Result) res:
    | sat(m) => m.num(x)
    | unsat => -1
    | unknown(_) => -2
  end is 3
end

# ---------------------------------------------------------------------------
# Models

check "docs: Models":
  m = solve([constraints: x.eq(3), p, r.eq(1/2)]).model
  m.num(x) is 3
  m.bool(p) is true
  m.num(r) is 1/2
  m.value(x) is v-num(3)
  m.value(p) is v-bool(true)
  m.value(r) is v-num(1/2)
  m.names().sort() is [list: "p", "r", "x"]
  m.names().length() is 3
  # a variable not in the problem; num of a Bool; bool of a number
  m.num(y) raises "does not occur in the problem"
  m.bool(q) raises "does not occur in the problem"
  m.value(y) raises "does not occur in the problem"
  m.num(p) raises "is not an Int or a Real"
  m.bool(x) raises "is not a Bool"
  m.bool(r) raises "is not a Bool"
  m.num(x + 1) raises "Expected a variable"
  # by name
  model-num(m, "x") is 3
  model-bool(m, "p") is true
  model-num(m, "r") is 1/2
  model-num(m, "p") raises "is not an Int or a Real"
  model-bool(m, "x") raises "is not a Bool"
  # a Real's value is a rational
  solve([constraints: (r * 2).eq(1)]).model.num(r) is 1/2
  solve([constraints: (r * 3).eq(-2)]).model.num(r) is -2/3
  solve([constraints: r.eq(-1/2)]).model.value(r) is v-num(-1/2)
end

# ---------------------------------------------------------------------------
# Values

check "docs: Values":
  v-num(3).n is 3
  v-bool(true).b is true
  v-raw("text").s is "text"
  m = solve([constraints: x.eq(-7), p.negate()]).model
  m.value(x) is v-num(-7)
  m.value(p) is v-bool(false)
  m.value(x) satisfies is-v-num
  # an algebraic real comes back as Z3's own text, and num raises
  m2 = solve([constraints: (r * r).eq(2), r > 0]).model
  m2.value(r) satisfies is-v-raw
  m2.value(r) is v-raw("(root-obj (+ (^ x 2) (- 2)) 2)")
  m2.num(r) raises "is not an Int or a Real"
  model-num(m2, "r") raises "is not an Int or a Real"
end

# ---------------------------------------------------------------------------
# Soft Constraints

check "docs: Soft Constraints":
  cs = [constraints: [at-most(1): p, q]]
  ss = [softs: soft(p, 1), soft(q, 5)]
  # the total weight of violated soft constraints is minimised
  m = solve-soft(cs, ss).model
  m.bool(q) is true
  m.bool(p) is false
  cs.solve-soft(ss).model.bool(q) is true
  cs.solve-soft([softs: soft(p, 5), soft(q, 1)]).model.bool(p) is true
  # violating one of weight 3 beats violating two of weight 2 each
  m2 = solve-soft([constraints: p.implies(q.negate()), p.implies(s.negate())],
    [softs: soft(p, 3), soft(q, 2), soft(s, 2)]).model
  m2.bool(p) is false
  m2.bool(q) is true
  m2.bool(s) is true
  # the hard constraints still hold
  solve-soft([constraints: p.negate()], [softs: soft(p, 100)]).model.bool(p) is false
  # soft(t, w): a Bool term and a positive weight
  soft(p, 0) raises "must be positive"
  soft(p, -1) raises "must be positive"
  soft(x, 1) raises "the constraint of soft should be a Bool term, but x is an Int"
  soft("p", 1) raises "the constraint of soft cannot be used as a Z3 term"
  # [softs: ...] collects Soft values and other Softs; + joins two
  [softs: soft(p, 1), [softs: soft(q, 2), soft(s, 3)]].items.length() is 3
  ([softs: soft(p, 1)] + [softs: soft(q, 2)]).items.length() is 2
  ([softs: soft(p, 1)] + soft(q, 2)) raises "Only soft constraints can be added"
  [softs: p] raises "element 1 of 1 of softs is not a soft constraint"
  [softs: ].items.length() is 0
  # a weighted sum as an objective says the same thing
  maximize(cs, (p * 1) + (q * 5)).model.bool(q) is true
  maximize(cs, (p * 5) + (q * 1)).model.bool(p) is true
end

# ---------------------------------------------------------------------------
# Escape Hatches

check "docs: Escape Hatches: raw":
  to-smt(raw("(> x 100)")) is "(> x 100)"
  raw("(> x 100)") satisfies is-Term
  # raw text has no sort and combines with anything
  to-smt([conj: p, raw("(> x 100)")]) is "(and p (> x 100))"
  to-smt(x + raw("y")) is "(+ x y)"
  to-smt(raw("q").and-also(p)) is "(and q p)"
  to-smt(raw("q") < 3) is "(< q 3)"
  to-smt(ite(raw("c"), x, y)) is "(ite c x y)"
  [constraints: raw("(> x 100)")].length() is 1
  # variables only in raw text are not declared; mentioning them in a term declares them
  solve([constraints: raw("(> x 100)"), x < 200]).model.num(x) is%(_ > _) 100
  solve([constraints: raw("(> zz 100)")]) raises "Z3 rejected the SMT-LIB script"
  solve([constraints: raw("(> zz 100)")]) raises "Script was:"
  solve([constraints: raw("(> zz 100)")]) raises "(assert (> zz 100))"
  [constraints: raw("(> zz 100)")].script() is "(assert (> zz 100))\n(check-sat)"
end

check "docs: Escape Hatches: smt-eval, script, and z3-version":
  smt-eval("(check-sat)") is "sat\n"
  smt-eval("(declare-const a Int)(assert (> a 2))(assert (< a 2))(check-sat)") is "unsat\n"
  # a fresh context each time: a declaration does not carry over
  smt-eval("(declare-const a Int)(check-sat)") is "sat\n"
  smt-eval("(declare-const a Int)(check-sat)") is "sat\n"
  smt-eval("(assert (> a 2))(check-sat)") satisfies string-contains(_, "error")
  # cs.script() is a script smt-eval accepts
  smt-eval([constraints: x > 2, x < 4].script()) is "sat\n"
  smt-eval([constraints: x > 5, x < 5].script()) is "unsat\n"
  is-string(z3-version()) is true
  string-contains(z3-version(), ".") is true
end

# ---------------------------------------------------------------------------
# Errors

check "docs: Errors: each listed case raises a located error":
  # not a term, number, or Boolean
  [conj: p, "s", q] raises "element 2 of 3 of conj cannot be used as a Z3 term"
  # a Pyret Boolean as a constraint
  [constraints: x == 3] raises "is the Pyret Boolean false, not a Z3 constraint"
  [constraints: x == 3] raises "use .eq, not =="
  # wrong sort for the position
  [conj: 1] raises "element 1 of 1 of conj should be a Bool term, but 1 is an Int"
  (p < 1) raises "the left side of < is the Bool term p"
  x.eq(p) raises "Ill-sorted term: in (= x p), x is an Int but p is a Bool"
  ite(p, x, q) raises "Ill-sorted term: in (ite p x q), x is an Int but q is a Bool"
  r.modulo(2) raises "Ill-sorted term: (mod r 2) needs Int operands, but one is a Real"
  # cardinality counts and soft weights
  exactly(-1) raises "needs a non-negative integer"
  at-most(3/2) raises "needs a non-negative integer"
  soft(p, 0) raises "must be positive"
  # names, two sorts, family indices
  bool-var("") raises "non-empty"
  int-var("a|b") raises "may not contain"
  int-var("a\\b") raises "may not contain"
  solve([constraints: int-var("v").eq(1), bool-var("v")]) raises "two sorts"
  cost("c") raises "is not in the family's index set"
  # models
  m = solve([constraints: x.eq(1), p]).model
  m.num(z) raises "does not occur in the problem"
  m.num(p) raises "is not an Int or a Real"
  m.bool(x) raises "is not a Bool"
  # Z3 rejecting a script, only through raw: Z3's message and the whole script
  solve([constraints: raw("(> zz 100)")]) raises "Z3 rejected the SMT-LIB script"
  solve([constraints: raw("(> zz 100)")]) raises "zz"
  solve([constraints: raw("(> zz 100)")]) raises "Script was:"
  solve([constraints: raw("(> zz 100)")]) raises "(assert (> zz 100))"
end

# ---------------------------------------------------------------------------
# Pitfalls

check "docs: Pitfalls: operators on the left, and Pyret Booleans":
  to-smt(x * 3) is "(* x 3)"
  (3 * x) raises-satisfies lam(_): true end
  to-smt(lift(3) * x) is "(* 3 x)"
  to-smt([product: 3, x]) is "(* 3 x)"
  (x == 3) is false
  is-boolean(x == 3) is true
  [constraints: x == 3] raises "element 1 of 1 of constraints is the Pyret Boolean false, not a Z3 constraint"
  [constraints: x == 3] raises "to compare terms use .eq, not =="
  to-smt(x.eq(3)) is "(= x 3)"
  ((x > 2) and (y > 2)) raises-satisfies lam(_): true end
  to-smt((x > 2).and-also(y > 2)) is "(and (> x 2) (> y 2))"
  [constraints: x > 2, y > 2].length() is 2
end

check "docs: Pitfalls: chained comparisons, if, division, models, names":
  (x > y > 2) raises "the left side of > is the Bool term (> x y); chained comparisons such as x > y > 2 are not supported, write (x > y).and-also(y > 2)"
  to-smt((x > y).and-also(y > 2)) is "(and (> x y) (> y 2))"
  # elsewhere a Bool term in arithmetic is 0 or 1; order comparisons alone refuse it
  to-smt((x > y) + 1) is "(+ (ite (> x y) 1 0) 1)"
  # if does not build a term
  (if p: x else: y end) raises-satisfies lam(_): true end
  to-smt(ite(p, x, y)) is "(ite p x y)"
  # division rounds with Int operands
  to-smt(x / 2) is "(div x 2)"
  solve([constraints: x.eq(7), (x / 2).eq(y)]).model.num(y) is 3
  to-smt(x / 1/2) is "(/ x (/ 1 2))"
  to-smt(r / 2) is "(/ r 2)"
  solve([constraints: r.eq(7), (r / 2).eq(r2)]).model.num(r2) is 7/2
  # only the variables in the problem are in the model
  solve([constraints: x.eq(7)]).model.num(z) raises "does not occur in the problem"
  # a variable is its name
  int-var("x") is int-var("x")
  solve([constraints: int-var("x") > 2, int-var("x") < 4]).model.names() is [list: "x"]
  solve([constraints: int-var("x").eq(1), bool-var("x")]) raises "two sorts"
end

# ---------------------------------------------------------------------------
# Solving: unknown. Kept last: the resource limit set here is a global Z3
# option, which outlives the call that set it, so it is reset at the end.

check "docs: Solving: satisfiable and valid raise on unknown":
  limited = raw("true)\n(set-option :rlimit 1")
  hard = [constraints: limited, (r * r).eq(2), r > 0]
  solve(hard) satisfies is-unknown
  satisfiable(hard) raises "Z3 could not decide satisfiability"
  # valid asserts (not t), so the splice has to close that instead
  limited-valid = raw("(> r 0))))\n(set-option :rlimit 1)\n(assert (not (or (> r 0)")
  valid([disj: (r * r).eq(2), limited-valid]) raises "Z3 could not decide satisfiability"
  smt-eval("(set-option :rlimit 0)(check-sat)") is "sat\n"
  solve([constraints: (r * r).eq(2), r > 0]) satisfies is-sat
end
