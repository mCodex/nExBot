# Desktop installer

Run the **Desktop installers** workflow from the release revision. The build compiles the Rust engine with the checked-in Cargo lockfile and bundles the Lua profile from that same Git revision. Each package runs its bundled engine with `--version` as a smoke check. The installer is offline once downloaded.

The web download selects the newest compatible published release and its matching asset.

| Platform | Public release asset |
| --- | --- |
| Windows x64 | `nexbot-installer-windows-x64.exe` |
| macOS Apple silicon | `nexbot-installer-macos-arm64.zip` |
| macOS Intel | `nexbot-installer-macos-x64.zip` |
| Linux x64 | `nexbot-installer-linux-x64.zip` |

Release assets require native verification before publication. Sign the Windows executable. Sign and notarize the Mac application and recreate its ZIP with `ditto`. On Linux, check ZIP extraction preserves the executable permission and the engine starts under the user's systemd manager. Windows uses a current user's Scheduled Task and macOS uses a per-user LaunchAgent.

Test with the client closed during installation. Verify automatic startup after signing in again, the OTClient connection after a game relog, and preservation of settings and routes during a reinstall. Test selecting a custom client folder and retrying after a failed installation. The installer keeps the previous profile in `.nexbot-backups` beside the client’s `bot` folder and copies its usual settings and routes into the new profile. If startup setup fails, the installed profile and backup are available for a retry.

For local changes, run `python -m unittest discover -s tools/installer`. Build with `python tools/installer/package.py TARGET` on the matching OS after installing PyInstaller 6.16.0 and a Python interpreter with Tk support.
