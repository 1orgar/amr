#!/usr/bin/env python3
"""
Assemble modular Web PWA sources (Web/src/{js,css,html}/*) into Web/{app.js,style.css,index.html},
stamp SHA-256 content hashes into index.html (?v=<hash>) and Web/sw.js (CACHE_NAME),
and (unless --web-only is passed) synchronize embedded Swift raw string literals in
Sources/AppleMusicRemoteMac/Server/WebUIContent*.swift with injection-safe '#' delimiters.
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path


def sha256_short(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()[:8]


def choose_swift_raw_delimiters(content: str) -> tuple[str, str]:
    hashes = 1
    while ('"""' + ("#" * hashes)) in content:
        hashes += 1
    pad = "#" * hashes
    return f'{pad}"""', f'"""{pad}'


def write_if_changed(path: Path, content: str) -> bool:
    if path.is_file():
        existing = path.read_text(encoding="utf-8")
        if existing == content:
            return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


def assemble_js(js_src_dir: Path) -> tuple[str, list[Path]]:
    files = sorted(p for p in js_src_dir.glob("*.js") if p.is_file())
    if not files:
        raise FileNotFoundError(f"No JS modules found in {js_src_dir}")

    parts = [
        "/* AUTO-ASSEMBLED FROM Web/src/js/*.js BY Tools/sync_web_ui.py — EDIT Web/src/js/ MODULES */",
        "(() => {",
        '"use strict";',
        "",
    ]
    for fpath in files:
        mod_text = fpath.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
        parts.append(f"// === MODULE: {fpath.name} ===")
        parts.append(mod_text)
        parts.append("")

    parts.append("})();")
    parts.append("")
    return "\n".join(parts), files


def assemble_css(css_src_dir: Path) -> tuple[str, list[Path]]:
    files = sorted(p for p in css_src_dir.glob("*.css") if p.is_file())
    if not files:
        raise FileNotFoundError(f"No CSS modules found in {css_src_dir}")

    parts = [
        "/* AUTO-ASSEMBLED FROM Web/src/css/*.css BY Tools/sync_web_ui.py — EDIT Web/src/css/ MODULES */",
        "",
    ]
    for fpath in files:
        mod_text = fpath.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
        parts.append(f"/* === MODULE: {fpath.name} === */")
        parts.append(mod_text)
        parts.append("")

    return "\n".join(parts), files


def assemble_html(html_src_dir: Path, css_hash: str, js_hash: str) -> tuple[str, list[Path]]:
    files = sorted(p for p in html_src_dir.glob("*.html") if p.is_file())
    if not files:
        raise FileNotFoundError(f"No HTML partials found in {html_src_dir}")

    chunks = [p.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n") for p in files]
    raw_html = "\n".join(chunks) + "\n"

    # Insert auto-assembled notice immediately after <!DOCTYPE html> so standards mode is preserved
    raw_html = re.sub(
        r"^(<!DOCTYPE html>\s*\n)",
        r"\1<!-- AUTO-ASSEMBLED FROM Web/src/html/*.html BY Tools/sync_web_ui.py — EDIT Web/src/html/ PARTIALS -->\n",
        raw_html,
        count=1,
        flags=re.IGNORECASE,
    )

    raw_html = re.sub(r"(/style\.css)(?:\?v=[A-Za-z0-9._-]+)?", rf"\1?v={css_hash}", raw_html)
    raw_html = re.sub(r"(/app\.js)(?:\?v=[A-Za-z0-9._-]+)?", rf"\1?v={js_hash}", raw_html)
    return raw_html, files


def update_service_worker_cache_name(sw_path: Path, combined_hash: str) -> str:
    sw_text = sw_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    updated_sw, count = re.subn(
        r"const\s+CACHE_NAME\s*=\s*['\"]amr-shell-[^'\"]*['\"]\s*;",
        f"const CACHE_NAME = 'amr-shell-{combined_hash}';",
        sw_text,
        count=1,
    )
    if count == 0:
        raise RuntimeError(f"Could not locate CACHE_NAME declaration in {sw_path}")
    write_if_changed(sw_path, updated_sw)
    return updated_sw


def build_swift_extension_file(swift_filename: str, prop_name: str, raw_content: str) -> str:
    clean = raw_content.replace("\r\n", "\n").rstrip("\n")
    open_d, close_d = choose_swift_raw_delimiters(clean)
    return (
        f"//\n"
        f"//  {swift_filename}\n"
        f"//  AppleMusicRemoteMac\n"
        f"//\n\n"
        f"import Foundation\n\n"
        f"extension WebUIContent {{\n"
        f"    public static let {prop_name}: String = {open_d}\n"
        f"{clean}\n"
        f"{close_d}\n"
        f"}}\n"
    )


def sync_swift_files(amr_dir: Path, web_dir: Path) -> list[str]:
    server_dir = amr_dir / "Sources" / "AppleMusicRemoteMac" / "Server"
    updated: list[str] = []

    # Remove legacy 30K-line embedded WebUIContent+{JS,CSS,HTML}.swift files if present;
    # primary Web bundles are served directly from Resources/Web (or AppleMusicRemoteMac/Web in dev/tests).
    for legacy_name in ("WebUIContent+JS.swift", "WebUIContent+CSS.swift", "WebUIContent+HTML.swift"):
        legacy_path = server_dir / legacy_name
        if legacy_path.is_file():
            legacy_path.unlink()
            updated.append(f"removed {legacy_name}")

    core_swift = server_dir / "WebUIContent.swift"
    if core_swift.is_file():
        core_text = core_swift.read_text(encoding="utf-8").replace("\r\n", "\n")
        orig_core_text = core_text
        inline_targets = [
            ("manifest.json", ("manifestJSON",)),
            ("sw.js", ("serviceWorkerJS", "swJS")),
            ("apple-touch-icon.svg", ("appleTouchIconSVG", "iconSVG")),
        ]
        for web_name, prop_candidates in inline_targets:
            web_file = web_dir / web_name
            if not web_file.is_file():
                continue
            clean = web_file.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
            open_d, close_d = choose_swift_raw_delimiters(clean)
            for prop in prop_candidates:
                pattern = rf"(public\s+static\s+let\s+{re.escape(prop)}\s*:\s*String\s*=\s*)(?:#*\"\"\"\n.*?\n\s*\"\"\"#*)"
                core_text = re.sub(
                    pattern,
                    lambda m, od=open_d, cd=close_d, body=clean: f"{m.group(1)}{od}\n{body}\n{cd}",
                    core_text,
                    flags=re.DOTALL,
                )
        if core_text != orig_core_text:
            write_if_changed(core_swift, core_text)
            updated.append("WebUIContent.swift")

    return updated


def main() -> int:
    parser = argparse.ArgumentParser(description="Assemble Web UI sources and sync Swift WebUIContent.")
    parser.add_argument(
        "--web-only",
        action="store_true",
        help="Only assemble Web/{app.js,style.css,index.html} and stamp Web/sw.js without touching Swift files.",
    )
    args = parser.parse_args()

    amr_dir = Path(__file__).resolve().parent.parent
    web_dir = amr_dir / "Web"
    src_dir = web_dir / "src"

    js_text, js_files = assemble_js(src_dir / "js")
    css_text, css_files = assemble_css(src_dir / "css")

    write_if_changed(web_dir / "app.js", js_text)
    write_if_changed(web_dir / "style.css", css_text)

    js_hash = sha256_short(js_text)
    css_hash = sha256_short(css_text)

    html_text, html_files = assemble_html(src_dir / "html", css_hash=css_hash, js_hash=js_hash)
    write_if_changed(web_dir / "index.html", html_text)

    manifest_text = (web_dir / "manifest.json").read_text(encoding="utf-8") if (web_dir / "manifest.json").is_file() else ""
    icon_text = (web_dir / "apple-touch-icon.svg").read_text(encoding="utf-8") if (web_dir / "apple-touch-icon.svg").is_file() else ""
    combined_hash = sha256_short("\n".join([html_text, css_text, js_text, manifest_text, icon_text]))
    update_service_worker_cache_name(web_dir / "sw.js", combined_hash)

    mode_note = "web-only"
    if not args.web_only:
        swift_updated = sync_swift_files(amr_dir, web_dir)
        mode_note = f"synced Swift ({', '.join(swift_updated) if swift_updated else 'already up to date'})"

    print(
        f"[sync_web_ui] Assembled {len(js_files)} JS -> app.js ({js_hash}), "
        f"{len(css_files)} CSS -> style.css ({css_hash}), "
        f"{len(html_files)} HTML -> index.html, "
        f"sw.js -> amr-shell-{combined_hash} [{mode_note}]"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
