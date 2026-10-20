# Project status: docs/status.json

The Projects dashboard in kguydev/devops reads `docs/status.json` from every
repo to show its phase and next step. Keep the field names exactly as below;
the dashboard parses them.

```json
{"phase": "building", "next": "Ship the sign-in screen to TestFlight", "goal": "1.0"}
```

- `phase`: one of `idea`, `building`, `beta`, `live`, `maintenance`,
  `parked`.
- `next`: one line, in plain words, saying what happens next on the project.
- `goal`: the title of the GitHub milestone the project is working toward,
  or `""` when there is none. The dashboard draws a progress bar from that
  milestone.

A repo without the file gets the placeholder from `baseline/status.json`
when `scripts/apply-baseline.sh` runs, and `scripts/bootstrap.sh` resets a
new app's file to it. Replace the placeholder with the project's real
phase and next step.

There is no date field. The dashboard uses the file's last commit date and
flags a status older than 14 days.

Update the file in the same PR when the change:

- moves the project to another phase,
- completes or changes the next step, or
- switches the goal milestone.
