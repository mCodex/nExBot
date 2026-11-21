# macOS login agent

Run the installer once from your macOS desktop account. Supply the verified engine for your Mac and the directory that contains the bot's `_Loader.lua`.

```sh
./tools/macos/install-autostart.sh /path/to/nexbot-engine "/path/to/bot/nExBot"
```

The installer copies the engine into your Library and starts a per-user LaunchAgent. The agent runs at login and relaunches the engine after it exits. The engine accepts successive OTClient sessions on loopback. Re-run the installer with a verified replacement binary to update it.

Check the agent with `launchctl print "gui/$(id -u)/cc.nexbot.engine"`. The client console reports `connected and authenticated` after the bridge connects.

To uninstall, unload the agent and remove its installed files. Game profiles and waypoints stay in the client's bot directory.

```sh
launchctl bootout "gui/$(id -u)/cc.nexbot.engine"
rm -f "$HOME/Library/LaunchAgents/cc.nexbot.engine.plist"
rm -f "$HOME/Library/Application Support/nExBot/nexbot-engine"
```
