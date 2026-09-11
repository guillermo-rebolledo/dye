#!/usr/bin/env python3
"""Publish the app's own privacy policy and support text as two web pages.

App Store Connect demands a reachable URL for each, and a page that says something
different from the app is worse than no page at all. So there is one source — the
`privacyPolicy` and `support` properties of `FilmApp/Legal.swift` — and these pages
are generated from it. `Scripts/test_ci_site.py` fails the build when the committed
HTML no longer matches the Swift, which is the only thing that keeps the two honest.

    python3 Scripts/build-site.py            # regenerate docs/
    python3 Scripts/build-site.py --check    # fail if docs/ is stale

The output goes in `docs/` because GitHub Pages serves a repository's `/docs` folder
from the default branch with no build step and no workflow to go wrong.
"""

import html
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEGAL = ROOT / "FilmApp/Legal.swift"
SITE = ROOT / "docs"

# The published pages. Each is a Swift property, a directory under docs/, and a title.
PAGES = [
    ("privacyPolicy", "privacy", "Privacy Policy"),
    ("support", "support", "Support"),
]

STYLE = """\
:root { color-scheme: light dark; }
body { margin: 0 auto; padding: 3rem 1.25rem 5rem; max-width: 34rem;
       font: 1rem/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
       background: Canvas; color: CanvasText; }
h1 { font-size: 1.6rem; margin: 0 0 0.25rem; }
h2 { font-size: 1rem; margin: 2rem 0 0.5rem; }
p { margin: 0 0 1rem; }
a { color: inherit; }
footer { margin-top: 3rem; font-size: 0.85rem; opacity: 0.7; }\
"""


def swift_literal(source, name):
    """The text of `static let <name> = \"\"\"…\"\"\"`, as Swift would see it.

    Swift strips the closing delimiter's indentation from every line and treats a
    trailing backslash as "this line continues", which is how the source stays inside
    a sensible column width while the text stays one paragraph.
    """
    opening = f'static let {name} = """'
    start = source.index(opening) + len(opening)
    start = source.index("\n", start) + 1
    end = source.index('"""', start)
    indent = source[source.rfind("\n", 0, end) + 1:end]
    text = ""
    for line in source[start:end].split("\n")[:-1]:
        line = line[len(indent):] if line.startswith(indent) else line.lstrip()
        if line.endswith("\\"):
            text += line[:-1]
        else:
            text += line + "\n"
    return text.rstrip("\n")


def blocks(text):
    """Paragraphs, tagged as heading or prose.

    A paragraph that is one line long and does not end in a full stop is a heading —
    "Your photographs", "Children". That is a convention about the source text rather
    than a guess about English, and the app renders the same lines as plain prose.
    """
    for chunk in text.split("\n\n"):
        chunk = chunk.strip()
        if not chunk:
            continue
        is_heading = "\n" not in chunk and not chunk.endswith(".")
        yield ("h2" if is_heading else "p"), chunk


def render(title, text, link):
    body = [f"<h1>{html.escape(title)}</h1>"]
    for tag, chunk in blocks(text):
        body.append(f"<{tag}>{html.escape(chunk)}</{tag}>")
    if link:
        body.append(f'<p><a href="{link}">{html.escape(link)}</a></p>')
    body.append('<footer>Dye is an independent iPhone app. '
                '<a href="https://github.com/guillermo-rebolledo/dye">Source on GitHub</a>.</footer>')
    joined = "\n".join(body)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dye — {html.escape(title)}</title>
<style>
{STYLE}
</style>
</head>
<body>
{joined}
</body>
</html>
"""


INDEX = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dye</title>
<style>
""" + STYLE + """
</style>
</head>
<body>
<h1>Dye</h1>
<p>A film simulator for iPhone. It renders your photograph through a physical model
of a film stock, on your device, with no account and no network.</p>
<p><a href="privacy/">Privacy Policy</a></p>
<p><a href="support/">Support</a></p>
<footer>Dye is an independent iPhone app.
<a href="https://github.com/guillermo-rebolledo/dye">Source on GitHub</a>.</footer>
</body>
</html>
"""


def expected():
    """Every generated path and its contents, so building and checking cannot drift."""
    source = LEGAL.read_text()
    files = {
        SITE / "index.html": INDEX,
        # Tells GitHub Pages to serve these files as they are rather than running the
        # rest of docs/ through Jekyll, which would try to build the audits.
        SITE / ".nojekyll": "",
    }
    for name, directory, title in PAGES:
        link = "https://github.com/guillermo-rebolledo/dye/issues" if name == "support" else None
        files[SITE / directory / "index.html"] = render(title, swift_literal(source, name), link)
    return files


def main():
    checking = "--check" in sys.argv[1:]
    stale = []
    for path, contents in expected().items():
        if checking:
            if not path.is_file() or path.read_text() != contents:
                stale.append(path.relative_to(ROOT))
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
    if stale:
        print("build-site: these are out of date with FilmApp/Legal.swift:", file=sys.stderr)
        for path in stale:
            print(f"  {path}", file=sys.stderr)
        print("build-site: run python3 Scripts/build-site.py", file=sys.stderr)
        sys.exit(1)
    print(f"build-site: {'checked' if checking else 'wrote'} {len(expected())} files under docs/")


if __name__ == "__main__":
    main()
