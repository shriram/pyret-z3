# Z3 from Pyret

Use the [Z3](https://github.com/Z3Prover/z3) solver from a Pyret program in
the Pyret extension for VS Code. There is nothing to install: the library and
the solver are downloaded when you run.

## Getting Started

1. Download the two files in [`starter/`](starter/) into the folder of your
   program: `z3-shim.js` (never edit it) and `example.arr` (a program to
   start from).
2. Open `example.arr` in VS Code and click Run. The first run downloads the
   solver (22 MB); later runs reuse it.

To use Z3 in a program of your own, keep it in a folder that has `z3-shim.js`
and start it the way `example.arr` does:

```pyret
import url("https://raw.githubusercontent.com/shriram/pyret-z3/main/z3.arr") as Z
```

You must be online when you run.

## A Small Example

```pyret
x = Z.int-var("x")
y = Z.int-var("y")

cases (Z.Result) Z.solve([Z.constraints: x > 2, (x + y).eq(10)]):
  | sat(m) => m.num(x)          # 3, say; m.num(y) is then 7
  | unsat => raise("no solution")
  | unknown(why) => raise(why)
end
```

## Features

### Variables

```pyret
x = Z.int-var("x")
p = Z.bool-var("p")
r = Z.real-var("r")
```

Often you want one variable for each element of a list, or for each pair
drawn from two lists: a Boolean "student s sits in lab l" for every student
and every lab, say. Rather than inventing names like `"seated-17-2"` by hand,
ask for a whole indexed set at once:

```pyret
seated = Z.bool-family2("seated", students, labs)
```

Now `seated(s, l)` is the variable for student `s` and lab `l`, and asking
for a student or lab that is not in the lists is an error. One-index and
two-index forms exist for `int-`, `bool-`, and `real-` variables:
`Z.int-family("cost", items)` gives `cost(i)`.

For three or more indices, use the one-index form with a list of tuples as
the index set:

```pyret
slots = ...                                   # a list of {student; lab; time}
seated = Z.bool-family("seated", slots)       # seated({s; l; t}) is a variable
occupied = for Z.sum-over({s; l; t} from slots): seated({s; l; t}) end
```

`occupied` is the term that counts the occupied slots.

### Terms

The arithmetic and comparison operators build terms when their left operand
is a term. The right operand may be a term, a number, or a Boolean.

```pyret
x + y        x - 1        x * 3        x / 2
x < y        x <= 10      x > 0        x >= y
```

Pyret's `==`, `and`, `or`, and `not` cannot be reused; these methods take
their place:

| Instead of | Write |
|---|---|
| `x == y` | `x.eq(y)` |
| `not (x == y)` | `x.neq(y)` |
| `p and q` | `p.and-also(q)` |
| `p or q` | `p.or-else(q)` |
| `not p` | `p.negate()` |
| if p then q | `p.implies(q)` |
| p exactly when q | `p.iff(q)` |

In arithmetic a Boolean term counts as 0 or 1, so `p + q <= 1` says "at most
one of p and q".

Constructors build a term from several:

```pyret
[Z.conj: p, q, r]                 # all of them
[Z.disj: p, q, r]                 # at least one
[Z.sum: x, y, 1]
[Z.product: x, 2]
[Z.all-different: x, y, z]
[Z.exactly(1): p, q, r]           # also at-most(k), at-least(k)
Z.ite(p, x, y)                    # if p then x else y
```

And from a list, with `for`; each of these is a term:

```pyret
total-cost = for Z.sum-over(s from students): cost(s) end
all-adults = for Z.all-of(s from students): age(s) >= 18 end
lab-1-used = for Z.any-of(s from students): seated(s, 1) end
one-lab-for-s = for Z.exactly(1).over(l from labs): seated(s, l) end
```

`Z.sum-over2(s from students, l from labs)` and friends range over two lists.

### Constraints

A problem is a collection of Boolean terms:

```pyret
cs = [Z.constraints: x > 2, (x + y).eq(10), [Z.at-most(1): p, q]]
```

`+` joins two collections, and `for Z.each-of(s from students): ... end`
is the collection with one constraint per student.

### Solving

```pyret
Z.solve(cs)                 # a model, or unsat
Z.maximize(cs, x + y)       # a model with the objective as large as possible
Z.minimize(cs, x + y)
Z.satisfiable(cs)           # true or false
Z.valid(p.or-else(p.negate()))
Z.solve-soft(cs, [Z.softs: Z.soft(p, 1), Z.soft(q, 5)])   # weighted preferences
```

Each of these but `valid` is also a method: `cs.minimize(x + y)`. The result
is `sat(m)`, `unsat`, or `unknown(why)`, and a model answers `m.num(x)` and
`m.bool(p)`.

### Limits

Only Booleans, integers, and reals are covered. Z3's other theories (bit
vectors, arrays, strings, quantifiers) are reachable only through
`Z.raw("...")`, which splices in SMT-LIB text.

## Pitfalls

In this section `x` and `y` are bound to Z3 variables made with `Z.int-var`,
as in the example above.

**Operators look overloaded, but only on the left.** Pyret decides what `*`
means by looking at its left operand. `x * 3` builds a term; `3 * x` asks a
number to multiply itself by a term, and Pyret reports an error in `*`.
Keep the variable on the left, or write `[Z.product: 3, x]`.

**A Pyret Boolean is not a constraint.** Unlike `+` or `<`, the operators
`==`, `and`, `or`, and `not` cannot be given a new meaning for terms. So
`x == 3` does what `==` always does in Pyret: it compares the two values
and, since a variable is not the number 3, evaluates to `false`. That is a
Pyret Boolean, not a Z3 constraint, and the library refuses it:

```pyret
[Z.constraints: x == 3]
# element 1 of 1 of constraints is the Pyret Boolean false, not a Z3 constraint.
# ... to compare terms use .eq, not ==.
```

Write `x.eq(3)` instead. Likewise `(x > 2) and (y > 2)` fails, because `and`
needs Pyret Booleans and gets terms; write `(x > 2).and-also(y > 2)`, or list
the two as separate constraints. The methods are `.eq`, `.neq`, `.and-also`,
`.or-else`, `.implies`, `.iff`, and `.negate`.

**No chained comparisons.** `x > y > 2` means `(x > y) > 2` to Pyret. The
library rejects a comparison whose operand is a Boolean term; write
`(x > y).and-also(y > 2)`.

## Files

| | |
|---|---|
| `starter/` | The two files to download. |
| `z3.arr` | The library your program imports. |
| `z3-shim.js` | Connects Pyret to the solver. |
| `z3-built.js`, `z3-built.wasm` | Z3 4.16.0, compiled to WebAssembly. |
| `src/` | Tests, examples, build script, and notes for developers: see [`src/DEVELOPMENT.md`](src/DEVELOPMENT.md). |

## Without VS Code, or Offline

Copy `z3.arr`, `z3-shim.js`, `z3-built.js`, and `z3-built.wasm` next to your
program and write `import file("z3.arr") as Z`. This works in the `pyret`
command-line tool (run `pyret -q yourfile.arr` from the file's folder) and in
VS Code, and needs no network.

## Credits

[Z3](https://github.com/Z3Prover/z3) is by Microsoft Research and is
distributed under the [MIT license](https://github.com/Z3Prover/z3/blob/master/LICENSE.txt),
which permits redistributing it in compiled form. `z3-built.js` and
`z3-built.wasm` are Z3 4.16.0, built from the unmodified source with
[Emscripten](https://emscripten.org/) by the script in `src/`; a copy of
Z3's license is in [`LICENSE-Z3.txt`](LICENSE-Z3.txt). Z3 is not affiliated
with this repository.

Everything else here is under the [MIT license](LICENSE).
