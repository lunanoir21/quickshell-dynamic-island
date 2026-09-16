#!/usr/bin/env python3
"""Keeps the READMEs and the website's data in step with the changelog.

CHANGELOG.md (English) and CHANGELOG.tr.md (Turkish) are the only files that
hold release notes. This script rewrites the generated blocks between
`<!-- changelog:readme:start -->` and `<!-- changelog:readme:end -->` in the
READMEs — the latest release, under "What changed" — and regenerates
docs/changelog.json, which docs/index.html and docs/changelog.html read.
Those HTML files are never touched; they stay built from the JSON at runtime.

Each release carries three things the plain Keep a Changelog format has no
slot for: a bold title line, a summary paragraph, and a `### Shots` section.
A shot bullet uses the image's markdown title attribute for the wide flag:

    ## [2026.08.17] - 2026-08-17

    **A short sentence, not a version bump**

    Two or three sentences saying what changed and why.

    ### Added

    - One change per bullet; wrapped lines are indented two spaces.

    ### Shots

    - ![what the image shows](screenshots/name.png "wide") — **caption**
      — the sentence underneath.

Versions are dates (YYYY.MM.DD), because that is how this project releases.
The Turkish changelog must list the same versions as the English one; the
script refuses to run while they diverge.

Usage:
  python3 scripts/changelog.py                 rewrite the generated files
  python3 scripts/changelog.py --check         exit 1 if anything is stale
  python3 scripts/changelog.py --notes 2026.08.17 [--lang tr]
                                               one release as Markdown,
                                               e.g. for a GitHub release
"""
import argparse
import html
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/lunanoir21/quickshell-dynamic-island"
SITE_CHANGELOG = "https://lunanoir21.github.io/quickshell-dynamic-island/changelog.html"

RELEASE = re.compile(r"^## \[(?P<version>[^\]]+)\](?:\s+-\s+(?P<date>\d{4}-\d{2}-\d{2}))?\s*$")
TITLE = re.compile(r"^\*\*(?P<title>.+?)\*\*\s*$")
GROUP = re.compile(r"^### (?P<name>.+?)\s*$")
BULLET = re.compile(r"^- (?P<text>.+)$")
LINK_DEFINITION = re.compile(r"^\[[^\]]+\]:\s")

CHANGE_TYPES = frozenset({"added", "changed", "fixed", "removed"})

LANGS = {
    "en": {"source": "CHANGELOG.md", "readme": "README.md"},
    "tr": {"source": "CHANGELOG.tr.md", "readme": "README.tr.md"},
}

FULL_CHANGELOG = {
    "en": f"[Full changelog →]({SITE_CHANGELOG})",
    "tr": f"[Tüm değişiklik günlüğü →]({SITE_CHANGELOG})",
}

SHOT_IMAGE = re.compile(
    r"^!\[(?P<alt>[^\]]*)\]\((?P<src>[^\s)]+)(?:\s+\"(?P<title>[^\"]*)\")?\)\s*(?P<rest>.*)$")


def fail(message):
    sys.exit(f"changelog: {message}")


def parse_shot(line):
    match = SHOT_IMAGE.match(line)
    if not match:
        fail(f"shot bullet does not look like `![alt](src \"wide\") — **caption** — text`: {line!r}")
    shot = {"src": match["src"], "alt": match["alt"]}
    if match["title"] == "wide":
        shot["wide"] = True
    rest = match["rest"].strip()
    if rest.startswith("—"):
        rest = rest[1:].strip()
    if rest:
        caption = re.match(r"^\*\*(?P<caption>.+?)\*\*", rest)
        if caption:
            shot["caption"] = caption["caption"]
            rest = rest[caption.end():].strip()
        if rest.startswith("—"):
            rest = rest[1:].strip()
        if rest:
            shot["text"] = rest
    return shot


def parse(path):
    """Releases in file order, newest first: [{version, date, title, summary,
    groups: [{type, name, items}], shots: [{src, alt, caption, text, wide}]}]."""
    releases = []
    release = None
    group = None
    mode = None            # "changes" or "shots"
    title_seen = False
    pending_shot = None    # wrapped shot bullet, accumulated before parsing

    def flush_shot():
        nonlocal pending_shot
        if pending_shot is not None:
            release["shots"].append(parse_shot(pending_shot))
            pending_shot = None

    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.rstrip()

        if RELEASE.match(line):
            flush_shot()
            match = RELEASE.match(line)
            release = {"version": match["version"], "date": match["date"],
                       "groups": [], "shots": [], "summary_parts": []}
            releases.append(release)
            group = mode = None
            title_seen = False
            continue
        if release is None or LINK_DEFINITION.match(line):
            continue
        if not line.strip():
            continue

        if not title_seen:
            match = TITLE.match(line)
            if not match:
                fail(f"{path.name}:{number}: release {release['version']} needs a **title** line "
                     f"before any heading or bullet")
            release["title"] = match["title"]
            title_seen = True
            continue

        match = GROUP.match(line)
        if match:
            flush_shot()
            name = match["name"]
            if name.lower() in CHANGE_TYPES:
                group = {"type": name.lower(), "name": name, "items": []}
                release["groups"].append(group)
                mode = "changes"
            elif name.lower() == "shots":
                group = None
                mode = "shots"
            else:
                fail(f"{path.name}:{number}: unknown group heading `{name}` "
                     "(a change type or Shots expected)")
            continue

        if line.startswith("  "):
            if mode == "shots" and pending_shot is not None:
                pending_shot += " " + line.strip()
            elif mode == "changes" and group is not None and group["items"]:
                group["items"][-1] += " " + line.strip()
            continue

        match = BULLET.match(line)
        if match:
            if mode == "shots":
                flush_shot()
                pending_shot = match["text"]
            elif mode == "changes" and group is not None:
                group["items"].append(match["text"].strip())
            else:
                fail(f"{path.name}:{number}: a bullet needs a ### group above it")
            continue

        release["summary_parts"].append(line.strip())

    flush_shot()
    for rel in releases:
        rel["summary"] = " ".join(rel.pop("summary_parts")) or None
    return releases


def released(releases, path):
    dated = [r for r in releases if r["date"]]
    if not dated:
        fail(f"{path.name} has no dated release")
    return releases


def wrap(text, width=78):
    lines, current = [], ""
    for word in text.split(" "):
        if not current:
            current = word
        elif len(current) + 1 + len(word) <= width:
            current += " " + word
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return "\n".join(lines)


def shot_cell(shot):
    src = shot["src"] if shot["src"].startswith("docs/") else "docs/" + shot["src"]
    alt = html.escape(shot.get("alt", ""), quote=True)
    caption = html.escape(shot.get("caption", ""), quote=False)
    text = html.escape(shot.get("text", ""), quote=False)
    sub = f"<b>{caption}</b> — {text}" if caption and text else caption or text
    return f'<img src="{src}" alt="{alt}"><br><sub>{sub}</sub>'


def render_shots_table(shots):
    rows, pending = [], []
    for shot in shots:
        if shot.get("wide"):
            if pending:
                rows.append("<tr>\n" + "\n".join(pending) + "\n</tr>")
                pending = []
            rows.append(f'<tr>\n<td colspan="2">{shot_cell(shot)}</td>\n</tr>')
        else:
            pending.append(f'<td width="50%">{shot_cell(shot)}</td>')
            if len(pending) == 2:
                rows.append("<tr>\n" + "\n".join(pending) + "\n</tr>")
                pending = []
    if pending:
        rows.append("<tr>\n" + "\n".join(pending) + "\n</tr>")
    return "<table>\n" + "\n".join(rows) + "\n</table>"


def readme_block(release, lang):
    chunks = [wrap(f"**{release['title']}** — {release['summary']}")]
    if release.get("shots"):
        chunks.append(render_shots_table(release["shots"]))
    chunks.append(FULL_CHANGELOG[lang])
    return "\n\n".join(chunks) + "\n"


def release_data(release):
    obj = {"version": release["version"], "date": release["date"]}
    if release["title"]:
        obj["title"] = release["title"]
    if release["summary"]:
        obj["summary"] = release["summary"]
    obj["changes"] = [{"type": g["type"], "text": item}
                      for g in release["groups"] for item in g["items"]]
    if release["shots"]:
        shots = []
        for shot in release["shots"]:
            entry = {"src": shot["src"], "alt": shot["alt"]}
            for key in ("caption", "text"):
                if shot.get(key):
                    entry[key] = shot[key]
            if shot.get("wide"):
                entry["wide"] = True
            shots.append(entry)
        obj["shots"] = shots
    return obj


def json_block(releases):
    data = {
        "$comment": ("Generated by scripts/changelog.py from CHANGELOG.md/CHANGELOG.tr.md. "
                     "Edit the changelog files, not this one. docs/index.html shows the newest "
                     "entry; docs/changelog.html renders all of them. Screenshot paths are "
                     "relative to docs/."),
        "releases": [release_data(r) for r in releases],
    }
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def replace_block(text, name, body, path):
    pattern = re.compile(
        rf"^(?P<indent>[ \t]*)<!-- changelog:{name}:start -->\n.*?^[ \t]*<!-- changelog:{name}:end -->$",
        re.M | re.S)
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        fail(f"{path.relative_to(ROOT)} needs exactly one changelog:{name} block, found {len(matches)}")
    match = matches[0]
    indent = match["indent"]
    body_lines = [indent + line if line else "" for line in body.rstrip("\n").split("\n")]
    if body.endswith("\n\n"):
        body_lines.append("")
    block = (f"{indent}<!-- changelog:{name}:start -->\n"
             + "\n".join(body_lines)
             + f"\n{indent}<!-- changelog:{name}:end -->")
    return text[:match.start()] + block + text[match.end():]


def build():
    """{path: (current text, generated text)} for every file we own."""
    parsed = {lang: parse(ROOT / config["source"]) for lang, config in LANGS.items()}

    versions = {lang: [r["version"] for r in releases] for lang, releases in parsed.items()}
    if len(set(map(tuple, versions.values()))) != 1:
        fail("CHANGELOG.md and CHANGELOG.tr.md list different versions: "
             + "; ".join(f"{lang}: {', '.join(v)}" for lang, v in versions.items()))

    outputs = {}
    for lang, config in LANGS.items():
        releases = released(parsed[lang], ROOT / config["source"])
        path = ROOT / config["readme"]
        text = path.read_text(encoding="utf-8")
        outputs[path] = (text, replace_block(text, "readme", readme_block(releases[0], lang), path))

    json_path = ROOT / "docs" / "changelog.json"
    current = json_path.read_text(encoding="utf-8")
    outputs[json_path] = (current, json_block(parsed["en"]))
    return outputs


def notes(release):
    lines = [f"**{release['title']}**", ""]
    if release["summary"]:
        lines += [release["summary"], ""]
    for group in release["groups"]:
        if not group["items"]:
            continue
        lines += [f"### {group['name']}", ""]
        lines += [f"- {item}" for item in group["items"]]
        lines.append("")
    raw_base = f"{REPO_URL}/raw/main/docs/"
    for shot in release["shots"]:
        lines.append(f'![{shot.get("alt", "")}]({raw_base}{shot["src"]})')
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if a generated file is out of date")
    parser.add_argument("--notes", metavar="VERSION", help="print one release's notes as Markdown")
    parser.add_argument("--lang", choices=sorted(LANGS), default="en", help="language for --notes")
    args = parser.parse_args()

    if args.notes:
        source = ROOT / LANGS[args.lang]["source"]
        for release in parse(source):
            if release["version"] == args.notes:
                sys.stdout.write(notes(release))
                return 0
        fail(f"{source.name} has no release {args.notes}")

    outputs = build()
    stale = [path for path, (current, generated) in outputs.items() if current != generated]

    if args.check:
        for path in stale:
            print(f"out of date: {path.relative_to(ROOT)}")
        if stale:
            print("run: python3 scripts/changelog.py")
            return 1
        print("changelog is up to date")
        return 0

    for path in stale:
        path.write_text(outputs[path][1], encoding="utf-8")
        print(f"updated {path.relative_to(ROOT)}")
    if not stale:
        print("nothing to update")
    return 0


if __name__ == "__main__":
    sys.exit(main())