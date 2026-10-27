// z3-shim.js: a Pyret `js-file` module that runs Z3 (WebAssembly) from Pyret.
//
// Import it from Pyret with
//     import js-file("z3-shim") as Shim
// (the path is relative to the importing file, without ".js"). The typed
// Pyret API lives in z3.arr; this file is the thin, untyped-SMT-LIB layer.
//
// It needs its two sibling build outputs, z3-built.js and z3-built.wasm,
// produced by build-z3-wasm.sh (a single-threaded Z3 build, so it runs inside
// the VS Code extension's webview, which has no SharedArrayBuffer).
//
// It runs in three hosts:
//   - the `pyret` command line (Node): files are read with `fs`;
//   - the Pyret VS Code extension (a webview): files are read through the
//     extension host's `fs.readFile` RPC on `window.MESSAGES`;
//   - code.pyret.org (imported with `import gdrive-js("z3-shim.js", "<id>")`):
//     there is no filesystem, so the files are fetched from REMOTE_BASE_URL.
// The local copies win when they exist; the remote copies are the fallback
// (so a VS Code user needs only z3-shim.js and z3.arr next to their program).
// Detection uses process.versions.node and window.MESSAGES; `typeof window`
// is useless because the CLI defines a window stub.
//
// Exports (see `provides` for the types):
//   z3-version : -> String
//   smt-eval   : String -> String
//       Evaluate SMT-LIB2 text in a fresh Z3 context and return Z3's textual
//       output verbatim (including any `(error ...)` lines).
//   smt-solve  : String, List<String> -> { status, output, values }
//       Evaluate a script (which should end in `(check-sat)`), report the
//       final status ("sat", "unsat", "unknown", or "error"), and when sat,
//       fetch `(get-value ...)` for the named constants. Each value is
//       { name, kind, value } with kind "number" (a Pyret Number: integers and
//       exact rationals), "boolean", or "other" (the raw s-expression text).
({
  requires: [],
  provides: {
    shorthands: {},
    values: {
      "z3-version": ["arrow", [], "String"],
      "smt-eval": ["arrow", ["String"], "String"],
      "smt-solve": ["arrow", ["String", ["List", "String"]],
        ["record", {
          "status": "String",
          "output": "String",
          "values": ["List", ["record", { "name": "String", "kind": "String", "value": "Any" }]]
        }]]
    },
    aliases: {},
    datatypes: {}
  },
  nativeRequires: [],
  theModule: function(runtime, namespace, uri) {
    "use strict";

    // Where z3-built.js and z3-built.wasm are served from when no local copy
    // is available. raw.githubusercontent.com sends CORS headers, which
    // code.pyret.org needs. Change this when the files move.
    var REMOTE_BASE_URL = "https://raw.githubusercontent.com/shriram/pyret-z3/main/";

    var isNode = typeof process !== "undefined" && process.versions && !!process.versions.node;
    var hostRpc = (typeof window !== "undefined" && window.MESSAGES && typeof window.MESSAGES.sendRpc === "function")
      ? window.MESSAGES : null;
    // Test knobs (Node only): PYRET_Z3_BASE_URL overrides the remote location,
    // PYRET_Z3_FORCE_REMOTE=1 skips the local files to exercise the fetch path.
    if (isNode && process.env.PYRET_Z3_BASE_URL) { REMOTE_BASE_URL = process.env.PYRET_Z3_BASE_URL; }
    var forceRemote = isNode && process.env.PYRET_Z3_FORCE_REMOTE === "1";
    var canFetch = typeof fetch === "function";

    // ---- locating and reading the build outputs -------------------------

    // uri is "jsfile:///abs/dir/z3-shim.js" (CLI) or "js-file:///abs/dir/z3-shim.js"
    // (extension). Strip the scheme; keep the rest as a filesystem path.
    function shimDirectory() {
      var p = uri.replace(/^[a-zA-Z-]+:\/\//, "");
      var slash = p.lastIndexOf("/");
      return slash < 0 ? "." : p.slice(0, slash);
    }

    function readLocalBytes(path) {
      if (forceRemote) { return Promise.reject(new Error("local files disabled by PYRET_Z3_FORCE_REMOTE")); }
      if (isNode) {
        return new Promise(function(resolve) { resolve(new Uint8Array(require("fs").readFileSync(path))); });
      }
      if (hostRpc) {
        return hostRpc.sendRpc("fs", "readFile", [path]).then(toBytes);
      }
      return Promise.reject(new Error("no local filesystem in this host"));
    }

    function readLocalText(path) {
      if (forceRemote) { return Promise.reject(new Error("local files disabled by PYRET_Z3_FORCE_REMOTE")); }
      if (isNode) {
        return new Promise(function(resolve) { resolve(require("fs").readFileSync(path, "utf8")); });
      }
      if (hostRpc) {
        return hostRpc.sendRpc("fs", "readFile", [path, "utf8"]);
      }
      return Promise.reject(new Error("no local filesystem in this host"));
    }

    function fetchRemote(name, asText) {
      if (!canFetch) { return Promise.reject(new Error("fetch is not available in this host")); }
      var url = REMOTE_BASE_URL + name;
      return cachedFetch(url).then(function(response) {
        if (!response.ok) { throw new Error("HTTP " + response.status + " for " + url); }
        return asText ? response.text() : response.arrayBuffer().then(function(buf) { return new Uint8Array(buf); });
      });
    }

    // Local copy next to the shim first, then the remote copy.
    function readFile(dir, name, asText) {
      var path = dir + "/" + name;
      var local = asText ? readLocalText(path) : readLocalBytes(path);
      return local.catch(function(localError) {
        return fetchRemote(name, asText).catch(function(remoteError) {
          throw new Error("could not read " + path + " (" + localError.message + ") nor fetch "
            + REMOTE_BASE_URL + name + " (" + remoteError.message + ")");
        });
      });
    }

    // The host RPC hands back a Uint8Array when the message channel preserves
    // typed arrays, but be tolerant of an ArrayBuffer or a plain object with
    // numeric keys (the shape a JSON round trip would leave).
    function toBytes(data) {
      if (data instanceof Uint8Array) { return data; }
      if (data instanceof ArrayBuffer) { return new Uint8Array(data); }
      if (data && typeof data.length === "number") { return Uint8Array.from(data); }
      if (data && typeof data === "object") {
        var keys = Object.keys(data);
        var out = new Uint8Array(keys.length);
        for (var i = 0; i < keys.length; i++) { out[i] = data[i]; }
        return out;
      }
      throw new Error("Unexpected file contents from the host: " + typeof data);
    }

    function checkWasmMagic(bytes, path) {
      if (bytes.length < 8 || bytes[0] !== 0x00 || bytes[1] !== 0x61 || bytes[2] !== 0x73 || bytes[3] !== 0x6d) {
        throw new Error(path + " is not a WebAssembly file (" + bytes.length + " bytes received)");
      }
    }

    // ---- loading Z3 (once per page, not once per Run) --------------------

    // In the VS Code extension every Run re-evaluates this module, so a
    // module-level cache would re-download the 22 MB build each time. Keep the
    // loaded module on the global object instead, keyed by where it came
    // from; Z3 contexts are created per call, so sharing the module is safe.
    var globalCache = (function() {
      var g = (typeof globalThis !== "undefined") ? globalThis : (typeof window !== "undefined" ? window : {});
      if (!g.__pyretZ3Modules) { g.__pyretZ3Modules = {}; }
      return g.__pyretZ3Modules;
    })();
    var stderrLines = [];

    // Fetch with the browser Cache API when available, so a reload of the
    // editor does not re-download the build either. Falls back to plain fetch.
    function cachedFetch(url) {
      if (typeof caches === "undefined" || !caches || typeof caches.open !== "function") { return fetch(url); }
      return caches.open("pyret-z3").then(function(cache) {
        return cache.match(url).then(function(hit) {
          if (hit) { return hit; }
          return fetch(url).then(function(response) {
            if (response.ok) { cache.put(url, response.clone()).catch(function() { /* quota; ignore */ }); }
            return response;
          });
        });
      }, function() { return fetch(url); });
    }

    function loadZ3() {
      var dir = shimDirectory();
      var cacheKey = dir + "|" + REMOTE_BASE_URL;
      if (globalCache[cacheKey]) { return globalCache[cacheKey]; }
      var gluePath = dir + "/z3-built.js";
      var wasmPath = dir + "/z3-built.wasm";
      var z3Promise = Promise.all([readFile(dir, "z3-built.js", true), readFile(dir, "z3-built.wasm", false)]).then(function(parts) {
        var glueText = parts[0];
        var wasmBytes = parts[1];
        // The glue is an Emscripten MODULARIZE build. Evaluate it as a
        // CommonJS module with `define` hidden, because the Pyret runtime has
        // a global AMD `define` and the glue would otherwise register itself
        // anonymously with it.
        var mod = { exports: {} };
        var factory = new Function("module", "exports", "define", "require", "__dirname", "__filename",
          glueText + "\n//# sourceURL=" + gluePath);
        factory(mod, mod.exports, undefined, isNode ? require : undefined, dir, gluePath);
        var initZ3 = mod.exports;
        if (typeof initZ3 !== "function") {
          throw new Error("z3-built.js did not export an init function");
        }
        checkWasmMagic(wasmBytes, wasmPath);
        return initZ3({
          // Instantiate from the bytes we read ourselves; the glue must never
          // fetch (there is no URL for the file inside the webview). Recent
          // Emscripten builds ignore `wasmBinary`; `instantiateWasm` is the
          // supported hook.
          instantiateWasm: function(imports, onSuccess) {
            WebAssembly.instantiate(wasmBytes, imports).then(function(result) {
              onSuccess(result.instance, result.module);
            }, function(e) {
              throw new Error("WebAssembly.instantiate failed for " + wasmPath + ": " + (e && e.message ? e.message : String(e)));
            });
            return {};
          },
          print: function(s) { stderrLines.push(String(s)); },
          printErr: function(s) { stderrLines.push(String(s)); },
          locateFile: function(f) { return dir + "/" + f; }
        });
      });
      globalCache[cacheKey] = z3Promise;
      // A failed load should be retried on the next call, not cached.
      z3Promise.catch(function() { delete globalCache[cacheKey]; });
      return z3Promise;
    }

    // ---- talking to Z3 ---------------------------------------------------

    function withContext(Module, body) {
      var cfg = Module._Z3_mk_config();
      var ctx = Module._Z3_mk_context(cfg);
      Module._Z3_del_config(cfg);
      Module._z3shim_install_error_handler(ctx);
      try {
        return body(ctx);
      } finally {
        Module._Z3_del_context(ctx);
      }
    }

    function evalSmt(Module, ctx, script) {
      stderrLines = [];
      var out;
      try {
        out = Module.ccall("Z3_eval_smtlib2_string", "string", ["number", "string"], [ctx, script]);
      } catch (e) {
        throw new Error("Z3 raised an internal exception: " + describeException(Module, e)
          + (stderrLines.length > 0 ? "\n" + stderrLines.join("\n") : ""));
      }
      // Z3 reports SMT-LIB problems in two ways at once: an (error "...") line
      // in the output and an error code on the context. Keep everything in
      // the text so callers see one consistent channel; only exceptions that
      // escape Z3 itself become JS errors.
      var code = Module._Z3_get_error_code(ctx);
      if (code !== 0 && !/^\(error /m.test(out)) {
        var msg = Module.ccall("Z3_get_error_msg", "string", ["number", "number"], [ctx, code]);
        out = out + (out.endsWith("\n") || out === "" ? "" : "\n") + "(error " + JSON.stringify(msg) + ")\n";
      }
      return out;
    }

    function describeException(Module, e) {
      if (e && typeof e === "object" && typeof e.message === "string" && e.message !== "") {
        return e.message;
      }
      if (typeof Module.getExceptionMessage === "function") {
        try { return String(Module.getExceptionMessage(e)); } catch (ignored) { /* fall through */ }
      }
      return String(e);
    }

    // ---- a small s-expression reader for Z3's output ---------------------

    // Produces nested arrays of atoms. Atoms are {atom: text} with the raw
    // token text; |quoted symbols| and "strings" keep their delimiters.
    function readSExprs(text) {
      var i = 0;
      var n = text.length;
      function skipWs() {
        while (i < n) {
          var c = text[i];
          if (c === ";") { while (i < n && text[i] !== "\n") { i++; } }
          else if (c === " " || c === "\n" || c === "\t" || c === "\r") { i++; }
          else { break; }
        }
      }
      function readOne() {
        skipWs();
        if (i >= n) { return undefined; }
        var c = text[i];
        if (c === "(") {
          i++;
          var items = [];
          for (;;) {
            skipWs();
            if (i >= n) { throw new Error("Unbalanced parentheses in Z3 output: " + text); }
            if (text[i] === ")") { i++; return items; }
            items.push(readOne());
          }
        }
        if (c === ")") { throw new Error("Unexpected ')' in Z3 output: " + text); }
        var start = i;
        if (c === "|") {
          i++;
          while (i < n && text[i] !== "|") { i++; }
          i++;
          return { atom: text.slice(start, i) };
        }
        if (c === "\"") {
          i++;
          for (;;) {
            if (i >= n) { break; }
            if (text[i] === "\"") {
              if (text[i + 1] === "\"") { i += 2; continue; }
              i++;
              break;
            }
            i++;
          }
          return { atom: text.slice(start, i) };
        }
        while (i < n && " \n\t\r()".indexOf(text[i]) < 0) { i++; }
        return { atom: text.slice(start, i) };
      }
      var forms = [];
      for (;;) {
        var f = readOne();
        if (f === undefined) { break; }
        forms.push(f);
      }
      return forms;
    }

    function sexprToString(s) {
      if (Array.isArray(s)) { return "(" + s.map(sexprToString).join(" ") + ")"; }
      return s.atom;
    }

    function isAtom(s, a) { return !Array.isArray(s) && s.atom === a; }

    function unquoteSymbol(atom) {
      if (atom.length >= 2 && atom[0] === "|" && atom[atom.length - 1] === "|") {
        return atom.slice(1, -1);
      }
      return atom;
    }

    function quoteSymbol(name) {
      if (/^[A-Za-z~!@$%^&*_\-+=<>.?\/][A-Za-z0-9~!@$%^&*_\-+=<>.?\/]*$/.test(name)) { return name; }
      if (name.indexOf("|") >= 0 || name.indexOf("\\") >= 0) {
        throw new Error("Z3 symbol names may not contain '|' or '\\': " + JSON.stringify(name));
      }
      return "|" + name + "|";
    }

    // Numeric literal text in Z3 model output: "3", "1.5", "(- 3)", "(/ 1 2)",
    // "(- (/ 1.0 2.0))". Parsed exactly with BigInt rationals; returns
    // {num, den} or null if not numeric.
    function rationalValue(s) {
      if (!Array.isArray(s)) {
        var m = /^([0-9]+)(?:\.([0-9]+))?$/.exec(s.atom);
        if (m === null) { return null; }
        var frac = m[2] === undefined ? "" : m[2];
        return { num: BigInt(m[1] + frac), den: BigInt("1" + "0".repeat(frac.length)) };
      }
      if (s.length === 2 && isAtom(s[0], "-")) {
        var inner = rationalValue(s[1]);
        return inner === null ? null : { num: -inner.num, den: inner.den };
      }
      if (s.length === 3 && isAtom(s[0], "/")) {
        var a = rationalValue(s[1]);
        var b = rationalValue(s[2]);
        if (a === null || b === null || b.num === 0n) { return null; }
        var num = a.num * b.den;
        var den = a.den * b.num;
        if (den < 0n) { num = -num; den = -den; }
        return { num: num, den: den };
      }
      return null;
    }

    function numericValue(s) {
      var r = rationalValue(s);
      if (r === null) { return null; }
      if (r.den === 1n) { return runtime.makeNumberFromString(r.num.toString()); }
      return runtime.makeNumberFromString(r.num.toString() + "/" + r.den.toString());
    }

    function modelValue(s) {
      if (isAtom(s, "true")) { return { kind: "boolean", value: true }; }
      if (isAtom(s, "false")) { return { kind: "boolean", value: false }; }
      var num = numericValue(s);
      if (num !== null) { return { kind: "number", value: num }; }
      return { kind: "other", value: sexprToString(s) };
    }

    // The status is the last bare sat/unsat/unknown line of the output; an
    // (error ...) form anywhere makes the status "error".
    function statusOf(output) {
      if (/^\(error /m.test(output)) { return "error"; }
      var status = "unknown";
      var seen = false;
      output.split("\n").forEach(function(ln) {
        var t = ln.trim();
        if (t === "sat" || t === "unsat" || t === "unknown") { status = t; seen = true; }
      });
      return seen ? status : "error";
    }

    // ---- Pyret-facing functions ------------------------------------------

    function pyretError(e) {
      if (runtime.isPyretException && runtime.isPyretException(e)) { return e; }
      return runtime.ffi.makeMessageException(e && e.message ? e.message : String(e));
    }

    // Run `body(Module)` once Z3 is loaded, pausing the Pyret stack meanwhile.
    function withZ3(body) {
      return runtime.pauseStack(function(restarter) {
        loadZ3().then(function(Module) {
          var result;
          try {
            result = body(Module);
          } catch (e) {
            restarter.error(pyretError(e));
            return;
          }
          restarter.resume(result);
        }, function(e) {
          restarter.error(runtime.ffi.makeMessageException("Could not load Z3 (z3-built.js / z3-built.wasm next to z3-shim.js): " + (e && e.message ? e.message : String(e))));
        });
      });
    }

    function z3Version() {
      runtime.ffi.checkArity(0, arguments, "z3-version", false);
      return withZ3(function(Module) {
        var ptrs = Module._malloc(16);
        try {
          Module._Z3_get_version(ptrs, ptrs + 4, ptrs + 8, ptrs + 12);
          var parts = [0, 4, 8, 12].map(function(off) { return Module.getValue(ptrs + off, "i32"); });
          return parts.join(".");
        } finally {
          Module._free(ptrs);
        }
      });
    }

    function smtEval(script) {
      runtime.ffi.checkArity(1, arguments, "smt-eval", false);
      runtime.checkString(script);
      return withZ3(function(Module) {
        return withContext(Module, function(ctx) {
          return evalSmt(Module, ctx, script);
        });
      });
    }

    function smtSolve(script, names) {
      runtime.ffi.checkArity(2, arguments, "smt-solve", false);
      runtime.checkString(script);
      runtime.checkList(names);
      var nameArr = runtime.ffi.toArray(names);
      nameArr.forEach(function(nm) { runtime.checkString(nm); });
      return withZ3(function(Module) {
        return withContext(Module, function(ctx) {
          var output = evalSmt(Module, ctx, script);
          var status = statusOf(output);
          var values = [];
          if (status === "sat" && nameArr.length > 0) {
            var query = "(get-value (" + nameArr.map(quoteSymbol).join(" ") + "))";
            var valueOutput = evalSmt(Module, ctx, query);
            if (/^\(error /m.test(valueOutput)) {
              throw new Error("Z3 could not report model values: " + valueOutput.trim());
            }
            var forms = readSExprs(valueOutput);
            if (forms.length !== 1 || !Array.isArray(forms[0])) {
              throw new Error("Unexpected get-value output from Z3: " + valueOutput);
            }
            forms[0].forEach(function(pair) {
              if (!Array.isArray(pair) || pair.length !== 2 || Array.isArray(pair[0])) {
                throw new Error("Unexpected get-value entry from Z3: " + sexprToString(pair));
              }
              var mv = modelValue(pair[1]);
              values.push(runtime.makeObject({
                name: unquoteSymbol(pair[0].atom),
                kind: mv.kind,
                value: mv.value
              }));
            });
          }
          return runtime.makeObject({
            status: status,
            output: output,
            values: runtime.ffi.makeList(values)
          });
        });
      });
    }

    return runtime.makeModuleReturn({
      "z3-version": runtime.makeFunction(z3Version, "z3-version"),
      "smt-eval": runtime.makeFunction(smtEval, "smt-eval"),
      "smt-solve": runtime.makeFunction(smtSolve, "smt-solve")
    }, {});
  }
})
