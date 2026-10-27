use context starter2024

# z3.arr: a typed Pyret interface to the Z3 SMT solver.
#
# Variables carry their sort; terms are built with the operators and
# constructors below; a problem is a `[constraints: ...]` value, which is
# solved with `solve`, `maximize`, `minimize`, or `solve-soft` (as functions
# or as methods). Every constructor checks what it is given, so mistakes are
# reported where they are made rather than by Z3.
#
# Example:
#   x = int-var("x")
#   cases (Result) solve([constraints: x > 2, x < 5]):
#     | sat(m) => m.num(x)      # 3, say
#     | unsat => ...
#     | unknown(why) => ...
#   end
#
# The solver runs through z3-shim.js, which loads the WebAssembly build of Z3.

provide:
  # variables
  int-var, bool-var, real-var,
  bool-family, int-family, real-family, bool-family2, int-family2, real-family2,
  # terms
  lift, ite, conj, disj, all-different, sum, product, exactly, at-most, at-least,
  sum-over, sum-over2, all-of, all-of2, any-of, any-of2, each-of, each-of2,
  # problems
  constraints, softs, soft,
  solve, solve-soft, maximize, minimize, satisfiable, valid,
  model-num, model-bool,
  # escape hatches
  raw, to-smt, smt-eval, z3-version,
  # types
  type Term, type Constraints, type Soft, type Softs, type Model,
  data Sort, data Value, data Result
end

import js-file("z3-shim") as Shim
import string-dict as SD
import lists as L

# ---------------------------------------------------------------------------
# Terms

data Sort:
  | int-sort
  | bool-sort
  | real-sort
end

data Term:
  # literals and variables
  | t-int(n :: Number)              # an integer literal
  | t-real(n :: Number)             # an exact real (rational) literal
  | t-bool(b :: Boolean)
  | t-var(name :: String, sort :: Sort)
  # Boolean connectives
  | t-not(t :: Term)
  | t-and(ts :: List<Term>)
  | t-or(ts :: List<Term>)
  | t-implies(a :: Term, b :: Term)
  | t-iff(a :: Term, b :: Term)
  | t-xor(a :: Term, b :: Term)
  | t-ite(c :: Term, a :: Term, b :: Term)
  # equality and order
  | t-eq(a :: Term, b :: Term)
  | t-distinct(ts :: List<Term>)
  | t-lt(a :: Term, b :: Term)
  | t-le(a :: Term, b :: Term)
  | t-gt(a :: Term, b :: Term)
  | t-ge(a :: Term, b :: Term)
  # arithmetic
  | t-add(ts :: List<Term>)
  | t-sub(a :: Term, b :: Term)
  | t-mul(ts :: List<Term>)
  | t-neg(a :: Term)
  | t-div(a :: Term, b :: Term)     # integer division (div) or real division (/)
  | t-mod(a :: Term, b :: Term)
  | t-bool-to-int(b :: Term)        # (ite b 1 0)
  # cardinality over Boolean terms (Z3's pseudo-Boolean constraints)
  | t-at-most(k :: Number, ts :: List<Term>)
  | t-at-least(k :: Number, ts :: List<Term>)
  | t-exactly(k :: Number, ts :: List<Term>)
  # escape hatch: raw SMT-LIB text, spliced in verbatim
  | t-raw(smt :: String)
sharing:
  # Operators. Pyret dispatches `+`, `-`, `*`, `/`, `<`, `<=`, `>`, `>=` to
  # these when the LEFT operand is a Term; the right operand may be a Term,
  # a Number, or a Boolean. Boolean-sorted operands of arithmetic count as
  # 0/1, so `p + q <= 1` means "at most one". The order comparisons refuse
  # Boolean operands on either side: Pyret parses `x > y > 2` as
  # `(x > y) > 2`, which would otherwise be a silently false (> (ite ..) 2).
  # `==`, `and`, `or`, and `not` cannot be overloaded: use `.eq`,
  # `.and-also`, `.or-else`, and `.negate`.
  method _plus(self, other): t-add([list: arith(self), arith-elem("the right side of +", other)]) end,
  method _minus(self, other): t-sub(arith(self), arith-elem("the right side of -", other)) end,
  method _times(self, other): t-mul([list: arith(self), arith-elem("the right side of *", other)]) end,
  method _divide(self, other): t-div(arith(self), arith-elem("the right side of /", other)) end,
  method _lessthan(self, other): t-lt(compare-elem("<", "left", self), compare-elem("<", "right", other)) end,
  method _lessequal(self, other): t-le(compare-elem("<=", "left", self), compare-elem("<=", "right", other)) end,
  method _greaterthan(self, other): t-gt(compare-elem(">", "left", self), compare-elem(">", "right", other)) end,
  method _greaterequal(self, other): t-ge(compare-elem(">=", "left", self), compare-elem(">=", "right", other)) end,
  method eq(self, other): checked(t-eq(self, lift-elem("the argument of .eq", other))) end,
  method neq(self, other): t-not(checked(t-eq(self, lift-elem("the argument of .neq", other)))) end,
  method neg(self): t-neg(arith(self)) end,
  method negate(self): t-not(bool-elem("the term before .negate", self)) end,
  method and-also(self, other):
    t-and([list: bool-elem("the left side of .and-also", self), bool-elem("the right side of .and-also", other)])
  end,
  method or-else(self, other):
    t-or([list: bool-elem("the left side of .or-else", self), bool-elem("the right side of .or-else", other)])
  end,
  method implies(self, other):
    t-implies(bool-elem("the left side of .implies", self), bool-elem("the right side of .implies", other))
  end,
  method iff(self, other):
    t-iff(bool-elem("the left side of .iff", self), bool-elem("the right side of .iff", other))
  end,
  method to-smt(self) -> String: to-smt(self) end
end

fun valid-name(name :: String) -> String block:
  quote-symbol(name)   # raises on names Z3 cannot take
  name
end

fun int-var(name :: String) -> Term: t-var(valid-name(name), int-sort) end
fun bool-var(name :: String) -> Term: t-var(valid-name(name), bool-sort) end
fun real-var(name :: String) -> Term: t-var(valid-name(name), real-sort) end

fun raw(smt :: String) -> Term:
  doc: "SMT-LIB text spliced in verbatim; its variables are not declared for you."
  t-raw(smt)
end

# ---------------------------------------------------------------------------
# Sort checking
#
# `sort-of` computes the sort of a term and raises a descriptive error on the
# first ill-sorted subterm. `none` is the sort of raw text, which is
# compatible with anything. Int and Real mix freely, as in Z3.

fun sort-name(s :: Sort) -> String:
  cases (Sort) s:
    | int-sort => "an Int"
    | bool-sort => "a Bool"
    | real-sort => "a Real"
  end
end

fun describe-sort(o :: Option<Sort>) -> String:
  cases (Option) o:
    | some(s) => sort-name(s)
    | none => "raw SMT-LIB text"
  end
end

fun sort-error(parent :: Term, child :: Term, expected :: String):
  raise("Ill-sorted term: in " + to-smt(parent) + ", " + to-smt(child)
      + " should be " + expected + " but is " + describe-sort(sort-of(child)))
end

fun check-bool(parent :: Term, x :: Term) -> Nothing:
  cases (Option) sort-of(x):
    | some(s) => if s == bool-sort: nothing else: sort-error(parent, x, "a Bool") end
    | none => nothing
  end
end

fun check-num(parent :: Term, x :: Term) -> Option<Sort>:
  cases (Option) sort-of(x):
    | some(s) => if s == bool-sort: sort-error(parent, x, "a number") else: some(s) end
    | none => none
  end
end

fun num-join(sorts :: List<Option<Sort>>) -> Option<Sort>:
  doc: "The sort of an arithmetic combination: Real if anything is, else Int."
  if L.any(lam(o): o == some(real-sort) end, sorts): some(real-sort)
  else if L.any(is-some, sorts): some(int-sort)
  else: none
  end
end

fun check-same(parent :: Term, a :: Term, b :: Term) -> Option<Sort>:
  doc: "Two terms that must have the same kind of sort (both Bool, or both numbers)."
  sa = sort-of(a)
  sb = sort-of(b)
  a-bool = sa == some(bool-sort)
  b-bool = sb == some(bool-sort)
  ask:
    | is-none(sa) then: sb
    | is-none(sb) then: sa
    | a-bool and b-bool then: some(bool-sort)
    | a-bool or b-bool then:
      raise("Ill-sorted term: in " + to-smt(parent) + ", " + to-smt(a) + " is "
          + describe-sort(sa) + " but " + to-smt(b) + " is " + describe-sort(sb))
    | otherwise: num-join([list: sa, sb])
  end
end

fun check-count(t :: Term, k :: Number) -> Nothing:
  if num-is-integer(k) and (k >= 0): nothing
  else: raise("Ill-sorted term: " + to-smt(t) + " needs a non-negative integer count, got " + num-to-string(k))
  end
end

fun sort-of(t :: Term) -> Option<Sort>:
  doc: "The sort of a well-sorted term (none for raw text); raises on an ill-sorted term."
  fun all-bool(xs :: List<Term>) -> Option<Sort> block:
    each(lam(x): check-bool(t, x) end, xs)
    some(bool-sort)
  end
  fun all-num(xs :: List<Term>) -> Option<Sort>:
    num-join(map(lam(x): check-num(t, x) end, xs))
  end
  fun compare(a :: Term, b :: Term) -> Option<Sort> block:
    check-num(t, a)
    check-num(t, b)
    some(bool-sort)
  end
  cases (Term) t:
    | t-int(_) => some(int-sort)
    | t-real(_) => some(real-sort)
    | t-bool(_) => some(bool-sort)
    | t-var(_, s) => some(s)
    | t-not(x) => all-bool([list: x])
    | t-and(xs) => all-bool(xs)
    | t-or(xs) => all-bool(xs)
    | t-implies(a, b) => all-bool([list: a, b])
    | t-iff(a, b) => all-bool([list: a, b])
    | t-xor(a, b) => all-bool([list: a, b])
    | t-ite(c, a, b) => block:
        check-bool(t, c)
        check-same(t, a, b)
      end
    | t-eq(a, b) => block:
        check-same(t, a, b)
        some(bool-sort)
      end
    | t-distinct(xs) => block:
        when not(is-empty(xs)):
          each(lam(x): check-same(t, xs.first, x) end, xs.rest)
        end
        some(bool-sort)
      end
    | t-lt(a, b) => compare(a, b)
    | t-le(a, b) => compare(a, b)
    | t-gt(a, b) => compare(a, b)
    | t-ge(a, b) => compare(a, b)
    | t-add(xs) => all-num(xs)
    | t-sub(a, b) => all-num([list: a, b])
    | t-mul(xs) => all-num(xs)
    | t-neg(a) => all-num([list: a])
    | t-div(a, b) => all-num([list: a, b])
    | t-mod(a, b) => all-num([list: a, b])
    | t-bool-to-int(b) => block:
        check-bool(t, b)
        some(int-sort)
      end
    | t-at-most(k, xs) => block:
        check-count(t, k)
        all-bool(xs)
      end
    | t-at-least(k, xs) => block:
        check-count(t, k)
        all-bool(xs)
      end
    | t-exactly(k, xs) => block:
        check-count(t, k)
        all-bool(xs)
      end
    | t-raw(_) => none
  end
end

fun checked(t :: Term) -> Term block:
  doc: "The term itself, after checking that it is well-sorted."
  sort-of(t)
  t
end

# ---------------------------------------------------------------------------
# Lifting and element checks
#
# Every constructor describes, in `where`, the position it is checking
# ("element 2 of 3 of conj", "the right side of +"), so errors say where the
# offending value came from.

fun lift(x) -> Term:
  doc: "Turn a Number or Boolean into a literal term; pass terms through."
  lift-elem("the argument of lift", x)
end

fun lift-elem(where :: String, x) -> Term:
  ask:
    | is-Term(x) then: x
    | is-number(x) then:
      if num-is-integer(x): t-int(x) else: t-real(x) end
    | is-boolean(x) then: t-bool(x)
    | otherwise: raise(where + " cannot be used as a Z3 term: " + tostring(x))
  end
end

fun bool-elem(where :: String, x) -> Term:
  doc: "A Boolean-sorted term (checked), from a term or a Boolean."
  t = lift-elem(where, x)
  cases (Option) sort-of(t):
    | some(s) =>
      if s == bool-sort: t
      else: raise(where + " should be a Boolean term, but " + to-smt(t) + " is " + sort-name(s))
      end
    | none => t
  end
end

fun arith(t :: Term) -> Term:
  doc: "A term usable in arithmetic: Boolean terms become (ite t 1 0)."
  cases (Option) sort-of(t):
    | some(s) => if s == bool-sort: t-bool-to-int(t) else: t end
    | none => t
  end
end

fun arith-elem(where :: String, x) -> Term:
  doc: "A number-sorted term (checked), from a term, a Number, or a Boolean (as 0/1)."
  arith(lift-elem(where, x))
end

fun compare-elem(op :: String, side :: String, x) -> Term:
  doc: "A number-sorted operand of an order comparison; Boolean operands are refused."
  where = "the " + side + " side of " + op
  t = lift-elem(where, x)
  cases (Option) sort-of(t):
    | some(s) =>
      if s == bool-sort:
        raise(where + " is the Boolean term " + to-smt(t)
            + "; chained comparisons such as x > y > 2 are not supported, write (x > y).and-also(y > 2)")
      else: t
      end
    | none => t
  end
end

fun position(label :: String, i :: Number, n :: Number) -> String:
  "element " + num-to-string(i) + " of " + num-to-string(n) + " of " + label
end

fun term-list(label :: String, elem :: (String, Any -> Term), xs :: List) -> List<Term>:
  doc: "Convert each element with `elem`, naming its position in errors."
  n = xs.length()
  L.map_n(lam(i, x): elem(position(label, i, n), x) end, 1, xs)
end

fun constructor-object(go :: (List -> Any)):
  doc: ```The object behind `[name: a, b, c]` notation, applying go to the
       elements; `for name.over(x from xs): body end` applies it to the
       mapped list.```
  {
    make: lam(arr): go(raw-array-to-list(arr)) end,
    make0: lam(): go(empty) end,
    make1: lam(a): go([list: a]) end,
    make2: lam(a, b): go([list: a, b]) end,
    make3: lam(a, b, c): go([list: a, b, c]) end,
    make4: lam(a, b, c, d): go([list: a, b, c, d]) end,
    make5: lam(a, b, c, d, e): go([list: a, b, c, d, e]) end,
    method over(self, f, xs :: List): go(map(f, xs)) end
  }
end

# ---------------------------------------------------------------------------
# Term constructors

fun ite(c, a, b) -> Term:
  doc: "If c then a else b; the branches must have the same kind of sort."
  checked(t-ite(bool-elem("the condition of ite", c),
      lift-elem("the then-branch of ite", a),
      lift-elem("the else-branch of ite", b)))
end


fun cardinality(label :: String, build :: (Number, List<Term> -> Term)) -> (Number -> Any):
  doc: "`[exactly(k): p, q]` and `for exactly(k).over(x from xs): body end`."
  lam(k :: Number) block:
    when not(num-is-integer(k) and (k >= 0)):
      raise(label + " needs a non-negative integer, got " + num-to-string(k))
    end
    full = label + "(" + num-to-string(k) + ")"
    constructor-object(lam(xs): build(k, term-list(full, bool-elem, xs)) end)
  end
end


# Aggregators, written for `for` syntax: `for sum-over(x from xs): body end`
# is `sum-over(lam(x): body end, xs)`.
fun pairs<A, B>(f :: (A, B -> Any), xs :: List<A>, ys :: List<B>) -> List:
  for concat-map(x from xs): map(lam(y): f(x, y) end, ys) end
end

fun sum-over<A>(f :: (A -> Any), xs :: List<A>) -> Term:
  t-add(term-list("sum-over", arith-elem, map(f, xs)))
end
fun sum-over2<A, B>(f :: (A, B -> Any), xs :: List<A>, ys :: List<B>) -> Term:
  t-add(term-list("sum-over2", arith-elem, pairs(f, xs, ys)))
end
fun all-of<A>(f :: (A -> Any), xs :: List<A>) -> Term:
  t-and(term-list("all-of", bool-elem, map(f, xs)))
end
fun all-of2<A, B>(f :: (A, B -> Any), xs :: List<A>, ys :: List<B>) -> Term:
  t-and(term-list("all-of2", bool-elem, pairs(f, xs, ys)))
end
fun any-of<A>(f :: (A -> Any), xs :: List<A>) -> Term:
  t-or(term-list("any-of", bool-elem, map(f, xs)))
end
fun any-of2<A, B>(f :: (A, B -> Any), xs :: List<A>, ys :: List<B>) -> Term:
  t-or(term-list("any-of2", bool-elem, pairs(f, xs, ys)))
end
fun each-of<A>(f :: (A -> Any), xs :: List<A>) -> Constraints:
  doc: "One constraint per element."
  constraints-from("each-of", map(f, xs))
end
fun each-of2<A, B>(f :: (A, B -> Any), xs :: List<A>, ys :: List<B>) -> Constraints:
  constraints-from("each-of2", pairs(f, xs, ys))
end

# Variable families: `seated = bool-family2("seated", students, labs)` gives a
# function `seated(s, l)` whose variables are named "seated[s,l]". Indices are
# checked against the index sets, to catch typos early.
fun index-name(v) -> String:
  if is-string(v): v else: tostring(v) end
end

fun family<A>(name :: String, srt :: Sort, xs :: List<A>) -> (A -> Term):
  lam(x) block:
    when not(xs.member(x)):
      raise(name + ": index " + tostring(x) + " is not in the family's index set")
    end
    t-var(valid-name(name + "[" + index-name(x) + "]"), srt)
  end
end

fun family2<A, B>(name :: String, srt :: Sort, xs :: List<A>, ys :: List<B>) -> (A, B -> Term):
  lam(x, y) block:
    when not(xs.member(x) and ys.member(y)):
      raise(name + ": index (" + tostring(x) + ", " + tostring(y) + ") is not in the family's index set")
    end
    t-var(valid-name(name + "[" + index-name(x) + "," + index-name(y) + "]"), srt)
  end
end

fun bool-family<A>(name :: String, xs :: List<A>) -> (A -> Term): family(name, bool-sort, xs) end
fun int-family<A>(name :: String, xs :: List<A>) -> (A -> Term): family(name, int-sort, xs) end
fun real-family<A>(name :: String, xs :: List<A>) -> (A -> Term): family(name, real-sort, xs) end
fun bool-family2<A, B>(name :: String, xs :: List<A>, ys :: List<B>) -> (A, B -> Term): family2(name, bool-sort, xs, ys) end
fun int-family2<A, B>(name :: String, xs :: List<A>, ys :: List<B>) -> (A, B -> Term): family2(name, int-sort, xs, ys) end
fun real-family2<A, B>(name :: String, xs :: List<A>, ys :: List<B>) -> (A, B -> Term): family2(name, real-sort, xs, ys) end

# ---------------------------------------------------------------------------
# Problems: constraints and soft constraints

data Constraints:
  | constraint-set(terms :: List<Term>)
sharing:
  method _plus(self, other):
    if is-Constraints(other): constraint-set(self.terms + other.terms)
    else: raise("Only constraints can be added to constraints, not " + tostring(other))
    end
  end,
  method solve(self) -> Result: solve(self) end,
  method solve-soft(self, ss :: Softs) -> Result: solve-soft(self, ss) end,
  method maximize(self, objective) -> Result: maximize(self, objective) end,
  method minimize(self, objective) -> Result: minimize(self, objective) end,
  method satisfiable(self) -> Boolean: satisfiable(self) end,
  method script(self) -> String:
    doc: "The SMT-LIB script that `solve` would send to Z3."
    problem-to-smt(self, soft-set(empty), empty)
  end,
  method length(self) -> Number: self.terms.length() end
end

fun constraint-elems(where :: String, x) -> List<Term>:
  doc: "The constraints an element of [constraints: ...] stands for."
  ask:
    | is-Constraints(x) then: x.terms
    | is-boolean(x) then:
      raise(where + " is the Pyret Boolean " + tostring(x) + ", not a Z3 constraint."
          + " A constraint mentions Z3 variables; to compare terms use .eq, not ==."
          + " For a constant constraint, write lift(" + tostring(x) + ").")
    | is-Term(x) then: [list: bool-elem(where, x)]
    | otherwise: raise(where + " is not a constraint: " + tostring(x))
  end
end

fun constraints-from(label :: String, xs :: List) -> Constraints:
  n = xs.length()
  parts = L.map_n(lam(i, x): constraint-elems(position(label, i, n), x) end, 1, xs)
  constraint-set(for L.foldr(acc from empty, p from parts): p + acc end)
end


data Soft:
  | soft-item(t :: Term, weight :: Number)
end

fun soft(t, weight :: Number) -> Soft:
  doc: "A soft constraint: violating it costs `weight` (a positive number)."
  if weight > 0: soft-item(bool-elem("the constraint of soft", t), weight)
  else: raise("The weight of a soft constraint must be positive, got " + num-to-string(weight))
  end
end

data Softs:
  | soft-set(items :: List<Soft>)
sharing:
  method _plus(self, other):
    if is-Softs(other): soft-set(self.items + other.items)
    else: raise("Only soft constraints can be added to soft constraints, not " + tostring(other))
    end
  end
end

fun soft-elems(where :: String, x) -> List<Soft>:
  ask:
    | is-Softs(x) then: x.items
    | is-Soft(x) then: [list: x]
    | otherwise: raise(where + " is not a soft constraint (use soft(term, weight)): " + tostring(x))
  end
end

fun softs-from(label :: String, xs :: List) -> Softs:
  n = xs.length()
  parts = L.map_n(lam(i, x): soft-elems(position(label, i, n), x) end, 1, xs)
  soft-set(for L.foldr(acc from empty, p from parts): p + acc end)
end


# ---------------------------------------------------------------------------
# Results

data Objective:
  | maximize-obj(t :: Term)
  | minimize-obj(t :: Term)
end

data Value:
  | v-num(n :: Number)
  | v-bool(b :: Boolean)
  | v-raw(s :: String)   # anything else, as SMT-LIB text
end

data Model:
  | model(values :: SD.StringDict<Value>)
sharing:
  method value(self, v :: Term) -> Value:
    doc: "The value of a variable in the model."
    name = var-name(v)
    if self.values.has-key(name):
      self.values.get-value(name)
    else:
      raise("The variable " + name + " does not occur in the problem that produced this model")
    end
  end,
  method num(self, v :: Term) -> Number:
    cases (Value) self.value(v):
      | v-num(n) => n
      | else => raise("Model value for " + var-name(v) + " is not a number")
    end
  end,
  method bool(self, v :: Term) -> Boolean:
    cases (Value) self.value(v):
      | v-bool(b) => b
      | else => raise("Model value for " + var-name(v) + " is not a Boolean")
    end
  end,
  method names(self) -> List<String>: self.values.keys-list() end
end

fun var-name(v :: Term) -> String:
  cases (Term) v:
    | t-var(name, _) => name
    | else => raise("Expected a variable, got the term " + to-smt(v))
  end
end

data Result:
  | sat(model :: Model)
  | unsat
  | unknown(reason :: String)
end

# ---------------------------------------------------------------------------
# Serialisation to SMT-LIB 2

fun quote-symbol(name :: String) -> String:
  doc: "Quote a name as an SMT-LIB symbol when it is not a plain identifier."
  plain-chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789~!@$%^&*_-+=<>.?/"
  chars = string-explode(name)
  starts-ok = (chars.length() > 0) and not(string-contains("0123456789", chars.first))
  all-plain = L.all(lam(c): string-contains(plain-chars, c) end, chars)
  if (name == "") or string-contains(name, "|") or string-contains(name, "\\"):
    raise("Z3 variable names must be non-empty and may not contain '|' or '\\': " + name)
  else if starts-ok and all-plain:
    name
  else:
    "|" + name + "|"
  end
end

fun number-to-smt(n :: Number) -> String:
  doc: "Render an exact Pyret number as an SMT-LIB numeral (integers and rationals)."
  ex = num-exact(n)
  if num-is-integer(ex):
    if ex < 0:
      "(- " + num-to-string(0 - ex) + ")"
    else:
      num-to-string(ex)
    end
  else:
    # num-to-string of a non-integer exact number is "p/q"
    parts = string-split(num-to-string(num-abs(ex)), "/")
    frac = "(/ " + parts.first + " " + parts.rest.first + ")"
    if ex < 0: "(- " + frac + ")" else: frac end
  end
end

fun sort-to-smt(s :: Sort) -> String:
  cases (Sort) s:
    | int-sort => "Int"
    | bool-sort => "Bool"
    | real-sort => "Real"
  end
end

fun app(op :: String, args :: List<String>) -> String:
  "(" + op + " " + L.join-str(args, " ") + ")"
end

fun to-smt(t :: Term) -> String:
  doc: "Render a term as SMT-LIB 2 text."
  fun sub(x): to-smt(x) end
  fun subs(xs): map(sub, xs) end
  fun nary(op, xs, empty-val):
    if is-empty(xs): empty-val
    else if xs.length() == 1: to-smt(xs.first)
    else: app(op, subs(xs))
    end
  end
  fun card(op, k, xs):
    "((_ " + op + " " + num-to-string(k) + ") " + L.join-str(subs(xs), " ") + ")"
  end
  cases (Term) t:
    | t-int(n) =>
      if num-is-integer(n): number-to-smt(n)
      else: raise("t-int needs an integer, got " + num-to-string(n))
      end
    | t-real(n) => number-to-smt(n)
    | t-bool(b) => if b: "true" else: "false" end
    | t-var(name, _) => quote-symbol(name)
    | t-not(x) => app("not", [list: sub(x)])
    | t-and(xs) => nary("and", xs, "true")
    | t-or(xs) => nary("or", xs, "false")
    | t-implies(a, b) => app("=>", [list: sub(a), sub(b)])
    | t-iff(a, b) => app("=", [list: sub(a), sub(b)])
    | t-xor(a, b) => app("xor", [list: sub(a), sub(b)])
    | t-ite(c, a, b) => app("ite", [list: sub(c), sub(a), sub(b)])
    | t-eq(a, b) => app("=", [list: sub(a), sub(b)])
    | t-distinct(xs) =>
      if xs.length() < 2: "true" else: app("distinct", subs(xs)) end
    | t-lt(a, b) => app("<", [list: sub(a), sub(b)])
    | t-le(a, b) => app("<=", [list: sub(a), sub(b)])
    | t-gt(a, b) => app(">", [list: sub(a), sub(b)])
    | t-ge(a, b) => app(">=", [list: sub(a), sub(b)])
    | t-add(xs) => nary("+", xs, "0")
    | t-sub(a, b) => app("-", [list: sub(a), sub(b)])
    | t-mul(xs) => nary("*", xs, "1")
    | t-neg(a) => app("-", [list: sub(a)])
    | t-div(a, b) =>
      if has-real(a) or has-real(b): app("/", [list: sub(a), sub(b)])
      else: app("div", [list: sub(a), sub(b)])
      end
    | t-mod(a, b) => app("mod", [list: sub(a), sub(b)])
    | t-bool-to-int(b) => app("ite", [list: sub(b), "1", "0"])
    | t-at-most(k, xs) =>
      if is-empty(xs): "true" else: card("at-most", k, xs) end
    | t-at-least(k, xs) =>
      if is-empty(xs): to-smt(t-bool(k <= 0)) else: card("at-least", k, xs) end
    | t-exactly(k, xs) =>
      if is-empty(xs): to-smt(t-bool(k == 0))
      else:
        ones = L.join-str(map(lam(_): "1" end, xs), " ")
        "((_ pbeq " + num-to-string(k) + " " + ones + ") " + L.join-str(subs(xs), " ") + ")"
      end
    | t-raw(s) => s
  end
end

fun has-real(t :: Term) -> Boolean:
  doc: "Does the term mention a real literal or variable? (Chooses / versus div.)"
  L.any(lam(v): v.sort == real-sort end, variables(t)) or has-real-literal(t)
end

fun has-real-literal(t :: Term) -> Boolean:
  cases (Term) t:
    | t-real(_) => true
    | else => L.any(has-real-literal, children(t))
  end
end

fun children(t :: Term) -> List<Term>:
  doc: "The immediate subterms of a term."
  cases (Term) t:
    | t-int(_) => empty
    | t-real(_) => empty
    | t-bool(_) => empty
    | t-var(_, _) => empty
    | t-not(x) => [list: x]
    | t-and(xs) => xs
    | t-or(xs) => xs
    | t-implies(a, b) => [list: a, b]
    | t-iff(a, b) => [list: a, b]
    | t-xor(a, b) => [list: a, b]
    | t-ite(c, a, b) => [list: c, a, b]
    | t-eq(a, b) => [list: a, b]
    | t-distinct(xs) => xs
    | t-lt(a, b) => [list: a, b]
    | t-le(a, b) => [list: a, b]
    | t-gt(a, b) => [list: a, b]
    | t-ge(a, b) => [list: a, b]
    | t-add(xs) => xs
    | t-sub(a, b) => [list: a, b]
    | t-mul(xs) => xs
    | t-neg(a) => [list: a]
    | t-div(a, b) => [list: a, b]
    | t-mod(a, b) => [list: a, b]
    | t-bool-to-int(b) => [list: b]
    | t-at-most(_, xs) => xs
    | t-at-least(_, xs) => xs
    | t-exactly(_, xs) => xs
    | t-raw(_) => empty
  end
end

fun variables(t :: Term) -> List<Term>:
  doc: "All variable occurrences in a term (with repeats)."
  cases (Term) t:
    | t-var(_, _) => [list: t]
    | else => concat-map(variables, children(t))
  end
end

fun concat-map<A, B>(f :: (A -> List<B>), xs :: List<A>) -> List<B>:
  for L.foldr(acc from empty, x from xs): f(x).append(acc) end
end

fun declarations(ts :: List<Term>) -> List<Term>:
  doc: ```Distinct variables across all terms, in first-occurrence order. A name
       used with two different sorts is an error.```
  all-vars = concat-map(variables, ts)
  for fold(acc from empty, v from all-vars):
    cases (Option) L.find(lam(w): w.name == v.name end, acc):
      | none => acc.append([list: v])
      | some(w) =>
        if w.sort == v.sort: acc
        else: raise("Variable " + v.name + " is used with two sorts: "
              + sort-to-smt(w.sort) + " and " + sort-to-smt(v.sort))
        end
    end
  end
end

fun declaration-to-smt(v :: Term) -> String:
  "(declare-const " + quote-symbol(v.name) + " " + sort-to-smt(v.sort) + ")"
end

# ---------------------------------------------------------------------------
# Running the solver

fun all-terms(hard :: Constraints, ss :: Softs, objectives :: List<Objective>) -> List<Term>:
  hard.terms + map(_.t, ss.items) + map(_.t, objectives)
end

fun problem-to-smt(hard :: Constraints, ss :: Softs, objectives :: List<Objective>) -> String:
  doc: "The full SMT-LIB script for a problem, ending in (check-sat)."
  decls = map(declaration-to-smt, declarations(all-terms(hard, ss, objectives)))
  asserts = map(lam(t): "(assert " + to-smt(t) + ")" end, hard.terms)
  soft-asserts = map(
    lam(s): "(assert-soft " + to-smt(s.t) + " :weight " + number-to-smt(s.weight) + ")" end,
    ss.items)
  objs = map(
    lam(o):
      cases (Objective) o:
        | maximize-obj(t) => "(maximize " + to-smt(t) + ")"
        | minimize-obj(t) => "(minimize " + to-smt(t) + ")"
      end
    end,
    objectives)
  L.join-str(decls + asserts + soft-asserts + objs + [list: "(check-sat)"], "\n")
end

fun shim-value-to-value(mv) -> Value:
  ask:
    | mv.kind == "number" then: v-num(mv.value)
    | mv.kind == "boolean" then: v-bool(mv.value)
    | otherwise: v-raw(mv.value)
  end
end

fun run-problem(hard :: Constraints, ss :: Softs, objectives :: List<Objective>) -> Result:
  doc: ```Solve a problem with hard constraints, weighted soft constraints, and
       objectives. With no soft constraints or objectives this is plain
       satisfiability.```
  script = problem-to-smt(hard, ss, objectives)
  names = map(_.name, declarations(all-terms(hard, ss, objectives)))
  out = Shim.smt-solve(script, names)
  ask:
    | out.status == "sat" then:
      dict = for fold(m from [SD.string-dict: ], mv from out.values):
        m.set(mv.name, shim-value-to-value(mv))
      end
      sat(model(dict))
    | out.status == "unsat" then: unsat
    | out.status == "unknown" then: unknown(out.output)
    | otherwise: raise("Z3 rejected the SMT-LIB script:\n" + out.output + "\nScript was:\n" + script)
  end
end

fun objective-term(what :: String, x) -> Term:
  if is-Term(x): arith(x)
  else: raise("The objective of " + what + " must be a Z3 term, got " + tostring(x))
  end
end

fun solve(cs :: Constraints) -> Result:
  doc: "Find a model satisfying all the constraints."
  run-problem(cs, soft-set(empty), empty)
end

fun solve-soft(cs :: Constraints, ss :: Softs) -> Result:
  doc: "Satisfy the constraints while minimising the total weight of violated soft constraints."
  run-problem(cs, ss, empty)
end

fun maximize(cs :: Constraints, objective) -> Result:
  doc: "Satisfy the constraints while maximising the objective (a Boolean objective counts as 0/1)."
  run-problem(cs, soft-set(empty), [list: maximize-obj(objective-term("maximize", objective))])
end

fun minimize(cs :: Constraints, objective) -> Result:
  doc: "Satisfy the constraints while minimising the objective (a Boolean objective counts as 0/1)."
  run-problem(cs, soft-set(empty), [list: minimize-obj(objective-term("minimize", objective))])
end

fun satisfiable(cs :: Constraints) -> Boolean:
  doc: "Are the constraints jointly satisfiable? Raises an error if Z3 answers unknown."
  cases (Result) solve(cs):
    | sat(_) => true
    | unsat => false
    | unknown(why) => raise("Z3 could not decide satisfiability: " + why)
  end
end

fun valid(t) -> Boolean:
  doc: "Is the Boolean term true under every assignment?"
  not(satisfiable(constraint-set([list: t-not(bool-elem("the argument of valid", t))])))
end

# ---------------------------------------------------------------------------
# Reading models by name
#
# `m.num(x)` and `m.bool(p)` on the Model take the variable; these take its
# name (see `m.names()`).

fun model-num(m :: Model, name :: String) -> Number:
  cases (Value) m.values.get-value(name):
    | v-num(n) => n
    | else => raise("Model value for " + name + " is not a number")
  end
end

fun model-bool(m :: Model, name :: String) -> Boolean:
  cases (Value) m.values.get-value(name):
    | v-bool(b) => b
    | else => raise("Model value for " + name + " is not a Boolean")
  end
end

fun z3-version() -> String:
  Shim.z3-version()
end

fun smt-eval(script :: String) -> String:
  doc: "Run raw SMT-LIB 2 text in a fresh Z3 context and return Z3's output."
  Shim.smt-eval(script)
end

# ---------------------------------------------------------------------------
# Constructor objects. Pyret resolves the functions and data above as one
# recursive group only if no value definitions sit between them, so these
# come last.

conj = constructor-object(lam(xs): t-and(term-list("conj", bool-elem, xs)) end)        # [conj: p, q, r]
disj = constructor-object(lam(xs): t-or(term-list("disj", bool-elem, xs)) end)         # [disj: p, q, r]
all-different = constructor-object(lam(xs): checked(t-distinct(term-list("all-different", lift-elem, xs))) end) # [all-different: x, y, z]
sum = constructor-object(lam(xs): t-add(term-list("sum", arith-elem, xs)) end)         # [sum: x, 1, p]
product = constructor-object(lam(xs): t-mul(term-list("product", arith-elem, xs)) end) # [product: x, 2]
exactly = cardinality("exactly", t-exactly)
at-most = cardinality("at-most", t-at-most)
at-least = cardinality("at-least", t-at-least)
constraints = constructor-object(lam(xs): constraints-from("constraints", xs) end)   # [constraints: c1, c2, ...]
softs = constructor-object(lam(xs): softs-from("softs", xs) end)   # [softs: soft(p, 1), soft(q, 5)]
