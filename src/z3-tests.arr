use context starter2024

# Tests for the public surface of z3.arr and for z3-shim.js.
# Run from this directory:  pyret -q z3-tests.arr
# The serializer and the sort checker are exercised through the public
# constructors, which are the only way to build terms.

include file("../z3.arr")
import js-file("../z3-shim") as Shim

x = int-var("x")
y = int-var("y")
p = bool-var("p")
q = bool-var("q")

check "shim: version and raw evaluation":
  string-contains(Shim.z3-version(), "4.") is true
  z3-version() is Shim.z3-version()
  smt-eval("(check-sat)") is "sat\n"
  smt-eval("(declare-const a Int)(assert (> a 2))(assert (< a 2))(check-sat)") is "unsat\n"
  string-contains(smt-eval("(this-is-not-a-command)"), "unsupported") is true
  # a fresh context each time: declarations do not leak between calls
  smt-eval("(declare-const a Int)(check-sat)") is "sat\n"
  smt-eval("(declare-const a Int)(check-sat)") is "sat\n"
end

check "shim: model values":
  out = Shim.smt-solve(
    "(declare-const n Int)(declare-const m Int)(declare-const b Bool)(declare-const r Real)"
      + "(assert (= n (- 7)))(assert (= m 12345678901234567890))(assert b)(assert (= r (/ (- 1) 2)))(check-sat)",
    [list: "n", "m", "b", "r"])
  out.status is "sat"
  out.values.length() is 4
  v = out.values
  v.get(0).name is "n"
  v.get(0).kind is "number"
  v.get(0).value is -7
  v.get(1).value is 12345678901234567890
  v.get(2).kind is "boolean"
  v.get(2).value is true
  v.get(3).kind is "number"
  v.get(3).value is -1/2
  quoted = Shim.smt-solve("(declare-const |CSCI 0190| Bool)(assert |CSCI 0190|)(check-sat)", [list: "CSCI 0190"])
  quoted.values.get(0).name is "CSCI 0190"
  quoted.values.get(0).value is true
  Shim.smt-solve("(declare-const n Int)(assert (> n 0))(assert (< n 0))(check-sat)", [list: "n"]).status is "unsat"
  Shim.smt-solve("(oops)", empty).status is "error"
end

# ---------------------------------------------------------------------------
# Terms

check "variables":
  to-smt(x) is "x"
  to-smt(int-var("CSCI 0190")) is "|CSCI 0190|"
  to-smt(int-var("a-b_c?")) is "a-b_c?"
  to-smt(int-var("1x")) is "|1x|"
  int-var("a|b") raises "may not contain"
  bool-var("") raises "non-empty"
  bool-family("f", [list: 1])(1).sort is bool-sort
  to-smt(lift(-3/4)) is "(- (/ 3 4))"
  to-smt(lift(2)) is "2"
  to-smt(lift(false)) is "false"
end

check "serializer, through the public constructors":
  r = real-var("r")
  to-smt([conj: p]) is "p"
  to-smt([sum: ]) is "0"
  to-smt([product: ]) is "1"
  to-smt([product: x]) is "x"
  to-smt(x / y) is "(div x y)"
  to-smt(r / 2) is "(/ r 2)"
  to-smt(x / r) is "(/ x r)"
  to-smt((x + r) / 2) is "(/ (+ x r) 2)"
  to-smt(x / 1/2) is "(/ x (/ 1 2))"
  to-smt([all-different: x, y]) is "(distinct x y)"
  to-smt([all-different: x]) is "true"
  to-smt([all-different: ]) is "true"
  to-smt([all-different: x, y, 3]) is "(distinct x y 3)"
  to-smt([at-least(0): ]) is "true"
  to-smt([at-least(1): ]) is "false"
  to-smt([exactly(0): ]) is "true"
  to-smt([exactly(1): ]) is "false"
  to-smt([at-most(0): ]) is "true"
  to-smt(ite(p, 1, 0)) is "(ite p 1 0)"
  to-smt(ite(p, true, q)) is "(ite p true q)"
end

check "sort checker, through the public constructors":
  r = real-var("r")
  # Int and Real mix; Bool does not mix with numbers
  (x + r).to-smt() is "(+ x r)"
  (x < r).to-smt() is "(< x r)"
  x.eq(r).to-smt() is "(= x r)"
  ite(p, x, r).to-smt() is "(ite p x r)"
  [all-different: p, x] raises "p is a Bool but x is an Int"
  [all-different: x, p] raises "x is an Int but p is a Bool"
  [constraints: [all-different: p, q]].length() is 1
  # raw text is compatible with anything, and its errors are Z3's
  [conj: p, raw("q")].to-smt() is "(and p q)"
  (x + raw("y")).to-smt() is "(+ x y)"
  # nested errors name the innermost offending subterm
  p.negate().and-also(p + x) raises "the right side of .and-also should be a Boolean term, but (+ (ite p 1 0) x) is an Int"
  [conj: p, (x < y).and-also(x)] raises "the right side of .and-also should be a Boolean term, but x is an Int"
end

check "operators on terms":
  to-smt((x + 1) <= 3) is "(<= (+ x 1) 3)"
  to-smt((x * 2) - y) is "(- (* x 2) y)"
  to-smt(x / 2) is "(div x 2)"
  to-smt(x < 1/2) is "(< x (/ 1 2))"
  to-smt(x > y) is "(> x y)"
  to-smt(x >= 0) is "(>= x 0)"
  to-smt(x.eq(3)) is "(= x 3)"
  to-smt(x.neq(y)) is "(not (= x y))"
  to-smt(x.neg()) is "(- x)"
  to-smt(p.negate()) is "(not p)"
  to-smt(p.and-also(q)) is "(and p q)"
  to-smt(p.or-else(false)) is "(or p false)"
  to-smt(p.implies(q)) is "(=> p q)"
  to-smt(p.iff(q)) is "(= p q)"
  to-smt(p.eq(q)) is "(= p q)"
  (x + y).to-smt() is "(+ x y)"
  # Boolean terms count as 0/1 in arithmetic
  to-smt((p + q) <= 1) is "(<= (+ (ite p 1 0) (ite q 1 0)) 1)"
  to-smt(p * 3) is "(* (ite p 1 0) 3)"
  to-smt((x < y) + 1) is "(+ (ite (< x y) 1 0) 1)"
  to-smt(lift(2)) is "2"
  to-smt(lift(-3)) is "(- 3)"
  to-smt(lift(2.5)) is "(/ 5 2)"
  to-smt(lift(true)) is "true"
  to-smt(ite(p, x, 0)) is "(ite p x 0)"
  to-smt(raw("(> x 100)")) is "(> x 100)"
end

check "operators catch mistakes":
  lift("no") raises "cannot be used as a Z3 term"
  (x + "one") raises "the right side of + cannot be used as a Z3 term"
  p.and-also(x) raises "the right side of .and-also should be a Boolean term, but x is an Int"
  x.or-else(p) raises "the left side of .or-else should be a Boolean term"
  x.negate() raises "the term before .negate should be a Boolean term"
  x.eq(p) raises "x is an Int but p is a Bool"
  p.implies(1) raises "the right side of .implies should be a Boolean term, but 1 is an Int"
  ite(x, x, y) raises "the condition of ite should be a Boolean term"
  ite(p, p, y) raises "p is a Bool but y is an Int"
  # order comparisons refuse Boolean operands on either side; Pyret parses
  # x > y > 2 as (x > y) > 2, which would otherwise be silently false
  (x > y > 2) raises "chained comparisons such as x > y > 2 are not supported"
  (x > y > 2) raises "the left side of >"
  (x < p) raises "the right side of <"
  (p <= 1) raises "the left side of <="
  (x < y < 2) raises "the left side of < is the Boolean term (< x y)"
  (x <= p) raises "the right side of <= is the Boolean term p"
  (p > 1) raises "the left side of > is the Boolean term p"
  (x >= y >= 0) raises "the left side of >= is the Boolean term (>= x y)"
  (x >= p) raises "the right side of >="
  (x > true) raises "the right side of > is the Boolean term true"
  # arithmetic on Booleans is still fine; the sum is an Int term
  ((p + q) <= 1).to-smt() is "(<= (+ (ite p 1 0) (ite q 1 0)) 1)"
end

check "constructor notation":
  to-smt([conj: p, q, true]) is "(and p q true)"
  to-smt([disj: p, q]) is "(or p q)"
  to-smt([conj: ]) is "true"
  to-smt([disj: ]) is "false"
  to-smt([sum: x, 1, p]) is "(+ x 1 (ite p 1 0))"
  to-smt([product: x, 2]) is "(* x 2)"
  to-smt([sum: x, y, x, y, x, y]) is "(+ x y x y x y)"
  to-smt([exactly(1): p, q]) is "((_ pbeq 1 1 1) p q)"
  to-smt([at-most(2): p, q, true]) is "((_ at-most 2) p q true)"
  to-smt([at-least(1): p]) is "((_ at-least 1) p)"
  to-smt([at-most(1): ]) is "true"
  to-smt(for exactly(1).over(v from [list: p, q]): v end) is "((_ pbeq 1 1 1) p q)"
  to-smt(for conj.over(v from [list: x, y]): v > 0 end) is "(and (> x 0) (> y 0))"
  [conj: p, x] raises "element 2 of 2 of conj should be a Boolean term, but x is an Int"
  [disj: p, 1] raises "element 2 of 2 of disj should be a Boolean term"
  [sum: x, "a"] raises "element 2 of 2 of sum cannot be used as a Z3 term"
  [exactly(1): p, x] raises "element 2 of 2 of exactly(1) should be a Boolean term"
  exactly(-1) raises "exactly needs a non-negative integer"
  at-most(1/2) raises "at-most needs a non-negative integer"
end

check "aggregators with for":
  vs = map(lam(i): int-var("v" + num-to-string(i)) end, range(0, 3))
  to-smt(for sum-over(v from vs): v * 2 end) is "(+ (* v0 2) (* v1 2) (* v2 2))"
  to-smt(for sum-over(v from empty): v end) is "0"
  to-smt(for all-of(v from vs): v >= 0 end) is "(and (>= v0 0) (>= v1 0) (>= v2 0))"
  to-smt(for any-of(v from vs): v.eq(7) end) is "(or (= v0 7) (= v1 7) (= v2 7))"
  (for each-of(v from vs): v <= 9 end).length() is 3
  to-smt(for sum-over2(i from [list: 1, 2], j from [list: 10]): int-var("w" + num-to-string(i + j)) end)
    is "(+ w11 w12)"
  to-smt(for all-of2(a from [list: p], b from [list: q, true]): a.implies(b) end)
    is "(and (=> p q) (=> p true))"
  (for each-of2(a from [list: 1, 2], b from [list: 1, 2, 3]): x <= (a * b) end).length() is 6
  to-smt(for any-of2(a from [list: p], b from [list: q]): a.and-also(b) end) is "(and p q)"
  (for all-of(v from vs): v end) raises "element 1 of 3 of all-of should be a Boolean term"
  (for each-of(i from [list: 1, 2]): i == 1 end) raises "element 1 of 2 of each-of is the Pyret Boolean true"
end

check "variable families":
  seated = bool-family2("seated", [list: 1, 2], [list: "a", "b"])
  to-smt(seated(1, "a")) is "|seated[1,a]|"
  seated(2, "b").sort is bool-sort
  seated(3, "a") raises "index"
  seated(1, "c") raises "index"
  amount = int-family("amount", [list: "food", "rent"])
  to-smt(amount("rent") + amount("food")) is "(+ |amount[rent]| |amount[food]|)"
  amount("fun") raises "index"
  real-family2("r", [list: 1], [list: 2])(1, 2).sort is real-sort
end

# ---------------------------------------------------------------------------
# Constraints

check "the constraints constructor":
  [constraints: x > 7, y > 0].length() is 2
  [constraints: ].length() is 0
  [constraints: [constraints: p, q], x > 1].length() is 3
  ([constraints: p] + [constraints: q]).length() is 2
  [constraints: lift(true)].length() is 1
  [constraints: x > 2].script() is "(declare-const x Int)\n(assert (> x 2))\n(check-sat)"
  [constraints: x > 7, x + y] raises "element 2 of 2 of constraints should be a Boolean term, but (+ x y) is an Int"
  [constraints: x == 3] raises "element 1 of 1 of constraints is the Pyret Boolean false"
  [constraints: x == 3] raises "use .eq, not =="
  [constraints: p, 3] raises "element 2 of 2 of constraints is not a constraint: 3"
  [constraints: p, "q"] raises "is not a constraint"
  [constraints: p.and-also(x)] raises "the right side of .and-also"
  ([constraints: p] + p) raises "Only constraints can be added"
  [constraints: int-var("v").eq(1), bool-var("v")].script() raises "two sorts"
end

check "soft constraints":
  [softs: soft(p, 1), soft(q, 5)].items.length() is 2
  ([softs: soft(p, 1)] + [softs: soft(q, 2)]).items.length() is 2
  soft(x, 1) raises "the constraint of soft should be a Boolean term"
  soft(p, 0) raises "must be positive"
  [softs: p] raises "element 1 of 1 of softs is not a soft constraint"
end

check "solve, as functions and as methods":
  r1 = solve([constraints: x > 2, x < 4])
  r1 satisfies is-sat
  model-num(r1.model, "x") is 3
  [constraints: x > 2, x < 4].solve().model.num(x) is 3
  solve([constraints: x > 2, x < 2]) is unsat
  [constraints: x > 2, x < 2].solve() is unsat
  satisfiable([constraints: p, p.negate()]) is false
  [constraints: p, p.negate()].satisfiable() is false
  valid(p.or-else(p.negate())) is true
  valid(p) is false
  valid(x) raises "the argument of valid should be a Boolean term"
  # a sat result mentions every variable, including ones only in soft terms
  r2 = solve-soft([constraints: [at-most(1): p, q]], [softs: soft(p, 1), soft(q, 5)])
  model-bool(r2.model, "q") is true
  model-bool(r2.model, "p") is false
  [constraints: [at-most(1): p, q]].solve-soft([softs: soft(p, 5), soft(q, 1)]).model.bool(p) is true
  r3 = maximize([constraints: x <= 10, x >= 0], x)
  model-num(r3.model, "x") is 10
  [constraints: x <= 10, x >= 0].maximize(x).model.num(x) is 10
  r4 = minimize([constraints: x <= 10, x >= -4], x)
  model-num(r4.model, "x") is -4
  [constraints: x <= 10, x >= -4].minimize(x).model.num(x) is -4
  maximize([constraints: x <= 10], 3) raises "The objective of maximize must be a Z3 term"
  r5 = solve([constraints: [exactly(2): p, q, bool-var("s")], p.negate()])
  model-bool(r5.model, "q") is true
  model-bool(r5.model, "s") is true
  solve([constraints: raw("(> x 100)"), x < 200]) satisfies is-sat
  solve([constraints: raw("(> y 100)")]) raises "rejected"
  solve([list: x > 1]) raises-satisfies lam(_): true end   # a list is not Constraints
end

check "term-based model lookup":
  r = solve([constraints: (x + y).eq(10), x > 7, y > 0])
  r satisfies is-sat
  (r.model.num(x) + r.model.num(y)) is 10
  r.model.num(x) is%(_ > _) 7
  r.model.value(x) is v-num(r.model.num(x))
  r.model.num(p) raises "does not occur" # p is not in the problem at all
  r.model.num(x + 1) raises "Expected a variable"
  r2 = solve([constraints: p.or-else(q), p.negate()])
  r2.model.bool(q) is true
  r2.model.bool(p) is false
  r2.model.num(q) raises "not a number"
  r2.model.names() is [list: "p", "q"]
  model-bool(r2.model, "q") is true
  # a family end to end: exactly one of three, the cheapest wins
  choice = bool-family("choice", [list: "a", "b", "c"])
  costs = [list: {"a"; 5}, {"b"; 1}, {"c"; 3}]
  r3 = minimize(
    [constraints: for exactly(1).over(k from [list: "a", "b", "c"]): choice(k) end],
    for sum-over(c from costs): choice(c.{0}) * c.{1} end)
  r3.model.bool(choice("b")) is true
  r3.model.bool(choice("a")) is false
  # a Boolean objective is maximised as 0/1
  r4 = maximize([constraints: (p + q) <= 1], q)
  r4.model.bool(q) is true
  r4.model.bool(p) is false
end
