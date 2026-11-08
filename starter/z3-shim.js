// Do not edit. This loads z3-shim.js from https://github.com/shriram/pyret-z3 .
//
// In the Pyret VS Code extension it fetches the real shim on every Run (the
// shim then fetches the solver, which the editor caches). On the `pyret`
// command line (Node) it stores the shim and the solver in ~/.cache/pyret-z3
// the first time, and loads them from there afterwards; delete that folder
// to re-download.
(function () {
  var BASE = "https://raw.githubusercontent.com/shriram/pyret-z3/main/";
  var isNode = typeof process !== "undefined" && process.versions && !!process.versions.node;
  if (!isNode) {
    var r = new XMLHttpRequest();
    r.open("GET", BASE + "z3-shim.js", false);
    r.send();
    if (r.status !== 200) { throw new Error("Could not download z3-shim.js from GitHub (HTTP " + r.status + "). Are you online?"); }
    return eval(r.responseText);
  }
  // `require` is not in scope while Pyret compiles a url-imported module, so
  // reach the built-in modules through process when it is missing.
  var req = (typeof require === "function") ? require
    : (typeof process.getBuiltinModule === "function") ? process.getBuiltinModule
    : process.mainModule.require;
  var fs = req("fs"), path = req("path"), os = req("os"), cp = req("child_process");
  var dir = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "pyret-z3");
  var files = ["z3-shim.js", "z3-built.js", "z3-built.wasm"];
  var missing = files.filter(function (f) { return !fs.existsSync(path.join(dir, f)); });
  if (missing.length > 0) {
    fs.mkdirSync(dir, { recursive: true });
    process.stderr.write("pyret-z3: downloading " + missing.join(", ") + " into " + dir + " (once)\n");
    // A child Node process does the download, because this function must
    // return synchronously. Each file lands under a temporary name and is
    // renamed when complete, so an interrupted download is not mistaken for
    // a finished one next time.
    var script = "var fs=require('fs');var dir=process.argv[1];var base=process.argv[2];"
      + "(async function(){for(var f of process.argv.slice(3)){var r=await fetch(base+f);"
      + "if(!r.ok){throw new Error('HTTP '+r.status+' for '+base+f);}"
      + "fs.writeFileSync(dir+'/'+f+'.part',Buffer.from(await r.arrayBuffer()));"
      + "fs.renameSync(dir+'/'+f+'.part',dir+'/'+f);}})()"
      + ".catch(function(e){console.error('pyret-z3: '+e.message+'. Are you online?');process.exit(1);});";
    // Pyret runs inside a long-lived server process, so process.execPath can
    // name a Node that has since been upgraded away; prefer the one on PATH.
    var args = ["-e", script, dir, BASE].concat(missing);
    var errors = [];
    var ok = ["node", process.execPath].some(function (node) {
      try { cp.execFileSync(node, args, { stdio: ["ignore", "pipe", "pipe"] }); return true; }
      catch (e) { errors.push(node + ": " + ((e.stderr && String(e.stderr).trim()) || e.message)); return false; }
    });
    if (!ok) { throw new Error("pyret-z3: could not download the solver into " + dir + "\n" + errors.join("\n")); }
  }
  // The shim looks for the solver next to its own file, which it learns from
  // the uri Pyret passes; point it at the cache instead of this stub.
  var shim = eval(fs.readFileSync(path.join(dir, "z3-shim.js"), "utf8"));
  var theModule = shim.theModule;
  shim.theModule = function (runtime, namespace, uri) {
    return theModule(runtime, namespace, "jsfile://" + dir + "/z3-shim.js");
  };
  return shim;
})()
