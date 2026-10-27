use context starter2024

# LabAssign with Z3: assign students to one of three labs of equal capacity,
# respecting availability and preferring higher-ranked choices.
#
# Encoding. `seated(s, l)` is a Boolean variable, "student s is in lab l".
# Hard constraints: each lab holds at most `capacity` students; each student
# is in exactly one lab they are available for. Objective: minimise the total
# "unhappiness", where a first choice costs 0, a second 1, and a third 2.
# Z3's optimizer finds an assignment of minimum total cost; the model is read
# back into an AssignmentTable.
#
# The output type is unchanged: AssignmentTable rows are
#   student-id :: Number, lab-assigned :: Number
# If no assignment exists (the assumptions on the input do not guarantee
# one, since availability can rule out every lab), `assign` raises an error.

provide *
provide-types *

import file("../../z3.arr") as Z
import lists as L

data Preference:
  | first
  | second
  | third
  | unavailable
end

labs = [list: 1, 2, 3]

fun pref-column(lab :: Number) -> String:
  "lab-" + num-to-string(lab) + "-pref"
end

fun cost(p :: Preference) -> Number:
  doc: "How unhappy a student is with a lab (unavailable labs are ruled out separately)."
  cases (Preference) p:
    | first => 0
    | second => 1
    | third => 2
    | unavailable => 0
  end
end

fun available-labs(r :: Row) -> List<Number>:
  for filter(lab from labs): not(r[pref-column(lab)] == unavailable) end
end

fun assign(capacity :: Number, prefs :: Table) -> Table:
  doc: "Assign every student to an available lab, minimising total unhappiness."
  rows = prefs.all-rows()
  seated = Z.bool-family2("seated", map(_["student-id"], rows), labs)
  fun in-lab(r :: Row, lab :: Number) -> Z.Term: seated(r["student-id"], lab) end

  hard =
    (for Z.each-of(lab from labs):
        for Z.at-most(capacity).over(r from rows): in-lab(r, lab) end
      end)
    + (for Z.each-of(r from rows):
        for Z.exactly(1).over(lab from available-labs(r)): in-lab(r, lab) end
      end)

  unhappiness = for Z.sum-over2(r from rows, lab from labs):
    in-lab(r, lab) * cost(r[pref-column(lab)])
  end

  cases (Z.Result) hard.minimize(unhappiness):
    | sat(m) =>
      fun lab-of(r :: Row) -> Number:
        cases (Option) L.find(lam(lab): m.bool(in-lab(r, lab)) end, labs):
          | some(lab) => lab
          | none => raise("Z3 model assigns no lab to student " + num-to-string(r["student-id"]))
        end
      end
      prefs.build-column("lab-assigned", lab-of).select-columns([list: "student-id", "lab-assigned"])
    | unsat =>
      raise("No assignment exists: some student has no available lab, or the labs are too small")
    | unknown(why) => raise("Z3 could not decide: " + why)
  end
end

# ---------------------------------------------------------------------------
# Tests

fun lab-count(assignments :: Table, lab :: Number) -> Number:
  assignments.filter(lam(r): r["lab-assigned"] == lab end).length()
end

fun lab-for(assignments :: Table, student-id :: Number) -> Number:
  assignments.filter(lam(r): r["student-id"] == student-id end).row-n(0)["lab-assigned"]
end

fun respects(capacity :: Number, prefs :: Table, assignments :: Table) -> Boolean:
  doc: "Every student appears once, in an available lab, and no lab is over capacity."
  same-students = map(_["student-id"], prefs.all-rows()) == map(_["student-id"], assignments.all-rows())
  all-available = for L.all(r from prefs.all-rows()):
    not(r[pref-column(lab-for(assignments, r["student-id"]))] == unavailable)
  end
  within-capacity = for L.all(lab from labs): lab-count(assignments, lab) <= capacity end
  same-students and all-available and within-capacity
end

check "everyone gets a first choice when the labs are big enough":
  prefs = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref
    row: 1, first, second, third
    row: 2, second, first, third
    row: 3, unavailable, third, first
  end
  assign(5, prefs) is table: student-id, lab-assigned
    row: 1, 1
    row: 2, 2
    row: 3, 3
  end
end

check "capacity forces some second choices, and the total cost is minimal":
  prefs = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref
    row: 1, first, second, third
    row: 2, first, second, third
    row: 3, first, third, second
  end
  out = assign(1, prefs)
  out satisfies respects(1, prefs, _)
  # one student per lab; student 3 should take lab 3 (its second choice)
  # rather than lab 2 (its third), so total cost is 0 + 1 + 1 = 2
  lab-for(out, 3) is 3
  lab-count(out, 1) is 1
  lab-count(out, 2) is 1
  lab-count(out, 3) is 1
end

check "unavailable labs are never assigned":
  prefs = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref
    row: 1, unavailable, unavailable, first
    row: 2, unavailable, unavailable, first
    row: 3, first, unavailable, second
  end
  out = assign(2, prefs)
  out satisfies respects(2, prefs, _)
  lab-for(out, 1) is 3
  lab-for(out, 2) is 3
  lab-for(out, 3) is 1
end

check "a student with no available lab, or labs that are too small, is an error":
  no-labs = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref
    row: 1, unavailable, unavailable, unavailable
  end
  assign(3, no-labs) raises "No assignment"
  crowded = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref
    row: 1, first, unavailable, unavailable
    row: 2, first, unavailable, unavailable
  end
  assign(1, crowded) raises "No assignment"
end

check "empty table":
  prefs = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref end
  assign(3, prefs) is table: student-id, lab-assigned end
end

check "a larger instance keeps every constraint":
  prefs = table: student-id, lab-1-pref, lab-2-pref, lab-3-pref
    row: 10, first, second, third
    row: 11, first, second, third
    row: 12, first, second, third
    row: 13, first, third, second
    row: 14, second, first, unavailable
    row: 15, unavailable, first, second
    row: 16, third, second, first
    row: 17, first, unavailable, second
    row: 18, second, third, first
  end
  out = assign(3, prefs)
  out satisfies respects(3, prefs, _)
  # students 15 and 16 can get their first choices without crowding lab 1
  lab-for(out, 15) is 2
  lab-for(out, 16) is 3
end
