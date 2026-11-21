#!/usr/bin/env python3
"""Install the Rust engine in the current user's systemd manager."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

UNIT = "nexbot-engine.service"


def systemctl(*args):
    subprocess.run(["systemctl", "--user", *args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path, help="verified Linux nexbot-engine binary")
    parser.add_argument("profile", type=Path, help="installed nExBot profile directory")
    args = parser.parse_args()
    profile = args.profile.resolve(strict=True)
    if not profile.is_dir():
        parser.error("the profile must be a directory")
    engine = args.engine.resolve(strict=True)
    version = subprocess.check_output([engine, "--version"], text=True, timeout=10)
    if not version.startswith("nexbot-engine "):
        parser.error("expected a nexbot-engine executable")
    systemctl("show", "--property=Version")
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    if not config.is_absolute():
        config = home / ".config"
    unit_dir = config / "systemd/user"
    service = home / ".local/share/nexbot/service"
    service.mkdir(parents=True, exist_ok=True, mode=0o700)
    unit_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=service) as temp:
        staged = Path(temp)
        executable = staged / "nexbot-engine"
        shutil.copyfile(engine, executable)
        executable.chmod(0o700)
        (staged / "profile").symlink_to(profile, target_is_directory=True)
        executable.replace(service / executable.name)
        (staged / "profile").replace(service / "profile")
    with tempfile.TemporaryDirectory(dir=unit_dir) as temp:
        unit = Path(temp) / UNIT
        shutil.copyfile(Path(__file__).with_name(UNIT), unit)
        unit.replace(unit_dir / UNIT)
    systemctl("daemon-reload")
    systemctl("enable", UNIT)
    systemctl("restart", UNIT)
    systemctl("is-active", "--quiet", UNIT)
    print("Automatic startup enabled for", profile)


if __name__ == "__main__":
    main()
