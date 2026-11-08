use context starter2024

# Checks that docs.md documents the whole public surface of z3.arr: every
# name in its provide block, and every method on its data types, must appear
# in docs.md in backquotes (the Index at the end of docs.md lists them all).
# Run from this directory:  pyret -q docs-tests.arr
# Command line only: source-files.js reads the files through Node.

import js-file("source-files") as Src
import lists as L

fun strip-comment(ln :: String) -> String:
  if string-contains(ln, "#"): string-substring(ln, 0, string-index-of(ln, "#")) else: ln end
end

fun words(s :: String) -> List<String>:
  for filter(w from string-split-all(s, " ")): not(w == "") end
end

fun provided-names(src :: String) -> List<String>:
  doc: "The names in the provide block, without the `type` and `data` keywords."
  after = string-substring(src, string-index-of(src, "provide:") + 8, string-length(src))
  body = string-substring(after, 0, string-index-of(after, "\nend"))
  names = for L.foldr(acc from empty, ln from string-split-all(body, "\n")):
    words(string-replace(strip-comment(ln), ",", " ")).append(acc)
  end
  for filter(n from names): not((n == "type") or (n == "data")) end
end

fun method-names(src :: String) -> List<String>:
  doc: "Names declared with `method name(`, except the operator hooks such as _plus."
  after-each = string-split-all(src, "method ").rest
  names = for L.foldr(acc from empty, s from after-each):
    paren = string-index-of(s, "(")
    if paren > 0:
      n = string-substring(s, 0, paren)
      if string-contains(n, " ") or (string-char-at(n, 0) == "_"): acc else: link(n, acc) end
    else:
      acc
    end
  end
  L.distinct(names)
end

check "docs.md documents every provided name and every method":
  docs = Src.read-text("../docs.md")
  src = Src.read-text("../z3.arr")
  provided = provided-names(src)
  methods = method-names(src)
  # sanity: the parsers found roughly what the library has
  provided.length() is%(_ > _) 40
  methods.length() is%(_ > _) 15
  fun undocumented(prefix :: String, names :: List<String>) -> List<String>:
    for filter(n from names): not(string-contains(docs, "`" + prefix + n + "`")) end
  end
  undocumented("", provided) is empty
  # methods are written with a leading dot in the docs' Index
  undocumented(".", methods) is empty
end
