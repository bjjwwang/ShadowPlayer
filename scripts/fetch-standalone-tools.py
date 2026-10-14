#!/usr/bin/env python3
"""Fetch pinned upstream macOS releases and verify their SHA-256 digests."""
import concurrent.futures
import hashlib
import json
import re
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".build" / "standalone-tools"
CACHE.mkdir(parents=True, exist_ok=True)
TOOLS = CACHE / "Tools"
LICENSES = CACHE / "Licenses"
TOOLS.mkdir(exist_ok=True)
LICENSES.mkdir(exist_ok=True)

ASSETS = [
    ("yt-dlp_macos", "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos",
     "0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202"),
    ("deno-arm64.zip", "https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip",
     "5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c"),
    ("deno-x86_64.zip", "https://github.com/denoland/deno/releases/download/v2.9.7/deno-x86_64-apple-darwin.zip",
     "95daaff11c116a52ad54785e7914c8e9c9cdcaba793c5ed929c74ca2d8e6259a"),
]


def download(asset):
    name, url, expected = asset
    target = CACHE / name
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
        print(f"Downloading {name}…", flush=True)
        command = ["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
                   "--retry", "3", "--connect-timeout", "20", "--speed-time", "60",
                   "--speed-limit", "1024", "--max-time", "600", "--output", str(target)]
        completed = subprocess.run(command + ["--continue-at", "-", url])
        if completed.returncode != 0:
            # Some mirrors do not support range requests; retry a fresh download.
            subprocess.run(command + [url], check=True)
    actual = hashlib.sha256(target.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError(f"Checksum mismatch for {name}: {actual}")
    return target


with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    archives = list(pool.map(download, ASSETS))

(TOOLS / "yt-dlp").write_bytes(archives[0].read_bytes())
for architecture, archive in zip(["arm64", "x86_64"], archives[1:]):
    directory = CACHE / architecture
    directory.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        # Extract only the expected executable, never arbitrary archive paths.
        (directory / "deno").write_bytes(source.read("deno"))
    (directory / "deno").chmod(0o755)
subprocess.run(["/usr/bin/lipo", "-create", str(CACHE / "arm64/deno"),
                str(CACHE / "x86_64/deno"), "-output", str(TOOLS / "deno")], check=True)
for tool in TOOLS.iterdir():
    tool.chmod(0o755)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(tool)], check=True)

notices = {
    "yt-dlp-LICENSE.txt": "https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.08.19/LICENSE",
    "yt-dlp-THIRD_PARTY_LICENSES.txt": "https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.08.19/THIRD_PARTY_LICENSES.txt",
    "deno-LICENSE.txt": "https://raw.githubusercontent.com/denoland/deno/v2.9.7/LICENSE.md",
}
for name, url in notices.items():
    target = LICENSES / name
    if not target.exists():
        subprocess.run(["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
                        "--retry", "3", "--connect-timeout", "20", "--max-time", "60",
                        "--output", str(target), url], check=True)

# The upstream notice file already contains the verbatim GPLv3 license text.
license_catalog = (LICENSES / "yt-dlp-THIRD_PARTY_LICENSES.txt").read_text()
gpl_start = license_catalog.index("                    GNU GENERAL PUBLIC LICENSE")
gpl_end = re.search(r"\n-{40,}\n", license_catalog[gpl_start:])
(LICENSES / "GPL-3.0.txt").write_text(
    license_catalog[gpl_start:gpl_start + gpl_end.start()] if gpl_end else license_catalog[gpl_start:]
)

(LICENSES / "THIRD-PARTY-NOTICES.txt").write_text(
    "Shadowing Player uses independently executed upstream tools.\n\n"
    "yt-dlp 2026.08.19: https://github.com/yt-dlp/yt-dlp/tree/2026.08.19\n"
    "Official macOS PyInstaller release includes Python and third-party packages.\n"
    "Its combined binary is distributed by upstream under GPLv3+. See the included\n"
    "yt-dlp license, third-party license list, and GPL text for component terms.\n"
    "Release and corresponding source: https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19\n\n"
    "Deno 2.9.7: https://github.com/denoland/deno/tree/v2.9.7\n"
    "Upstream MIT license is included. Dependency licensing and source are documented upstream.\n"
    "Release and source: https://github.com/denoland/deno/releases/tag/v2.9.7\n\n"
    "These tools are not dynamically linked into the Swift application.\n"
    "FFmpeg is not included or needed: AVFoundation handles media merging and playback.\n",
    encoding="utf-8",
)
(CACHE / "tool-manifest.json").write_text(json.dumps([
    {"file": name, "url": url, "sha256": digest} for name, url, digest in ASSETS
], indent=2) + "\n")
print(f"Verified universal tools ready: {TOOLS}")
