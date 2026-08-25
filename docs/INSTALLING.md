# Installing

## Requirements

- OTClient (vBot or OTCR)
- Open Tibia server to connect to
- Latest nExBot release

## vBot (OTClientV8)

1. Find bot folder: `%APPDATA%/OTClientV8/<ServerName>/bot/`
2. Copy `nExBot/` into `bot/`
3. Open client → **Ctrl+B** → select nExBot → **Enable**

## OTCR (OpenTibiaBR)

1. Find bot folder: `~/.local/share/<otcr-data>/<ServerName>/bot/`
2. Copy `nExBot/` into `bot/`
3. Open client → **Ctrl+B** → select nExBot → **Enable**

> Exact OTCR path varies by distribution. Look for `.otcr` or similar hidden folder.

## Verify

Startup message in console: `[nExBot vX.X.X] Loaded in XXms`. The nExBot cockpit is visible in the bot panel.

## Auto-Detection

ACL detects vBot vs OTCR automatically. No manual configuration.

## Updating

1. Back up `cavebot_configs/`, `targetbot_configs/`, `nExBot_configs/`
2. Delete old `nExBot/`
3. Copy new release
4. Restore config folders

Per-character profiles in `storage/` persist across updates.

## Auto-Updater & Mod Folders

**Auto-updater does NOT work inside `mods/` or custom mod directories.** Lua sandbox can only write to user-data paths. Mod folders are read-only.

Correct setup:
```
<user-data>/
├── bot/nExBot/       ← updater works
└── mods/nExBot/      ← updater CANNOT write
```

## Folder Structure

```
nExBot/
├── _Loader.lua           # Entry point
├── version               # Version number
├── core/                 # HealBot, AttackBot, EventBus, etc.
│   ├── acl/              # Client abstraction
│   └── bot_core/         # Internal framework
├── cavebot/              # Navigation engine
├── targetbot/            # Combat AI
├── constants/            # Lookup tables
├── utils/                # Shared utilities
├── cavebot_configs/      # Saved routes (.cfg)
├── targetbot_configs/    # Saved creature configs (.json)
├── nExBot_configs/       # Saved profiles
├── storage/              # Per-character data
└── docs/                 # Documentation
```
