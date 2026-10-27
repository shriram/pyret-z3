use context starter2024

include file("reqs-common.arr")
provide *

### DO NOT EDIT ANYTHING ABOVE THIS LINE ###

# Proof of concept: checking (a small subset of) the ScB requirements with Z3.
#
# THIS IS NOT THE FULL SET OF REQUIREMENTS. It encodes only:
#   - the intro sequence: CSCI 0150, 0170, or 0111 followed by CSCI 0200; or
#     CSCI 0190 followed by CSCI 0200 or any other CSCI course numbered 0200
#     or above that is not used for another requirement;
#   - the math foundation: CSCI 0220 or MATH 1530;
#   - the three foundation areas: CSCI 0500; CSCI 0410; CSCI 0300 or 0330;
#   - five technical electives: CSCI courses numbered 1000 or above.
# The four additional electives, the calculus prerequisite, the rules about
# non-technical courses, the capstone, and everything in the handbook are
# left out.
#
# Encoding. The requirements are "slots". For every course in the roster and
# every slot it is eligible for, a Boolean says "this course fills this
# slot". A course fills at most one slot; a slot takes at most one course;
# the second intro slot takes a course other than CSCI 0200 only if CSCI 0190
# fills the first. Z3 maximises the number of filled slots:
#   completed       every slot can be filled;
#   all-necessary   otherwise, if an assignment that fills that many slots can
#                   also use every concentration course in the roster;
#   has-unnecessary otherwise.
# Courses that are eligible for no slot are not concentration courses and are
# ignored. Malformed names are caught before any of this.

import file("../../z3.arr") as Z
import lists as L

# ---------------------------------------------------------------------------
# Course names

data Course:
  | course(dept :: String, num :: Number)
end

fun is-upper-letter(c :: String) -> Boolean:
  string-contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c)
end

fun is-digit(c :: String) -> Boolean:
  string-contains("0123456789", c)
end

fun parse-course(s :: String) -> Option<Course>:
  doc: ```Four uppercase letters (or three and a space), a space, four digits,
       then an optional suffix of a dash and/or uppercase letters, which is
       ignored.```
  chars = string-explode(s)
  if chars.length() < 9:
    none
  else:
    dept = string-substring(s, 0, 4)
    dept-chars = string-explode(dept)
    dept-ok =
      L.all(is-upper-letter, dept-chars)
      or (L.all(is-upper-letter, dept-chars.take(3)) and (dept-chars.get(3) == " "))
    digits = string-substring(s, 5, 9)
    digits-ok = L.all(is-digit, string-explode(digits))
    suffix = string-substring(s, 9, string-length(s))
    suffix-chars = string-explode(suffix)
    suffix-ok = L.all(lam(c): is-upper-letter(c) or (c == "-") end, suffix-chars)
    if dept-ok and (string-char-at(s, 4) == " ") and digits-ok and suffix-ok:
      cases (Option) string-to-number(digits):
        | some(n) => some(course(string-substring(dept, 0, 3) + (if dept-chars.get(3) == " ": "" else: string-char-at(dept, 3) end), n))
        | none => none
      end
    else:
      none
    end
  end
end

fun canonical(c :: Course) -> String:
  doc: "The variable-friendly name of a course (suffixes already dropped)."
  c.dept + " " + num-to-string(c.num)
end

# ---------------------------------------------------------------------------
# The requirement slots and eligibility

data Slot:
  | slot(name :: String, eligible :: (Course -> Boolean))
end

fun is-csci(c :: Course) -> Boolean: c.dept == "CSCI" end
fun csci-num(c :: Course, n :: Number) -> Boolean: is-csci(c) and (c.num == n) end
fun csci-in(c :: Course, nums :: List<Number>) -> Boolean: is-csci(c) and nums.member(c.num) end

intro-1 = slot("intro-1", csci-in(_, [list: 150, 170, 111, 190]))
intro-2 = slot("intro-2", lam(c): is-csci(c) and (c.num >= 200) end)
tech-slots = for map(i from range(1, 6)):
  slot("tech-" + num-to-string(i), lam(c): is-csci(c) and (c.num >= 1000) end)
end

slots = [list:
    intro-1,
    intro-2,
    slot("math", lam(c): csci-num(c, 220) or ((c.dept == "MATH") and (c.num == 1530)) end),
    slot("algorithms", csci-num(_, 500)),
    slot("ai", csci-num(_, 410)),
    slot("systems", csci-in(_, [list: 300, 330]))
  ] + tech-slots

fun fills(c :: Course, s :: Slot) -> Z.Term:
  Z.bool-var(canonical(c) + " fills " + s.name)
end

fun eligible-slots(c :: Course) -> List<Slot>:
  for filter(s from slots): s.eligible(c) end
end

fun is-concentration-course(c :: Course) -> Boolean:
  not(is-empty(eligible-slots(c)))
end

# ---------------------------------------------------------------------------
# Constraints

fun slot-filled(roster :: List<Course>, s :: Slot) -> Z.Term:
  for Z.any-of(c from filter(s.eligible, roster)): fills(c, s) end
end

fun filled-count(roster :: List<Course>) -> Z.Term:
  # a Boolean term counts as 0/1 in a sum
  for Z.sum-over(s from slots): slot-filled(roster, s) end
end

fun structural-constraints(roster :: List<Course>) -> Z.Constraints:
  each-course-once = for Z.each-of(c from roster):
    for Z.at-most(1).over(s from eligible-slots(c)): fills(c, s) end
  end
  each-slot-once = for Z.each-of(s from slots):
    for Z.at-most(1).over(c from filter(s.eligible, roster)): fills(c, s) end
  end
  # Series C: a course other than CSCI 0200 completes the intro sequence only
  # after CSCI 0190.
  zero-one-ninety-first = for Z.any-of(c from filter(csci-num(_, 190), roster)): fills(c, intro-1) end
  series-c = for Z.each-of(c from filter(lam(c): intro-2.eligible(c) and not(csci-num(c, 200)) end, roster)):
    fills(c, intro-2).implies(zero-one-ninety-first)
  end
  each-course-once + each-slot-once + series-c
end

fun max-filled(roster :: List<Course>) -> Number:
  doc: "The largest number of slots the roster can fill at once."
  cases (Z.Result) structural-constraints(roster).maximize(filled-count(roster)):
    | sat(model) =>
      for fold(n from 0, s from slots):
        if L.any(lam(c): model.bool(fills(c, s)) end, filter(s.eligible, roster)):
          n + 1
        else:
          n
        end
      end
    | unsat => raise("internal error: the structural constraints are always satisfiable")
    | unknown(why) => raise("Z3 could not decide: " + why)
  end
end

fun all-usable(roster :: List<Course>, best :: Number) -> Boolean:
  doc: "Can every course fill some slot while still filling `best` slots?"
  every-course-used = for Z.each-of(c from roster):
    for Z.any-of(s from eligible-slots(c)): fills(c, s) end
  end
  (structural-constraints(roster)
      + every-course-used
      + [Z.constraints: filled-count(roster).eq(best)]).satisfiable()
end

fun check-reqs(roster :: List<String>) -> Completion:
  parsed = map(parse-course, roster)
  if L.any(is-none, parsed):
    malformed
  else:
    courses = L.distinct(map(_.value, parsed))
    relevant = filter(is-concentration-course, courses)
    best = max-filled(relevant)
    ask:
      | best == slots.length() then: completed
      | all-usable(relevant, best) then: all-necessary
      | otherwise: has-unnecessary
    end
  end
end
