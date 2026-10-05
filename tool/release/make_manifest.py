"""Writes the files the in-app updater reads, next to the release packages in dist/:

  latest.json      version, minSupportedVersion, notes, and name/sha256/size per package
  SHA256SUMS.txt   checksums for manual verification
  notes.md         this version's section of CHANGELOG.md (the release body)

    python tool/release/make_manifest.py 2.0.0 [dist]
"""
import hashlib
import json
import os
import re
import sys

PACKAGES = {
    "android": "QuickShareStudio-Android.apk",
    "windows": "QuickShareStudio-Windows-x64.zip",
    "windows_setup": "QuickShareStudio-Windows-Setup.exe",
    "linux": "QuickShareStudio-Linux.tar.gz",
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def changelog_section(version, path="CHANGELOG.md"):
    lines, found = [], False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("## ["):
                if found:
                    break
                found = line.startswith(f"## [{version}]")
                continue
            if found:
                lines.append(line)
    if not found:
        raise SystemExit(f"CHANGELOG.md has no section for {version}")
    return "".join(lines).strip() + "\n"


def main():
    version = sys.argv[1].lstrip("v")
    dist = sys.argv[2] if len(sys.argv) > 2 else "dist"
    with open("MIN_SUPPORTED_VERSION", encoding="utf-8") as f:
        minimum = f.read().strip()
    notes_md = changelog_section(version)
    # Short notes for the update dialog: the bold title of each entry ("- **Title:** details").
    notes = []
    for line in notes_md.splitlines():
        if line.startswith("- "):
            m = re.match(r"- \*\*(.+?)\*\*", line)
            notes.append((m.group(1) if m else line[2:]).strip().rstrip(":").strip())
    notes = notes[:8]

    packages, sums = {}, []
    for key, name in PACKAGES.items():
        path = os.path.join(dist, name)
        if not os.path.isfile(path):
            raise SystemExit(f"Required release package is missing: {path}")
        digest = sha256(path)
        packages[key] = {"name": name, "sha256": digest, "size": os.path.getsize(path)}
        sums.append(f"{digest}  {name}\n")

    manifest = {"version": version, "minSupportedVersion": minimum, "notes": notes, "packages": packages}
    with open(os.path.join(dist, "latest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    with open(os.path.join(dist, "SHA256SUMS.txt"), "w", encoding="utf-8") as f:
        f.writelines(sums)
    with open(os.path.join(dist, "notes.md"), "w", encoding="utf-8") as f:
        f.write(notes_md)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
