"""Build and publish the complete desktop installer set for the checked-out tag."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tomllib

from package import ROOT, TARGETS


MANIFEST = "nexbot-installers.json"


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def check_version(tag):
    if not re.fullmatch(r"v5\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag):
        raise ValueError("Expected a stable v5 tag.")
    if (ROOT / "version").read_text().strip() != tag[1:]:
        raise ValueError("The profile version must match the release tag.")

    engine = ROOT / "rust/apps/nexbot-engine/Cargo.toml"
    engine_version = tomllib.loads(engine.read_text())["package"]["version"]
    if engine_version != tag[1:]:
        raise ValueError("The bundled engine version must match the stable release tag.")
    return engine_version


def release_manifest(directory, tag, commit):
    engine_version = check_version(tag)
    assets = []
    for _, suffix, extension, _ in TARGETS.values():
        path = directory / f"nexbot-installer-{suffix}{extension}"
        size = path.stat().st_size
        if not size:
            raise ValueError(f"Empty installer: {path.name}")
        with path.open("rb") as asset:
            digest = hashlib.file_digest(asset, "sha256").hexdigest()
        assets.append({"name": path.name, "bytes": size, "sha256": digest})
    return {
        "schema": 1,
        "tag": tag,
        "engineVersion": engine_version,
        "engineCommit": commit,
        "assets": assets,
    }


def publish(directory, manifest, repository):
    tag = manifest["tag"]
    paths = [directory / asset["name"] for asset in manifest["assets"]]
    paths.append(directory / MANIFEST)
    expected = {
        asset["name"]: (asset["bytes"], f'sha256:{asset["sha256"]}')
        for asset in manifest["assets"]
    }
    path = directory / MANIFEST
    expected[MANIFEST] = (path.stat().st_size, f"sha256:{hashlib.sha256(path.read_bytes()).hexdigest()}")

    def get_release():
        releases = run("gh", "api", "--paginate", "--slurp", f"repos/{repository}/releases")
        return next((release for page in json.loads(releases) for release in page if release["tag_name"] == tag), None)

    def published_assets(release):
        endpoint = f'repos/{repository}/releases/{release["id"]}/assets'
        pages = json.loads(run("gh", "api", "--paginate", "--slurp", endpoint))
        return {
            item["name"]: (item["size"], item["digest"])
            for page in pages for item in page if item["state"] == "uploaded"
        }

    release = get_release()
    if release is None:
        run("gh", "release", "create", tag, "--repo", repository, "--verify-tag", "--draft", "--generate-notes")
        release = get_release()
    if release is None or release["prerelease"]:
        raise ValueError("Expected a stable release draft.")

    actual = published_assets(release)
    for name, signature in actual.items():
        if name in expected and signature != expected[name]:
            raise ValueError(f"Release already contains different bytes for {name}.")
    if release["draft"]:
        missing = [str(path) for path in paths if path.name not in actual]
        if missing:
            run("gh", "release", "upload", tag, "--repo", repository, *missing)
        actual = published_assets(release)
    if any(actual.get(name) != signature for name, signature in expected.items()):
        raise ValueError("The release does not contain the complete verified installer set.")
    if release["draft"]:
        run("gh", "release", "edit", tag, "--repo", repository, "--draft=false")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check-version", "manifest", "publish"))
    parser.add_argument("directory", type=Path, nargs="?")
    args = parser.parse_args()
    tag = os.environ["GITHUB_REF_NAME"]
    if args.command == "check-version":
        check_version(tag)
        raise SystemExit(0)
    if args.directory is None:
        parser.error("installer directory is required")
    directory = args.directory.resolve()
    manifest = release_manifest(directory, tag, run("git", "rev-parse", "HEAD"))
    encoded = json.dumps(manifest, indent=2) + "\n"
    if args.command == "manifest":
        (directory / MANIFEST).write_text(encoded, encoding="utf-8")
    else:
        if (directory / MANIFEST).read_text(encoding="utf-8") != encoded:
            raise ValueError("The attested installer manifest has changed.")
        publish(directory, manifest, os.environ["GITHUB_REPOSITORY"])
