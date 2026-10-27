use context starter2024

# A program that uses Z3. Keep z3-shim.js in the same folder as this file,
# and be online when you run: the library and the solver come from GitHub.

import url("https://raw.githubusercontent.com/shriram/pyret-z3/main/z3.arr") as Z

x = Z.int-var("x")
y = Z.int-var("y")
p = Z.bool-var("p")
q = Z.bool-var("q")

check "two integers":
  r = Z.solve([Z.constraints: (x + y).eq(10), x > 7, y > 0])
  r satisfies Z.is-sat
  (r.model.num(x) + r.model.num(y)) is 10
end

check "at most one of p and q; prefer p":
  r = [Z.constraints: [Z.at-most(1): p, q]].maximize(p)
  r.model.bool(p) is true
  r.model.bool(q) is false
end

check "no solution":
  Z.solve([Z.constraints: x > 5, x < 5]) is Z.unsat
end

check "mistakes are caught before Z3 sees them":
  [Z.constraints: x == 5] raises "use .eq, not =="
  [Z.constraints: x + 5] raises "should be a Boolean term"
end
