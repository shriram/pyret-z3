# Development Notes

How the pieces fit, why they are the way they are, and how to test and
upgrade them. The student-facing instructions are in the top-level README.

## Layout

```
z3.arr                 the Pyret library (students import it by URL)
z3-shim.js             the js-file module: loads the WebAssembly build, exposes
                       z3-version, smt-eval, smt-solve
z3-built.js, .wasm     Z3 4.16.0 compiled with Emscripten, single-threaded
starter/               what students copy: a one-line z3-shim.js stub and an
                       example program
src/build-z3-wasm.sh   reproduces the build from the Z3 source tree
src/z3-shim-native.c   a tiny C helper linked into the build
src/z3-tests.arr       tests of the library and the shim
src/labassign-poc/     the lab-assignment problem as a Z3 optimisation
src/reqs-poc/          a small subset of the ScB requirements checker (not the
                       full rules)
src/tools/             runs a Pyret file inside the VS Code extension, headless
```

## How It Works

**The extension.** The Pyret VS Code extension (`pyret-parley`) is a web
extension: it runs a code.pyret.org build inside a webview. Neither the
webview nor the extension host can start a process, so the installed `z3`
binary is out of reach and Z3 has to run in the page as WebAssembly. The
extension supports `import js-file("name")`, which reads `name.js` through an
RPC to the extension host (`fs.readFile`, `path.resolve`).

**The js-file module.** `z3-shim.js` is a JavaScript object literal
`({ requires, provides, nativeRequires, theModule })`. `provides.values`
carries the exports' types, so Pyret sees them typed. `theModule(runtime,
namespace, uri)` receives the module's own URI; the shim uses it to look for
`z3-built.js` and `z3-built.wasm` beside itself, via Node `fs` on the command
line or the host RPC in the webview. When they are absent it fetches them
from `REMOTE_BASE_URL` (the constant at the top of the file), caching the
download with the browser Cache API so a second run makes no network request.
Asynchronous work uses `runtime.pauseStack`. The module is evaluated with
`new Function` with `define` hidden, because the Pyret page has a global AMD
`define`, and the WebAssembly is instantiated through the `instantiateWasm`
hook, since Emscripten 6 glue ignores `wasmBinary`.

**The shim's surface.** Three functions, all over SMT-LIB 2 text, each in a
fresh Z3 context: `z3-version`, `smt-eval(script)` returns Z3's output
verbatim, and `smt-solve(script, names)` returns the status and the values of
the named constants (Pyret Numbers, including exact rationals and big
integers, Booleans, or raw text). Z3 reports errors both as text and as an
error code; the shim folds everything into the text, and a script whose output
has no `sat`/`unsat`/`unknown` line gets status `error`.

**Why a custom WebAssembly build.** The official `z3-solver` npm package is a
pthreads build and needs `SharedArrayBuffer`, which a VS Code webview gets
only when the whole editor runs with `--enable-coi`. Students cannot be asked
to do that. Z3 links fine single-threaded; `build-z3-wasm.sh` configures it
with `Z3_SINGLE_THREADED` and `Z3_POLLING_TIMER` (without the latter the first
`unsat` answer tries to start a timer thread and throws), links with `em++`
(a C-only link drops the C++ runtime), and exports only the SMT-LIB entry
points. Solving blocks the page while it runs, which is fine for course-sized
problems. There are no wall-clock timeouts; `(set-option :rlimit N)` through
`Z.raw` or `Z.smt-eval` gives a deterministic bound.

## The Pyret Library

`z3.arr` is a term AST (`t-*` constructors, private) with a serializer to
SMT-LIB, a sort checker, and a public surface in which every value a program
can build goes through a checking constructor:

- Operators on terms (`_plus` and friends), with numbers and Booleans lifted
  and Boolean terms counted as 0/1 in arithmetic. Pyret dispatches on the left
  operand, so the term must be on the left; `==`, `and`, `or`, `not` cannot
  be overloaded.
- Constructor notation: `[conj: ...]`, `[sum: ...]`, `[all-different: ...]`,
  `[exactly(k): ...]`. A constructor head may be a call, and the constructor
  object also has `over(f, xs)`, so `for exactly(k).over(x from xs)` works
  because a method accessed as a field is a function.
- `Constraints` is a nominal type; `[constraints: ...]` checks that every
  element is a Boolean term, splices nested constraints, and rejects raw
  Pyret Booleans with a hint about `.eq`, since `x == 3` is structural
  equality on terms and silently yields `false`.
- Errors name the position: "element 2 of 3 of conj should be a Boolean
  term, but x is an Int". The sort checker (`sort-of`) walks the whole term,
  so a deep term built by folding operators costs quadratic time; the
  aggregators build flat terms.
- The `provide:` block exports only the public names; `Z.raw`, `Z.to-smt`,
  `cs.script()`, and `Z.smt-eval` are the escape hatches.
- No tests live in the library (the editor compiles everything it imports).
  `z3-tests.arr` reaches the serializer and sort checker through the public
  constructors.

Pyret facts learned the hard way: a value binding ends the mutually recursive
group of `fun` and `data` definitions, so the constructor objects are bound
at the end of the file; `distinct` and `sort` are builtin names; `cases`
takes `| else =>`, not `otherwise`; sharing-block methods are separated by
commas; `data Result: | sat(...)` already defines `is-sat`; a stale
`.pyret/` cache after a `--no-check-mode` run breaks later runs until
deleted.

## Deployment

Students write `import url(".../main/z3.arr") as Z` and keep the one-line
`starter/z3-shim.js` beside their program. This is the best available
without changing the Pyret editor:

- The editor's import protocols are `file`, `js-file`, `url`, `url-file`, and
  the Google Drive ones. Only `js-file` and `gdrive-js` load JavaScript;
  `js-file` reads through the host filesystem RPC, and `gdrive-js` needs the
  Google sign-in the extension lacks. So JavaScript cannot be imported from a
  URL directly.
- A module imported by `url` resolves its own `js-file` imports relative to
  the importing program's folder, which is why `z3.arr`'s
  `import js-file("z3-shim")` finds the student's stub.
- The editor evaluates a `js-file` module's text synchronously and uses
  whatever object the expression yields, so the stub fetches the real shim
  with a synchronous `XMLHttpRequest` and `eval`s it. The shim is fetched at
  compile time and at run time, within GitHub's five-minute cache; `z3.arr`
  is fetched on every run (the `url` locator has no cache). Students must be
  online. raw.githubusercontent.com sends `Access-Control-Allow-Origin: *`.
- The `pyret-parley.compiler` setting defaults to `pyret`; its `ts`
  alternative has no `js-file` locator, so the shim cannot load under it.
- A proper fix is a `js-url` import protocol in `cpo-main.js` (about twenty
  lines modelled on the `gdrive-js` locator: fetch the text, then
  `builtin-raw-locator-from-str` and `make-js-locator-from-raw`), plus the
  same in `ts-compiler-lib.js`. That needs a pyret-lang pull request and an
  extension release.
- code.pyret.org cannot import the shim today: its `gdrive-js` locator
  downloads with a `drive.file`-scoped token that cannot see files uploaded
  through the Drive website, and Google blocks CPO's full-scope login. A
  one-line CPO change (`getSharedFileById` instead of `getFileById` in
  `makeGDriveJSLocator`) would fix that. The shim itself runs inside the CPO
  page.

## Testing

On the command line, from each file's own directory:

```bash
cd src && pyret -q z3-tests.arr
```

```bash
cd src/labassign-poc && pyret -q labassign.arr
```

```bash
cd src/reqs-poc && pyret -q tests.arr
```

Inside the VS Code extension (VS Code for the Web in headless Chromium, which
like the desktop extension has no cross-origin isolation): in `src/tools`,
`npm install`, then `npm run serve` in one terminal and
`npm run check -- src/z3-tests.arr` (or `starter/example.arr`, or any file
under the repo root) in another. The driver opens the file in the Pyret
editor webview, clicks Run, and prints the check summary. The extension path
in `package.json` names the installed extension version.

The likely regressions are negative numbers and rationals in model output,
the Boolean-to-0/1 lifting in objectives, and the element-position messages.

## Upgrading Z3

```bash
git clone --depth 1 --branch z3-<version> https://github.com/Z3Prover/z3 z3-src
src/build-z3-wasm.sh z3-src .
```

needs Emscripten. It replaces `z3-built.js` and `z3-built.wasm` at the
root. Then run the test suites, update the version in the README, and push. Students pick up the new build on their
next run: the browser cache is keyed by URL, and the shim's text comes with
GitHub's five-minute cache header.
