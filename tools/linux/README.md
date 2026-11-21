# Linux login startup

From a graphical login with a systemd user manager, run the installer once as the OTClient user. Supply the verified Linux binary for the host architecture and the installed bot profile directory containing `_Loader.lua`.

```sh
python3 tools/linux/install-autostart.py /path/to/nexbot-engine "/path/to/bot/nExBot"
systemctl --user is-enabled nexbot-engine.service
systemctl --user is-active nexbot-engine.service
journalctl --user -u nexbot-engine.service -n 20
```

The installer copies the executable into the user's home directory, starts it immediately and enables it at login. Repeat the command to install a newer verified build or switch to another profile. The process handles game relogs. The OTClient console reports `connected and authenticated` after the bridge connects.

To remove automatic startup and its installed files, run:

```sh
systemctl --user disable --now nexbot-engine.service
rm -- "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/nexbot-engine.service"
systemctl --user daemon-reload
rm -- "$HOME/.local/share/nexbot/service/nexbot-engine" "$HOME/.local/share/nexbot/service/profile"
rmdir "$HOME/.local/share/nexbot/service"
```
