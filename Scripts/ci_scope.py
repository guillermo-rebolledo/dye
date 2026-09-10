"""Select CI jobs conservatively from the complete PR merge diff."""

import os
import subprocess


def classify(paths):
    engine = app = False
    for path in paths:
        if path in {"README.md", "CONTEXT.md"} or path.startswith(
            ("docs/", "design_handoff_dye_editor/")
        ):
            continue
        if path.startswith(("FilmApp/", "FilmApp.xcodeproj/")):
            app = True
        elif path.startswith(("Tests/", "ProfileBaker/")):
            engine = True
        else:
            # Shared engine resources, curves, build/CI configuration, scripts,
            # and unfamiliar paths all require full validation.
            engine = app = True
    return engine, app


def scope(base):
    if not base:
        # Pushes to main and manual runs always exercise the complete workflow.
        return True, True
    # HEAD is GitHub's tested merge commit. Comparing it directly to the PR base
    # covers all PR commits without a full-history fetch or API pagination.
    # Disable rename detection so a move out of source into docs still tests
    # the deleted source path. NUL delimiters preserve unusual filenames.
    changed = subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD", "--"]
    )
    return classify(os.fsdecode(path) for path in changed.split(b"\0") if path)


if __name__ == "__main__":
    engine, app = scope(os.environ.get("BASE_SHA", ""))
    result = f"engine={str(engine).lower()}\napp={str(app).lower()}\n"
    print(result, end="")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as file:
            file.write(result)
