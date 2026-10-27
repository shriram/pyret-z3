use context starter2024

provide *
provide-types *

### DO NOT CHANGE.

# You will not upload this: the grader supplies its own copy.

data Completion:
  | completed        # requirements met, can graduate
  | all-necessary    # making progress, no unnecessary courses
  | has-unnecessary  # making progress, has unnecessary courses
  | malformed        # input is malformed
end
