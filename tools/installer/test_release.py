import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import release


class InstallerReleaseTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.root = Path(work.name)
        (self.root / "version").write_text("5.0.0\n")
        self.engine = self.root / "rust/apps/nexbot-engine/Cargo.toml"
        self.engine.parent.mkdir(parents=True)
        self.engine.write_text('[package]\nversion = "5.0.0"\n')
        root = patch.object(release, "ROOT", self.root)
        root.start()
        self.addCleanup(root.stop)
        for _, suffix, extension, _ in release.TARGETS.values():
            (self.root / f"nexbot-installer-{suffix}{extension}").write_bytes(b"installer")

    def test_manifest_contains_every_target_with_size_and_digest(self):
        manifest = release.release_manifest(self.root, "v5.0.0", "a" * 40)
        self.assertEqual(manifest["engineVersion"], "5.0.0")
        self.assertEqual(len(manifest["assets"]), 4)
        self.assertIn({
            "name": "nexbot-installer-windows-x64.exe",
            "bytes": 9,
            "sha256": hashlib.sha256(b"installer").hexdigest(),
        }, manifest["assets"])

    def test_manifest_rejects_a_preview_engine(self):
        self.engine.write_text('[package]\nversion = "5.0.0-alpha.1"\n')
        with self.assertRaisesRegex(ValueError, "engine version"):
            release.release_manifest(self.root, "v5.0.0", "a" * 40)

    def test_manifest_rejects_an_incomplete_matrix(self):
        (self.root / "nexbot-installer-linux-x64.zip").unlink()
        with self.assertRaises(FileNotFoundError):
            release.release_manifest(self.root, "v5.0.0", "a" * 40)
