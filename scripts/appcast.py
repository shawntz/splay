#!/usr/bin/env python3
"""Writes dist/appcast.xml, the Sparkle feed, for the signed and zipped dist/build/Splay.app."""
import datetime
import email.utils
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

REPO = "shawntz/splay"
CHANGELOG = Path("docs/changelog.md")
APP = Path("dist/build/Splay.app")

version = sys.argv[1]
archive = Path("dist/Splay.app.zip")
info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == version
signature = Path("dist/signature.txt").read_text().strip()
assert re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature), "Invalid Ed25519 signature"

# Sparkle shows this in its update window: the system font, the system's light or dark look, and a way to the rest.
NOTES_PAGE = """<!doctype html>
<meta charset="utf-8">
<style>
  :root { color-scheme: light dark; }
  body { font: 13px/1.45 -apple-system, sans-serif; margin: 10px 14px; }
  h3 { font-size: 13px; margin: 14px 0 4px; }
  h3:first-child, p:first-child { margin-top: 0; }
  ul { margin: 4px 0; padding-left: 18px; }
  li { margin: 3px 0; }
  code { font: 12px ui-monospace, monospace; }
  footer { margin-top: 14px; opacity: 0.6; }
</style>
{notes}
<footer>Every release: <a href="https://shawntz.github.io/splay/changelog/">shawntz.github.io/splay/changelog</a></footer>
"""


def release_notes(version):
    """The version's section of the changelog as a page for Sparkle, rendered by GitHub. None without one."""
    lines = CHANGELOG.read_text().splitlines()
    heading = f"## {version}"
    if heading not in lines:
        return None
    body = []
    for line in lines[lines.index(heading) + 1:]:
        if line.startswith("## "):
            break
        body.append(line)
    text = "\n".join(body).strip()
    if not text:
        return None
    html = subprocess.run(["gh", "api", "markdown", "-f", "mode=gfm", "-f", f"context={REPO}", "-f", f"text={text}"],
                          check=True, capture_output=True, text=True).stdout
    return NOTES_PAGE.replace("{notes}", html.strip())


ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "Splay"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = version
ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
# A build without an Intel slice tells Sparkle to skip Intel Macs, which otherwise would install an app they can't run.
archs = subprocess.run(["lipo", "-archs", str(APP / "Contents/MacOS/splay")],
                       check=True, capture_output=True, text=True).stdout.split()
if "x86_64" not in archs:
    ET.SubElement(item, f"{{{ns}}}hardwareRequirements").text = "arm64"
notes = release_notes(version)
if notes:
    ET.SubElement(item, "description").text = notes
else:
    ET.SubElement(item, f"{{{ns}}}releaseNotesLink").text = f"https://github.com/{REPO}/releases/tag/v{version}"
ET.SubElement(item, "enclosure", {
    "url": f"https://github.com/{REPO}/releases/download/v{version}/Splay.app.zip",
    "length": str(archive.stat().st_size),
    "type": "application/octet-stream",
    f"{{{ns}}}version": info["CFBundleVersion"],
    f"{{{ns}}}shortVersionString": version,
    f"{{{ns}}}edSignature": signature,
})
ET.indent(rss)
ET.ElementTree(rss).write("dist/appcast.xml", encoding="utf-8", xml_declaration=True)
