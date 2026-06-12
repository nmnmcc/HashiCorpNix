#!/usr/bin/env python3
"""Scan releases.hashicorp.com and update versions.json with all product versions and SRI hashes."""

import base64
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import Request, urlopen

PLATFORMS = ("linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64")
RELEASES_URL = "https://releases.hashicorp.com/index.json"
WORKERS = 16

ROOT = Path(__file__).parent
VERSIONS_FILE = ROOT / "versions.json"

_STABLE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def fetch(url):
    try:
        req = Request(url, headers={"User-Agent": "hashicorp-nix-updater"})
        with urlopen(req, timeout=30) as r:
            return r.read().decode()
    except Exception:
        return None


def hex_to_sri(hex_hash):
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_hash)).decode()


def version_tuple(v):
    return tuple(int(x) for x in v.split("."))


def eligible_versions(product_data):
    """Return stable versions that ship zip builds for at least one target platform."""
    result = []
    for ver, info in (product_data.get("versions") or {}).items():
        if not _STABLE.fullmatch(ver):
            continue
        if any(
            b.get("filename", "").endswith(".zip")
            and b.get("os") in ("linux", "darwin")
            and b.get("arch") in ("amd64", "arm64")
            for b in (info.get("builds") or [])
        ):
            result.append(ver)
    return result


def fetch_shas(product, version):
    url = (
        f"https://releases.hashicorp.com/{product}/{version}"
        f"/{product}_{version}_SHA256SUMS"
    )
    body = fetch(url)
    if body is None:
        return None

    shas = {}
    for platform in PLATFORMS:
        target = f"{product}_{version}_{platform}.zip"
        for line in body.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1].lstrip("*") == target:
                shas[platform] = hex_to_sri(parts[0])
                break
    return shas or None


def load_existing():
    if VERSIONS_FILE.exists():
        try:
            data = json.loads(VERSIONS_FILE.read_text())
            if isinstance(data, dict):
                return data
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def main():
    existing = load_existing()
    existing_set = {
        (p, v)
        for p, info in existing.items()
        for v in (info.get("versions") or {})
    }

    print("Fetching releases.hashicorp.com/index.json ...")
    raw = fetch(RELEASES_URL)
    if raw is None:
        print("Failed to fetch index.json", file=sys.stderr)
        sys.exit(1)
    index = json.loads(raw)

    print("Resolving versions ...")
    all_pairs = []
    for product, product_data in index.items():
        if not isinstance(product_data, dict) or "versions" not in product_data:
            continue
        for ver in eligible_versions(product_data):
            all_pairs.append((product, ver))

    new_pairs = [(p, v) for p, v in all_pairs if (p, v) not in existing_set]
    print(f"Total: {len(all_pairs)} versions, {len(new_pairs)} new")

    if not new_pairs:
        print("--- up to date ---")
        return

    print(f"Fetching checksums ({len(new_pairs)} versions, {WORKERS} workers) ...")
    results = {}
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {
            pool.submit(fetch_shas, p, v): (p, v) for p, v in new_pairs
        }
        done = 0
        for future in as_completed(futures):
            done += 1
            p, v = futures[future]
            try:
                shas = future.result()
            except Exception:
                shas = None
            if shas:
                results[(p, v)] = shas
            if done % 200 == 0 or done == len(new_pairs):
                print(f"  {done}/{len(new_pairs)}")

    print(f"Fetched: {len(results)}")

    # Deep-copy existing and merge
    data = {}
    for p, info in existing.items():
        data[p] = {
            "latest": info.get("latest"),
            "versions": dict(info.get("versions") or {}),
        }

    for (p, v), shas in results.items():
        if p not in data:
            data[p] = {"latest": None, "versions": {}}
        data[p]["versions"][v] = shas

    # Recompute latest per product
    for info in data.values():
        vers = list(info["versions"])
        info["latest"] = max(vers, key=version_tuple) if vers else None

    VERSIONS_FILE.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")

    total_ver = sum(len(info["versions"]) for info in data.values())
    print(f"--- done: {len(data)} products, {total_ver} versions ---")


if __name__ == "__main__":
    main()
