#!/usr/bin/env python3
"""Check the isolated public Pages payload; never package the whole docs tree."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent / "docs" / "site"


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.h1 = 0
        self.language = False
        self.viewport = False
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if tag in {"script", "iframe", "form", "object", "embed"}:
            raise ValueError(f"Unsupported active content: {tag}")
        if any(name.startswith("on") for name in attrs):
            raise ValueError("Inline event handler is not allowed")
        if "id" in attrs:
            if attrs["id"] in self.ids:
                raise ValueError("Duplicate HTML id")
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.h1 += 1
        if tag == "html":
            self.language = bool(attrs.get("lang"))
        if tag == "meta" and attrs.get("name") == "viewport":
            self.viewport = bool(attrs.get("content"))
        for name in ("href", "src"):
            if name in attrs:
                self.links.append((tag, attrs[name]))


def validate():
    files = sorted(ROOT.rglob("*"))
    pages = {}
    for path in files:
        if path.is_symlink():
            raise ValueError("Symlinks cannot enter the public site payload")
        if path.is_dir():
            continue
        if path.suffix == ".png":
            data = path.read_bytes()
            if not data.startswith(b"\x89PNG\r\n\x1a\n") or not 24 <= len(data) <= 2_000_000:
                raise ValueError("Invalid or oversized PNG")
            width, height = struct.unpack(">II", data[16:24])
            if not (0 < width <= 2048 and 0 < height <= 2048):
                raise ValueError("PNG dimensions exceed public asset limits")
            continue
        if path.suffix == ".svg":
            text = path.read_text(encoding="utf-8")
            if re.search(r"/Users/|/private/var/|BEGIN .*PRIVATE KEY|<!DOCTYPE|<!ENTITY", text, re.IGNORECASE):
                raise ValueError("Private or unsupported SVG content")
            tree = ET.fromstring(text)
            for element in tree.iter():
                if element.tag.split("}")[-1] not in {"svg", "path", "circle", "rect", "g"}:
                    raise ValueError("Unsupported SVG element")
                if any(name.startswith("on") or name.split("}")[-1] in {"href", "style"} or "url(" in value for name, value in element.attrib.items()):
                    raise ValueError("Active or external SVG content")
            continue
        if path.name == "bootstrap-icons-license.txt":
            text = path.read_text(encoding="utf-8")
            if "MIT License" not in text or re.search(r"/Users/|BEGIN .*PRIVATE KEY", text):
                raise ValueError("Unexpected icon license contents")
            continue
        if path.suffix not in {".html", ".css"}:
            raise ValueError(f"Unexpected public asset: {path.name}")
        text = path.read_text(encoding="utf-8")
        if re.search(r"/Users/|/private/var/|@icloud\.com|BEGIN .*PRIVATE KEY|chatgpt-conversation://", text):
            raise ValueError(f"Private operational content in {path.name}")
        if path.suffix == ".css" and re.search(r"@import|url\s*\(", text, re.IGNORECASE):
            raise ValueError("CSS must not fetch external assets")
        if path.suffix == ".html":
            page = Page(text)
            if page.h1 != 1 or not page.language or not page.viewport:
                raise ValueError(f"Missing document accessibility metadata: {path.name}")
            pages[path.resolve()] = page
    if not all((ROOT / name).resolve() in pages for name in ("index.html", "privacy.html", "support.html")):
        raise ValueError("Missing required public page")
    for path, page in pages.items():
        for tag, link in page.links:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc:
                if parsed.scheme != "https" or tag != "a" or parsed.username or parsed.password:
                    raise ValueError("Only HTTPS navigation links may leave the site")
                continue
            target = (path.parent / unquote(parsed.path)).resolve() if parsed.path else path
            if not target.is_relative_to(ROOT.resolve()) or not target.is_file():
                raise ValueError(f"Broken or escaping local link: {path.name}: {link}")
            if parsed.fragment and (target not in pages or unquote(parsed.fragment) not in pages[target].ids):
                raise ValueError(f"Missing linked anchor: {path.name}: {link}")
    print(f"PASS: {len(pages)} static public pages; local links, anchors and payload boundaries verified.")


if __name__ == "__main__":
    try:
        validate()
    except (ValueError, OSError, ET.ParseError, struct.error) as error:
        sys.exit(f"FAIL: {error}")
