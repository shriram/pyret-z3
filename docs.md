# pyret-z3 Reference

This is the complete documentation of the library: every function, method,
and type that `z3.arr` provides. The [README](README.md) covers setup.

## Loading

Load the library using

```pyret
import url("https://raw.githubusercontent.com/shriram/pyret-z3/main/z3.arr") as Z
```

so that the library's names are reached as `Z.int-var`, `Z.solve`, and so
on. The examples below write them that way. You may of course use any other
prefix as well, such as `Z3`. (You can also use `include` if you
prefer, but that may cause name clashes, so consider using `import` instead.)


Contents: [Overview](#overview) ·
[Terms](#terms) · [Constraints](#constraints) ·
[Solving](#solving) · [Soft Constraints](#soft-constraints) ·
[Escape Hatches](#escape-hatches) · [Pitfalls](#pitfalls) ·
[Index](#index)

## Overview

A program builds *terms*, gathers *constraints*, and
asks Z3 to *solve* them. The answer is a *result*: `sat` with a *model*
that gives each variable a value, `unsat`, or `unknown`.

```pyret
x = Z.int-var("x")
y = Z.int-var("y")

cases (Z.Result) Z.solve([Z.constraints: x > 2, (x + y).eq(10)]):
  | sat(m) => m.num(x)          # 3, say; m.num(y) is then 7
  | unsat => raise("no solution")
  | unknown(why) => raise(why)
end
```

In Z3, every term has a *sort* (analogous to a type): in Z3 they are called
`Int`, `Bool`, or `Real`, and we will use these names in what follows to
refer to the Z3 sorts. We say a term is *numeric* when its sort is `Int` or
`Real`; the words “Number” and “Boolean” are reserved for Pyret values. (The
type `Z.Sort` reflects these in Pyret as
the values `Z.int-sort`, `Z.bool-sort`, and `Z.real-sort`.) The library checks
sorts as terms are built, trying to catch errors in Pyret itself before they go
to Z3.

Numbers are exact: integers and rationals go to Z3 exactly and come back
exactly. A Z3 Real is an exact number, not a floating-point approximation.
It is modeled in Pyret as a rational (e.g., `-1/2`)
unless Z3 produces something that is not one (an algebraic number, say);
see [`Value`](#values). The library turns a RoughNum (float) in Pyret into an
exact rational for Z3.

## Terms

### Variables

Z3 has a notion of variables, which are quantities to solve for. There are three
kinds of variables, corresponding to the sorts. Z3 cannot see the names of Pyret
variables (and indeed, a term may not be bound to a Pyret variable anyway).
Instead, each Z3 variable is given a name for use within Z3:

```pyret
x = Z.int-var("x")
p = Z.bool-var("p")
r = Z.real-var("r")
```

A variable is identified by
its name: two calls `Z.int-var("x")` denote the same variable.
A name may be any non-empty string except
one containing `|` or `\`; the library quotes it for Z3 if needed, so
`"CSCI 0190"` is fine. Using one name with two sorts in the same problem is
an error.

#### Variable Families

Sometimes we want a family of related Z3 variables, not just one at a time:
e.g., to represent a set of entities.
A *variable family* makes a whole indexed set at once and returns a function
from indices to variables:

```pyret
cost = Z.int-family("cost", items)                  # cost(i)
seated = Z.bool-family2("seated", students, labs)   # seated(s, l)
```

There are six of these constructors: one for each sort, for one index and
for two. Their names are
`int-family`, `bool-family`, `real-family` (one index) and
`int-family2`, `bool-family2`, `real-family2` (two indices). The indices
may be any values; they are compared with `==`, and asking for an index that
is not in the list is an error, which catches typos and off-by-ones early.
The variable `seated(17, 2)` is the same as `Z.bool-var("seated[17,2]")`:
the family builds the Z3 name from the family's name and the printed
indices. That is the name you see in `m.names()` and in SMT-LIB output.

For three or more indices, use a one-index family over a list of tuples (or
of values of your own datatype):

```pyret
slots = ...                                   # a list of {student; lab; time}
busy = Z.bool-family("busy", slots)           # busy({s; l; t}) is a variable
```

### Literals

Z3 only recognizes Z3 terms, not Pyret values. Therefore, all Pyret values have
to be *lifted* into the Z3 types. The `lift` operator does this explicitly:

```pyret
Z.lift(3)        # the Int literal 3
Z.lift(1/2)      # the Real literal 1/2
Z.lift(true)     # the Bool literal true
```

However, the library automatically lifts Pyret Numbers and Booleans whenever
they appear

- inside a term constructor ([Constructors](#constructors); notably
  not inside `constraints`, whose elements must be terms),
- on the *right* of a binary operator, or
- as the argument of a method.

For instance, the following examples do not require explicit lifting:

```pyret
x + 1                      # the 1 is lifted
x.eq(3)                    # so is the 3
p.and-also(true)           # and the true
[Z.sum: x, y, 1]           # and the 1 here
[Z.conj: p, true]          # and this true
Z.ite(p, 1, 2)             # and both branches
```

Thus, you only need to write `lift` explicitly when you need a term and have a
plain Pyret value, such as on the *left* of a binary operator:

```pyret
Z.lift(3) * x
```

In contrast, the un-lifted `3 * x` produces an error (see
[Pitfalls](#pitfalls)). Note that sometimes just re-ordering terms, e.g.,
by writing `3 * x` as `x * 3`, will let the library do the lifting.

### Arithmetic

```pyret
x + y      x - 1      x * 3      x / 2      x.neg()      x.modulo(3)
```

The operators build terms when their *left* operand is a term; the right
operand may be a term, a number, or a Boolean. `.neg()` is unary minus and
`.modulo(k)` the remainder.

The meaning of division is that given by Z3. When both operands are of sort
Int, it performs integer division (`div`, rounding so that the remainder
is non-negative), and exact real division when
either is Real. `.modulo` is defined only on Ints, and is the remainder that
matches `div`. Ints
and Reals can mix freely in arithmetic; the result is Real if
anything in it is.

A Bool term in an arithmetic expression is treated as 0 (false) or 1 (true),
so `p + q <= 1` says “at
most one of p and q”, and `for Z.sum-over(s from students): seated(s, 1) end`
counts the students in lab 1.

### Comparisons

```pyret
x < y      x <= 10      x > 0      x >= y
x.eq(y)    x.neq(0)     p.eq(q)    p.eq(true)
```

The four order comparisons need numeric operands on both sides. For complicated
reasons (see [Pitfalls](#pitfalls)), these cannot be chained: `x > y > 2`
must instead be written as `(x > y).and-also(y > 2)`.

Pyret's `==` cannot be given a new meaning, so it does not build a term;
`x == y` only compares the two Pyret values and yields a Pyret Boolean.
Therefore, it cannot be used to build a constraint; use `.eq` instead.
Both `.eq` and `.neq` work on any two terms of the same
kind of sort: two numeric terms, or two Bools.

### Boolean Connectives

Likewise `and`, `or`, and `not` cannot be given new meanings. Use these methods
instead:

| Meaning | Write |
|---|---|
| p and q | `p.and-also(q)` |
| p or q | `p.or-else(q)` |
| not p | `p.negate()` |
| if p then q | `p.implies(q)` |
| p exactly when q | `p.iff(q)` |
| exactly one of p and q | `p.xor(q)` |

The term on the left must be a Bool term; the argument may be a Bool term
or a Pyret Boolean.

### Constructors

These build one term from several. Each is written with Pyret's
`[name: ...]` syntax, and each element may be a term or a plain value:

```pyret
[Z.conj: p, q, r]                 # all of them (“conjunction”)
[Z.disj: p, q, r]                 # at least one (“disjunction”)
[Z.sum: x, y, 1]
[Z.product: x, 2]
[Z.all-different: x, y, z]        # pairwise distinct
[Z.exactly(1): p, q, r]           # exactly one of them is true
[Z.at-most(2): p, q, r]           # at most two
[Z.at-least(1): p, q, r]          # at least one
Z.ite(p, x, y)                    # if p then x else y (“if-then-else”)
```

The elements of `conj` and `disj` must be Bool, and so must those of the
three cardinality constructors, which also take a non-negative integer
count. The elements of `sum` and `product` must be numeric (a Bool
element counts as 0 or 1, as in all arithmetic). The elements of
`all-different` may be of any sort, but all of the same kind: all numeric,
or all Bool.
`ite` is an ordinary function: its condition is Bool, and its two branches
have the same kind of sort; the result has that sort.

Empty constructors have their mathematical meaning: `[Z.conj: ]` is true,
`[Z.disj: ]` false, `[Z.sum: ]` 0, `[Z.product: ]` 1, `[Z.all-different: ]`
true, `[Z.at-most(k): ]` true, `[Z.at-least(k): ]` true only when k is 0,
and `[Z.exactly(k): ]` likewise.

### Building Terms from Lists

Every constructor above also has a `.over` form for use with Pyret's
`for`: `for Z.conj.over(s from students): body end` builds the conjunction
of the body's value for each student. The cardinality constructors are
used the same way, after supplying the count:

```pyret
one-lab-for-s = for Z.exactly(1).over(l from labs): seated(s, l) end
```

Three aggregators are written the same way and are the usual spelling of
sums and quantifiers over a list; each is a single term:

```pyret
total-cost = for Z.sum-over(s from students): cost(s) end
all-adults = for Z.all-of(s from students): age(s) >= 18 end
lab-1-used = for Z.any-of(s from students): seated(s, 1) end
```

`Z.sum-over2`, `Z.all-of2`, and `Z.any-of2` range over the pairs from two
lists: `for Z.sum-over2(s from students, l from labs): body end`.

`Z.each-of` and `Z.each-of2` look the same but produce a
[`Constraints`](#constraints) value, one constraint per element (or pair),
rather than a single term. As constraints, `all-of`
and `each-of` mean the same thing: asserting a conjunction asserts every
conjunct. The difference is what you get back. `all-of` makes one Bool term
that you can negate, use as the premise of `.implies`, or nest inside
`any-of`; `each-of` makes separate constraints to hand to the solver, and is
simply the direct spelling of “one constraint per element”. `any-of` has no
such twin, because a disjunction cannot be split into separate constraints.

### Inspecting Terms

For a term `t`, `t.to-smt()` (also `Z.to-smt(t)`) renders it as SMT-LIB 2 text, which
is useful when an error message or a solver answer is surprising.
`Z.is-Term(v)` tells whether a Pyret value is a term. `Z.Term` is the type
of terms, for annotations:

```pyret
fun in-lab(s :: Number, l :: Number) -> Z.Term: seated(s, l) end
```

## Constraints

A Z3 task is a `Z.Constraints` value: a collection of Bool terms, all of
which must hold.

```pyret
cs = [Z.constraints: x > 2, (x + y).eq(10), [Z.at-most(1): p, q]]
```

Each element of `[Z.constraints: ...]` is a Bool term or another
`Constraints` value (whose constraints are spliced in).

`cs1 + cs2` is the collection with both sets of constraints, so a problem
can be assembled from named parts:

```pyret
rules = one-value-per-cell + each-value-once-per-row + each-value-once-per-column
```

`for Z.each-of(s from students): body end` is the collection with one
constraint per student, and `Z.each-of2` the same over the pairs from two
lists:

```pyret
one-lab-each = for Z.each-of(s from students):
  for Z.exactly(1).over(l from labs): seated(s, l) end
end
```

The body of `each-of` usually produces one Bool term, giving one constraint
per element. It may instead produce a `Constraints` value, giving several
per element; these are spliced into one flat collection, so `each-of` nests
freely (an inner `each-of`, or a `[Z.constraints: ...]` with several rules,
inside an outer `each-of`).

A `Constraints` value has two methods that are sometimes useful when debugging:
`.length()` (the number of
constraints) and `.script()` (the SMT-LIB script that `solve` would send
to Z3, declarations included).

## Solving

```pyret
Z.solve(cs)                 # a model satisfying cs, or unsat
Z.maximize(cs, x + y)       # a model making the objective as large as possible
Z.minimize(cs, x + y)       # a model making the objective as small as possible
Z.solve-soft(cs, scs)       # see Soft Constraints
Z.satisfiable(cs)           # true or false
Z.valid(t)                  # is the Bool term true under every assignment?
```

The names of the functions
other than `valid` are also available as methods on the constraints:
`cs.solve()`, `cs.minimize(x + y)`, etc. The objective of `maximize` and
`minimize` is a numeric term, or a Bool term, which counts as 0 or 1.
`satisfiable` and `valid` raise an error if Z3 answers `unknown`.

### Results

`solve`, `solve-soft`, `maximize`, and `minimize` return a `Z.Result`:

```pyret
data Result:
  | sat(model :: Model)
  | unsat
  | unknown(reason :: String)
end
```

`unknown` is Z3 giving up (a timeout, or a problem outside what it can
decide), with its explanation. The usual way to consume a result is
`cases`, as in the [Overview](#overview); the data definition also gives
you `Z.is-sat`, `Z.is-unsat`, `Z.is-unknown`, the field `r.model` on a
`sat` result, and `Z.unsat` as a value to compare with:

```pyret
r = Z.solve(cs)
r satisfies Z.is-sat
r.model.num(x) is 3
Z.solve([Z.constraints: x > 5, x < 5]) is Z.unsat
```

### Models

When Z3 finds a solution, it creates a model.
A `Z.Model` maps the problem's variables to values.

```pyret
m.num(x)       # the Number assigned to the Int or Real variable x
m.bool(p)      # the Boolean assigned to p
m.value(x)     # the Value assigned to x (see below)
m.names()      # the names of all variables in the model, as a List<String>
```

The first three take a Z3 variable ([Variables](#variables)), not a Pyret
variable or the variable's name string.
Asking for a variable
that does not occur in the problem, or `num` of a Bool variable (or vice versa),
is an error.

`Z.model-num(m, "x")` and `Z.model-bool(m, "p")` take the Z3 variable name
(the string), for situations where you have only the name, as from `m.names()`.

### Values

```pyret
data Value:
  | v-num(n :: Number)
  | v-bool(b :: Boolean)
  | v-raw(s :: String)
end
```

`m.value(x)` returns one of these. `v-raw` holds Z3's own text for a value
the library cannot turn into a Pyret number, such as an algebraic real
(`(root-obj (+ (^ x 2) (- 2)) 2)` for the square root of 2); `m.num` raises
an error on such a value, so use `m.value` when that can happen.

## Soft Constraints

A soft constraint is one the solver should satisfy if it can, at a cost
when it cannot:

```pyret
scs = [Z.softs: Z.soft(p, 1), Z.soft(q, 5)]
Z.solve-soft(cs, scs)        # or cs.solve-soft(scs)
```

`Z.soft(t, w)` pairs a Bool term with a positive weight. `solve-soft`
finds a model of the hard constraints `cs` that minimises the total weight
of the soft constraints it violates. `[Z.softs: ...]` collects `Soft`
values (and other `Softs` collections) into a `Z.Softs` value; `scs1 + scs2`
joins two.

Soft constraints and `maximize`/`minimize` are two ways to express
preference. A sum of weighted Bool terms as an objective says the same thing
as soft constraints with those weights; soft constraints read better when
the preferences are many and separately named.

## Escape Hatches

The library covers Z3's `Bool`, `Int`, and `Real` sorts. Everything else
(bit vectors, arrays, strings, quantifiers, solver options) is reachable
only as SMT-LIB text.

`Z.raw("...")` is a term whose text is spliced into the script verbatim. It
has no sort of its own and is accepted wherever a term is, so it can be
combined with ordinary terms. Variables that appear only in raw text are
not declared for you; declare them in raw text too, or mention them in an
ordinary term. Since the library cannot check raw text, a mistake in it
surfaces only when you solve, as an error carrying Z3's complaint and the
full script.

`Z.smt-eval("...")` runs an SMT-LIB script in a fresh Z3 context and
returns Z3's output as a string. Declarations do not carry over between
calls, but Z3's global options do: a `(set-option ...)` in one call, or in
`raw` text, stays in force for the rest of the program's run, including
ordinary `solve` calls.
`cs.script()` shows the script the library would send for `cs`, which is
a good starting point for such text. `Z.z3-version()` is the solver's
version string.

## Pitfalls

In this section `x` and `y` are Int variables and `p` a Bool variable.

**Operators look overloaded, but only on the left.** Pyret decides what `*`
means by looking at its left operand. `x * 3` builds a term; in contrast,
`3 * x` is numeric multiplication, and reports a *Pyret* error.
Keep the variable on the left, write `Z.lift(3) * x`, or use
`[Z.product: 3, x]`.

**A Pyret Boolean is not a constraint.** Unlike `+` or `<`, the operators
`==`, `and`, `or`, and `not` cannot be given a new meaning for terms. So
`x == 3` is a Pyret comparison: it compares the two values
and, since a variable is not the number 3, evaluates to `false`. That is a
Pyret Boolean, not a Z3 constraint. Since it is natural to (accidentally)
write this as a constraint, the library checks for and refuses it, with a
message that suggests using `.eq`: write `x.eq(3)`
instead. Likewise `(x > 2) and (y > 2)` fails, because `and`
needs Pyret Booleans and gets terms; write `(x > 2).and-also(y > 2)`, or list
the two as separate constraints.

**No chained comparisons.** `x > y > 2` means `(x > y) > 2` to Pyret, so
the outer `>` gets a Bool term on its left, and Z3's order comparisons
are defined on numeric terms only. A chained comparison means a conjunction;
write `(x > y).and-also(y > 2)`, or two separate constraints.

The library rejects this rather than leaving it to Z3 for a
reason: elsewhere a Bool term in arithmetic counts as 0 or 1, and if that
rule applied here, `(x > y) > 2` would be well-sorted, meaning “(0 or 1) > 2”,
which is simply false. The solver would then report `unsat`, with nothing to
suggest that the constraint was not the one you meant. So order comparisons
are the one place a Bool operand is refused, with a message that names
chained comparisons.

**`if` does not build a term.** `if p: x else: y end` needs a Pyret Boolean
condition and `p` is a term. Write `Z.ite(p, x, y)`. Be aware this is a Pyret
*function* call, so both branches are evaluated.

**Division rounds.** With Int operands `/` is integer division. For a
fraction, make one operand Real: `Z.real-var`, or a literal like `1/2`.

**Only the variables in the problem are in the model.** `m.num(z)` is an
error if no constraint mentions `z`, even if you created `z`.

**A variable is its name.** `Z.int-var("x")` twice is one variable, and
`Z.int-var("x")` with `Z.bool-var("x")` in one problem is an error.

## Index

Every name the library provides, with a link to where it is described. All
of them are reached through the import prefix, `Z.int-var` and so on
(assuming you imported the library `as Z`), except those beginning with
`.`, which are methods: they are listed with the type they belong to and
are called on a value of that type (`x.eq(y)`, `cs.solve()`, `m.num(x)`).
`.over` is called on a constructor (`Z.conj.over`).

| Name | What it is | Section |
|---|---|---|
| `all-different` | `[all-different: ...]`, pairwise distinct | [Constructors](#constructors) |
| `all-of`, `all-of2` | conjunction over a list, or over pairs | [Building Terms from Lists](#building-terms-from-lists) |
| `any-of`, `any-of2` | disjunction over a list, or over pairs | [Building Terms from Lists](#building-terms-from-lists) |
| `at-least`, `at-most`, `exactly` | `[at-least(k): ...]`, cardinality | [Constructors](#constructors) |
| `bool-family`, `bool-family2` | indexed Bool variables | [Variable Families](#variable-families) |
| `bool-var` | a Bool variable | [Variables](#variables) |
| `conj`, `disj` | `[conj: ...]`, and / or of several | [Constructors](#constructors) |
| `constraints` | `[constraints: ...]`, a problem | [Constraints](#constraints) |
| `Constraints` | the type of a problem; methods `.solve`, `.solve-soft`, `.maximize`, `.minimize`, `.satisfiable`, `.script`, `.length`, and the operator `+` | [Constraints](#constraints), [Solving](#solving) |
| `each-of`, `each-of2` | one constraint per element, or per pair | [Constraints](#constraints) |
| `int-family`, `int-family2` | indexed Int variables | [Variable Families](#variable-families) |
| `int-var` | an Int variable | [Variables](#variables) |
| `is-Term` | is this Pyret value a term? | [Inspecting Terms](#inspecting-terms) |
| `ite` | if-then-else term | [Constructors](#constructors) |
| `lift` | a Number or Boolean as a literal term | [Literals](#literals) |
| `maximize`, `minimize` | solve with an objective | [Solving](#solving) |
| `Model` | a solution; methods `.num`, `.bool`, `.value`, `.names` | [Models](#models) |
| `model-bool`, `model-num` | read a model by variable name | [Models](#models) |
| `.over` | the `for` form of every constructor: `for Z.conj.over(x from xs): ... end` | [Building Terms from Lists](#building-terms-from-lists) |
| `product`, `sum` | `[sum: ...]`, arithmetic of several | [Constructors](#constructors) |
| `raw` | SMT-LIB text as a term | [Escape Hatches](#escape-hatches) |
| `real-family`, `real-family2` | indexed Real variables | [Variable Families](#variable-families) |
| `real-var` | a Real variable | [Variables](#variables) |
| `Result` | `sat(model)`, `unsat`, `unknown(reason)` | [Results](#results) |
| `satisfiable` | true or false | [Solving](#solving) |
| `smt-eval` | run an SMT-LIB script | [Escape Hatches](#escape-hatches) |
| `soft`, `softs`, `Soft`, `Softs` | weighted preferences | [Soft Constraints](#soft-constraints) |
| `solve`, `solve-soft` | find a model | [Solving](#solving) |
| `Sort` | `int-sort`, `bool-sort`, `real-sort` | [Overview](#overview) |
| `sum-over`, `sum-over2` | sum over a list, or over pairs | [Building Terms from Lists](#building-terms-from-lists) |
| `Term` | the type of terms; operators `+ - * / < <= > >=`, methods `.eq`, `.neq`, `.neg`, `.modulo`, `.negate`, `.and-also`, `.or-else`, `.implies`, `.iff`, `.xor`, `.to-smt` | [Terms](#terms) |
| `to-smt` | a term as SMT-LIB text | [Inspecting Terms](#inspecting-terms) |
| `valid` | true under every assignment? | [Solving](#solving) |
| `Value` | `v-num`, `v-bool`, `v-raw` | [Values](#values) |
| `z3-version` | the solver's version | [Escape Hatches](#escape-hatches) |
