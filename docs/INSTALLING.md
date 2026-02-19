# Installing nExBot

Get nExBot up and running on your OTClient in minutes.

---

## Requirements

- **OTClient** — either [OTClientV8](https://github.com/otcv8/otcv8-dev) or [OpenTibiaBR's OTCR](https://github.com/mehah/otclient)
- A running Open Tibia server to connect to
- The latest nExBot release (download from [GitHub](https://github.com/nicao-bot/nExBot) or the Discord server)

---

## Installation on vBot (OTClientV8)

### 1. Locate your bot folder

The default data directory is:

```
Windows:  %APPDATA%\OTClientV8\<ServerName>\bot\
Linux:    ~/.local/share/OTClientV8/<ServerName>/bot/
```

Replace `<ServerName>` with the name of the server you play on (e.g. `Tibia Realms RPG`).

> **Tip:** You can find the exact path by opening OTClientV8, pressing `Ctrl+B`, and noting the directory shown at the top of the Bot panel.

### 2. Copy nExBot

Copy the entire `nExBot` folder into the `bot/` directory so the structure looks like:

```
bot/
└── nExBot/
    ├── _Loader.lua
    ├── core/
    ├── cavebot/
    ├── targetbot/
    └── ...
```

### 3. Enable the bot

1. Open OTClientV8 and log in to your server.
2. Press **Ctrl+B** to open the Bot panel.
3. In the bot dropdown, select **nExBot**.
4. Click **Enable**.

You should see the Main, Cave, and Target tabs appear.

---

## Installation on OpenTibiaBR (OTCR)

### 1. Locate your bot folder

On OTCR the data path is usually:

```
Windows:  %APPDATA%\otclientrc\<ServerName>\bot\
Linux:    ~/.local/share/<otcr-data-dir>/<ServerName>/bot/
```

> The exact folder name varies depending on how the server distributes OTCR. Look for a `.otcr` or similar hidden folder under your data directory. On some distributions the path is `~/.local/share/otcr-<servername>/`.

### 2. Copy nExBot

Same as above — copy the `nExBot` folder into `bot/`:

```
bot/
└── nExBot/
    ├── _Loader.lua
    ├── core/
    ├── cavebot/
    ├── targetbot/
    └── ...
```

### 3. Enable the bot

1. Open OTCR and log in.
2. Press **Ctrl+B** to open Bot Settings.
3. Select **nExBot** from the list.
4. Click **Enable**.

---

## Verifying the Installation

After enabling, you should see:

- A startup message in the console: `[nExBot vX.X.X] Loaded in XXms`
- The **Main** tab with HealBot, AttackBot, Extras, and other panels
- The **Cave** tab with CaveBot controls
- The **Target** tab with TargetBot controls

If you see errors in the console, check the [FAQ](FAQ.md) troubleshooting section.

---

## Client Auto-Detection

nExBot automatically detects which client you are running — vBot or OTCR — through its **Anti-Corruption Layer (ACL)**. No manual configuration is needed.

The ACL detects the client by:
- Checking for OTCR-exclusive module files (e.g. `game_cyclopedia`, `game_forge`)
- Probing for OTCR-exclusive APIs like `g_game.forceWalk()`
- Falling back to OTClientV8 detection via `g_game.moveRaw()`

Once detected, nExBot loads the appropriate adapter so that all features — including OTCR-exclusive ones like imbuing, stash, and forge — work automatically.

---

## Updating nExBot

1. **Back up your configs** — copy the `cavebot_configs/`, `targetbot_configs/`, and `nExBot_configs/` folders somewhere safe.
2. Delete the old `nExBot/` folder.
3. Copy the new release into the same `bot/` directory.
4. Restore your config folders.
5. Reload the bot in-client.

Your per-character profiles are stored in `storage/` and will persist across updates as long as you keep that folder.

---

## Folder Structure

After installation, the full directory tree looks like:

```
nExBot/
├── _Loader.lua              # Entry point — loads everything
├── version                  # Current version number
├── core/                    # Core modules (HealBot, AttackBot, EventBus, etc.)
│   ├── acl/                 # Anti-Corruption Layer (client abstraction)
│   └── bot_core/            # Internal bot framework
├── cavebot/                 # CaveBot navigation engine
├── targetbot/               # TargetBot combat AI
├── constants/               # Lookup tables (food, floor items, etc.)
├── utils/                   # Shared utility functions
├── cavebot_configs/         # Saved CaveBot waypoint routes (.cfg)
├── targetbot_configs/       # Saved TargetBot creature configs (.json)
├── nExBot_configs/          # Saved bot profiles
├── storage/                 # Per-character persistent data
└── docs/                    # This documentation
```

---

## Next Steps

Once nExBot is running:

1. **[Set up HealBot](HEALBOT.md)** — this is the most important module for survival.
2. **[Configure TargetBot](TARGETBOT.md)** — add the monsters you want to fight.
3. **[Create CaveBot waypoints](CAVEBOT.md)** — automate your hunting route.
4. **[Configure AttackBot](ATTACKBOT.md)** — set up your offensive spell rotation.
