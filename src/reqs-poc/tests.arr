use context starter2024

include file("reqs-common.arr")
include file("check-reqs.arr")

### DO NOT EDIT ANYTHING ABOVE THIS LINE ###

# Do not refer to anything from check-reqs.arr (other than check-reqs itself).
# You may define helpers here and use them in check blocks.

# A roster that meets every rule in the proof-of-concept subset.
full = [list:
  "CSCI 0190", "CSCI 0200", "CSCI 0220", "CSCI 0500", "CSCI 0410", "CSCI 0300",
  "CSCI 1010", "CSCI 1230", "CSCI 1270", "CSCI 1300", "CSCI 1410"]

check "example":
  check-reqs([list: ]) is all-necessary
end

check "examples from the assignment":
  check-reqs([list: "CSCI 0190", "CSCI 0200"]) is all-necessary
  check-reqs([list: "CSCI 0190", "CSCI 0150"]) is has-unnecessary
end

check "malformed input takes priority":
  check-reqs([list: "csci 0190"]) is malformed
  check-reqs([list: "CSCI0190"]) is malformed
  check-reqs([list: "CSCI 190"]) is malformed
  check-reqs([list: "CSCI 019A"]) is malformed
  check-reqs([list: "CSC 0190"]) is malformed
  check-reqs([list: "CSCI  0190"]) is malformed
  check-reqs(full + [list: "oops"]) is malformed
  # suffixes after the digits and three-letter departments are fine
  check-reqs([list: "CSCI 2951S"]) is all-necessary
  check-reqs([list: "CSCI 2951-S"]) is all-necessary
  check-reqs([list: "PHP  0060"]) is all-necessary
end

check "completion":
  check-reqs(full) is completed
  # extra courses do not stop a complete roster from completing
  check-reqs(full + [list: "CSCI 0330", "CSCI 0150"]) is completed
  # one short
  check-reqs(full.rest) is all-necessary  # without CSCI 0190: intro-1 stays empty, every other course is used
  check-reqs(full.take(10)) is all-necessary
end

check "intro sequences":
  check-reqs([list: "CSCI 0150", "CSCI 0200"]) is all-necessary
  check-reqs([list: "CSCI 0170", "CSCI 0200"]) is all-necessary
  check-reqs([list: "CSCI 0111", "CSCI 0200"]) is all-necessary
  check-reqs([list: "CSCI 0150", "CSCI 0170", "CSCI 0200"]) is has-unnecessary
  # after CSCI 0190, a 1000-level course can complete the intro sequence
  check-reqs([list: "CSCI 0190", "CSCI 1010"]) is all-necessary
  # but after CSCI 0150 it cannot, and CSCI 0150 alone is still progress
  check-reqs([list: "CSCI 0150"]) is all-necessary
  check-reqs([list: "CSCI 0150", "CSCI 1010"]) is all-necessary
  check-reqs([list: "CSCI 0150", "CSCI 0190", "CSCI 0200"]) is has-unnecessary
end

check "foundations and electives":
  check-reqs([list: "CSCI 0300", "CSCI 0330"]) is has-unnecessary
  check-reqs([list: "CSCI 0220", "MATH 1530"]) is has-unnecessary
  check-reqs([list: "CSCI 0500", "CSCI 0410", "CSCI 0300", "CSCI 0220"]) is all-necessary
  # six 1000-level courses after CSCI 0190: one fills intro-2, five are technical
  check-reqs([list: "CSCI 0190", "CSCI 1010", "CSCI 1230", "CSCI 1270", "CSCI 1300", "CSCI 1410", "CSCI 1420"]) is all-necessary
  # seven: one too many
  check-reqs([list: "CSCI 0190", "CSCI 1010", "CSCI 1230", "CSCI 1270", "CSCI 1300", "CSCI 1410", "CSCI 1420", "CSCI 1430"]) is has-unnecessary
end

check "courses outside the concentration are ignored":
  check-reqs([list: "ENGL 0100"]) is all-necessary
  check-reqs([list: "CSCI 0190", "MATH 0100", "APMA 1650"]) is all-necessary
end
