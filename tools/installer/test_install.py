from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from install import detect_bot_folders, install_profile, installer_lock


class InstallerTests(unittest.TestCase):
    def setUp(self):
        folder = TemporaryDirectory()
        self.addCleanup(folder.cleanup)

        self.root = Path(folder.name)
        self.source = self.root / "package" / "nExBot"
        self.source.mkdir(parents=True)
        (self.source / "_Loader.lua").write_text("new", encoding="utf-8")

        self.bot = self.root / "otcr-trpgb" / ".otcr-trpgb" / "bot"
        self.bot.mkdir(parents=True)

    def test_detects_otcr_and_vbot_folders(self):
        vbot = self.root / "OTClientV8" / "Server" / "bot"
        vbot.mkdir(parents=True)
        (self.root / "OtherApp" / "bot").mkdir(parents=True)

        self.assertCountEqual(detect_bot_folders([self.root]), [self.bot.resolve(), vbot.resolve()])

    def test_installs_without_creating_a_backup_for_new_profile(self):
        profile, backup = install_profile(self.source, self.bot)

        self.assertEqual(profile, self.bot / "nExBot")
        self.assertIsNone(backup)
        self.assertEqual((profile / "_Loader.lua").read_text(encoding="utf-8"), "new")

    def test_backups_old_code_and_copies_player_data(self):
        profile = self.bot / "nExBot"
        routes = profile / "cavebot_configs"
        routes.mkdir(parents=True)
        (routes / "route.cfg").write_text("waypoint", encoding="utf-8")
        (profile / "_Loader.lua").write_text("old", encoding="utf-8")

        updated, backup = install_profile(self.source, self.bot)

        self.assertEqual((updated / "_Loader.lua").read_text(encoding="utf-8"), "new")
        self.assertEqual((updated / "cavebot_configs/route.cfg").read_text(encoding="utf-8"), "waypoint")
        self.assertEqual((backup / "_Loader.lua").read_text(encoding="utf-8"), "old")
        self.assertNotIn(self.bot, backup.parents)

    def test_restores_old_profile_when_staged_rename_fails(self):
        profile = self.bot / "nExBot"
        profile.mkdir()
        (profile / "_Loader.lua").write_text("old", encoding="utf-8")
        rename = Path.rename

        def fail_staged_rename(path, target):
            if path.parent.name.startswith(".nexbot-install-"):
                raise OSError("simulated move failure")
            return rename(path, target)

        with patch.object(Path, "rename", fail_staged_rename):
            with self.assertRaisesRegex(OSError, "simulated move failure"):
                install_profile(self.source, self.bot)

        self.assertEqual((profile / "_Loader.lua").read_text(encoding="utf-8"), "old")

    def test_lock_excludes_another_install_and_releases_after_failure(self):
        lock = self.root / ".nexbot-install.lock"
        with self.assertRaisesRegex(ValueError, "installation failed"):
            with installer_lock(lock):
                with self.assertRaisesRegex(RuntimeError, "Another installer"):
                    with installer_lock(lock):
                        self.fail("another installer acquired the lock")
                raise ValueError("installation failed")

        with installer_lock(lock):
            pass

    def test_keeps_unknown_directory_untouched(self):
        profile = self.bot / "nExBot"
        profile.mkdir()
        unrelated = profile / "user-file"
        unrelated.touch()

        with self.assertRaises(ValueError):
            install_profile(self.source, self.bot)

        self.assertTrue(unrelated.is_file())


if __name__ == "__main__":
    unittest.main()
