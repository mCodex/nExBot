# Start the engine at Windows sign-in

Place the verified Windows release executable in a permanent directory writable only by your Windows account and administrators. Open Windows PowerShell as the same user who plays the game. From the nExBot profile directory, run the installer once, adjusting the engine path to its installed location.

```powershell
.\tools\windows\autostart.ps1 -Engine "$env:LOCALAPPDATA\nExBot\nexbot-engine.exe" -ProfileDir .
```

The installer starts the engine immediately and registers it with Task Scheduler for subsequent sign-ins. The task runs with the player's interactive token and accepts one profile directory per Windows user. Repeating the command updates the task. Task Scheduler retries a crashed engine up to five times at one-minute intervals.

To verify, check the task state, then log into the game and look for `connected and authenticated` in the bot console. Repeat the game login to exercise reconnection.

```powershell
$task = "nExBot Engine - $([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)"
Get-ScheduledTask -TaskPath '\' -TaskName $task | Select-Object TaskName, State
```

To stop the engine and remove automatic startup for this user, run:

```powershell
.\tools\windows\autostart.ps1 -Uninstall
```
