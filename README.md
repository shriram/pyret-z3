# Z3 from Pyret

Use the [Z3](https://github.com/Z3Prover/z3) solver from a Pyret program, in
the Pyret extension for VS Code or on the `pyret` command line. There is
nothing to install: the library and the solver are downloaded when you run.

## Getting Started

You need one file: [`starter/z3-shim.js`](starter/z3-shim.js). Download it
into the folder of your program and never edit it. It is a small stub that
the library loads from your folder; the stub in turn fetches the real shim,
and the solver, from this repository. On the command line the first run
stores them in `~/.cache/pyret-z3` and later runs read them from there;
delete that folder to force a fresh download.

If this is your first time, also download
[`starter/example.arr`](starter/example.arr) into the same folder and run it:
open it in VS Code and click Run, or run `pyret example.arr` from that
folder. It exercises the whole setup, so a passing run confirms that
everything works. The first run downloads the solver (22 MB); later runs
reuse it.

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

## Documentation

[`docs.md`](docs.md) is the reference: every function, method, and type the
library provides, with examples, and a section of
[pitfalls](docs.md#pitfalls) that anyone (or anything) writing code against
the library should read first.

## Files

| | |
|---|---|
| `starter/` | The stub to download, and an example program to confirm the setup. |
| `z3.arr` | The library your program imports. |
| `docs.md` | The reference documentation. |
| `z3-shim.js` | Connects Pyret to the solver. |
| `z3-built.js`, `z3-built.wasm` | Z3 4.16.0, compiled to WebAssembly. |
| `src/` | Tests, build script, and notes for developers: see [`src/DEVELOPMENT.md`](src/DEVELOPMENT.md). |

## Offline

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
