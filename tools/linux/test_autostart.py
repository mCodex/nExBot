import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

INSTALL = Path(__file__).with_name("install-autostart.py")


class AutostartTest(unittest.TestCase):
    def test_install_then_reinstall_into_a_user_home_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix="nexbot home ") as temporary:
            home = Path(temporary)
            # Record calls without modifying the test user's real systemd manager.
            mock = home / "systemctl"
            mock.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/calls"\n')
            mock.chmod(0o700)
            env = dict(os.environ, HOME=str(home), PATH=str(home) + os.pathsep + os.environ["PATH"],
                       XDG_CONFIG_HOME=str(home / "configuration"))
            engine = home / "engine"
            engine.write_text("#!/bin/sh\necho nexbot-engine 5\n")
            engine.chmod(0o700)
            for suffix in ("one", "two"):
                profile = home / ("bot profile " + suffix)
                profile.mkdir()
                subprocess.run([sys.executable, INSTALL, engine, profile], env=env, check=True)
                service = home / ".local/share/nexbot/service"
                self.assertEqual(profile.resolve(), (service / "profile").resolve())
                self.assertEqual(engine.read_bytes(), (service / "nexbot-engine").read_bytes())
                self.assertTrue(os.access(service / "nexbot-engine", os.X_OK))
                unit = (home / "configuration/systemd/user/nexbot-engine.service").read_text()
                self.assertIn(" serve %h/.local/share/nexbot/service/profile", unit)
                self.assertIn("WantedBy=default.target", unit)
                self.assertIn("Restart=on-failure", unit)
            self.assertEqual(2, (home / "calls").read_text().count("--user restart nexbot-engine.service"))


if __name__ == "__main__":
    unittest.main()
