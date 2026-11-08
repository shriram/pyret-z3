// source-files.js: a Pyret `js-file` module for the tests, which lets
// z3-tests.arr read files of this repository (Pyret itself has no file
// access). Paths are relative to this file's folder.
//
//     import js-file("source-files") as Src
//     Src.read-text("../docs.md")
//
// Command line only: it uses Node's fs.
({
  requires: [],
  provides: {
    shorthands: {},
    values: { "read-text": ["arrow", ["String"], "String"] },
    aliases: {},
    datatypes: {}
  },
  nativeRequires: [],
  theModule: function(runtime, namespace, uri) {
    "use strict";
    // uri is "jsfile:///abs/dir/source-files.js"
    var dir = uri.replace(/^[a-zA-Z-]+:\/\//, "").replace(/\/[^\/]*$/, "");
    var req = (typeof require === "function") ? require : process.getBuiltinModule;

    function readText(path) {
      runtime.ffi.checkArity(1, arguments, "read-text", false);
      runtime.checkString(path);
      return runtime.makeString(req("fs").readFileSync(dir + "/" + path, "utf8"));
    }

    return runtime.makeModuleReturn({
      "read-text": runtime.makeFunction(readText, "read-text")
    }, {});
  }
})
