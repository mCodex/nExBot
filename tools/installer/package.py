"""Build the graphical installer from an engine and profile at the same revision."""

import argparse
from io import BytesIO
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
PROFILE_FILES = ("_Loader.lua", "version", "bridge", "cavebot", "constants", "core", "targetbot", "utils")
TARGETS = {
    "x86_64-pc-windows-msvc": ("Windows", "windows-x64", ".exe", ("tools/windows/autostart.ps1",)),
    "aarch64-apple-darwin": ("Darwin", "macos-arm64", ".zip", ("tools/macos/install-autostart.sh",)),
    "x86_64-apple-darwin": ("Darwin", "macos-x64", ".zip", ("tools/macos/install-autostart.sh",)),
    "x86_64-unknown-linux-gnu": (
        "Linux", "linux-x64", ".zip",
        ("tools/linux/install-autostart.py", "tools/linux/nexbot-engine.service"),
    ),
}


def package(target, output):
    system, suffix, extension, startup_files = TARGETS[target]
    if platform.system() != system:
        raise ValueError("Build each installer on its target operating system.")
    script = ROOT / "tools/installer/install.py"
    changes = subprocess.check_output(
        ["git", "status", "--porcelain", "--", "rust"], cwd=ROOT, text=True,
    )
    if changes.strip():
        raise ValueError("Build the engine from a clean release revision.")
    executable = "nexbot-engine.exe" if system == "Windows" else "nexbot-engine"
    engine = ROOT / "rust/target" / target / "release" / executable
    subprocess.run(
        ["cargo", "build", "--locked", "--release", "-p", "nexbot-engine", "--target", target],
        cwd=ROOT / "rust",
        check=True,
    )
    output.mkdir(parents=True, exist_ok=True)
    asset = output / f"nexbot-installer-{suffix}{extension}"

    with tempfile.TemporaryDirectory(prefix="nexbot-installer-") as temporary:
        workspace = Path(temporary)
        payload = workspace / "payload"
        profile = payload / "nExBot"
        profile.mkdir(parents=True)

        # Read only release sources; the working profile may contain character data.
        archive = subprocess.check_output(
            ["git", "archive", "HEAD", *PROFILE_FILES, *startup_files], cwd=ROOT,
        )
        with tarfile.open(fileobj=BytesIO(archive)) as sources:
            sources.extractall(profile, filter="data")
        name = "nExBot Installer"
        command = [
            sys.executable, "-m", "PyInstaller", "--noconfirm", "--name", name,
            "--add-data", f"{payload}:payload", "--add-binary", f"{engine}:payload",
            "--distpath", str(workspace / "dist"),
        ]
        if system == "Darwin":
            command.extend(["--windowed", "--target-arch", target.split("-")[0].replace("aarch64", "arm64")])
        else:
            command.append("--onefile")
            if system == "Windows":
                command.append("--windowed")
            else:
                # The bundled systemd script imports argparse through runpy.
                command.extend(["--hidden-import", "argparse"])
        subprocess.run([*command, str(script)], cwd=workspace, check=True)

        dist = workspace / "dist"
        if system == "Darwin":
            app = dist / f"{name}.app"
            subprocess.run([app / "Contents/MacOS" / name, "--verify-package"], check=True)
            subprocess.run(["ditto", "-c", "-k", "--keepParent", app, asset], check=True)
        elif system == "Windows":
            program = dist / f"{name}.exe"
            subprocess.run([program, "--verify-package"], check=True)
            shutil.copy2(program, asset)
        else:
            program = dist / name
            subprocess.run([program, "--verify-package"], check=True)
            with zipfile.ZipFile(asset, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.write(program, "nexbot-installer")

    print(asset)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/installer")
    args = parser.parse_args()
    package(args.target, args.output.resolve())
