# 📦 Containers

Automated container management, auto-opening, and quiver handling.

---

## 📖 Overview

The Containers module manages your backpacks and their contents automatically. It opens containers on login, organizes items between backpacks, and handles quiver ammunition for paladins.

Key capabilities:

- Auto-open containers on login
- Nested container traversal (BFS)
- Quiver auto-refill for paladins
- Container role assignments (loot, supplies, runes)
- Pagination support for large containers
- Deduplication to prevent opening a container twice

---

## 🚀 Quick Start

1. Open the **Containers** panel from the Main tab.
2. Assign roles to your container slots:
   - Slot 0: Main Backpack
   - Slot 1: Loot Container
   - Slot 2: Supplies
   - Slot 3: Runes
3. Enable **Auto Open on Login**.

---

## 🏷️ Container Roles

### Main Backpack

Your primary container that holds all other backpacks. It should be a large-capacity bag (e.g., a Golden Backpack or an Adventurer's Bag).

### Loot Container

Where monster drops go during hunting. Use a large container (e.g. Beach Bag with 36 slots) to maximize hunting time between depot visits.

### Supplies Container

Holds your potions, food, and other consumables. HealBot and the food system search this container for items.

### Runes Container

Holds your attack and utility runes. AttackBot pulls runes from here during combat.

---

## 🔓 Auto-Open System

The Container Panel uses a BFS queue system with re-scan on timeout:

1. On login, it waits for containers to load (500 ms delay)
2. Opens assigned containers
3. Scans for nested containers and queues them for opening
4. Handles paginated containers automatically
5. Re-scans parent containers on safety timeout (fixes late-opening backpacks)
6. Skips monster corpses during sorting (dead, remains, body of)
7. Enforces server-side container limit (max 19 open) to prevent server rejection
8. Emits `containers:open_all_complete` via EventBus when done

### Architecture

| Component | Responsibility |
|-----------|----------------|
| **ContainerBFS** | BFS queue with O(1) pop (index cursor instead of table.remove) |
| **ContainerTracker** | Prevents duplicate opens (4-second grace period) |
| **ContainerScanner** | Scans containers for nested containers |
| **getCachedContainers()** | Per-tick cache — eliminates redundant g_game.getContainers() calls |

### Deduplication

The queue uses slot-based keys (`containerId:absoluteSlotIndex`) for robust deduplication. The `ContainerTracker` prevents re-opening the same slot within a 4-second grace period, even if events fire multiple times.

### Safety Timeout

When a container entry is pending for too long, the safety timeout rescans the parent container before dropping the entry. This fixes backpacks that stay unopened when the child container opens before the parent.

### Corpse Filtering

The sorting system automatically skips monster corpses (identified by names containing "dead", "remains", or "body of") — these are looted by TargetBot, not sorted by the Container Panel.

---

## 🏹 Quiver Management

For Paladins, the quiver system handles ammunition automatically:

- Monitors equipped ammunition count
- Detects when the quiver is running low
- Refills from supplies container
- Works with all arrow and bolt types

### Supported Ammunition

| Type | Examples |
|------|----------|
| **Arrows** | Arrows, Crystalline Arrows, Diamond Arrows, Spectral Arrows |
| **Bolts** | Bolts, Power Bolts, Infernal Bolts, Prismatic Bolts, Spectral Bolts |

Quiver management is enabled by default — no toggle needed.

---

## ⚙️ Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| **Auto Open** | Open containers on login | OFF |
| **Auto Stack** | Stack identical items | ON |
| **Sort Containers** | Organize item positions | OFF |
| **Close Empty** | Close empty containers | OFF |
| **Auto Minimize** | Minimize opened containers | Configurable |
| **Rename** | Rename containers with labels | Configurable |

---

## 📐 Setup Examples

### Knight

```text
Main BP: Golden Backpack
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
└── Runes: Blue Backpack (SD / Magic Wall)
```

### Paladin

```text
Main BP: Adventurer's Bag
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
├── Ammo: Grey Backpack (arrow reserve)
└── Quiver: Auto-managed
```

### Mage

```text
Main BP: Jewelled Backpack
├── Supplies: Beach Bag (mana potions)
├── Loot: Beach Bag (drops)
└── Runes: Blue Backpack (attack runes)
```

---

## 🔗 EventBus Integration

```lua
-- Subscribe to container events
EventBus.on("containers:open_all_complete", function()
  print("All containers opened!")
end)
```

The `onAddItem` handler queues new container items for opening, and `onContainerOpen` triggers scanning of newly opened containers.

---

## ❓ Troubleshooting

### Containers not opening on login

1. Is **Auto Open** enabled in the panel?
2. Are containers correctly assigned to slots?
3. Wait a few seconds after login — the opener has a deliberate delay
4. Check console for `containers:open_all_complete` event

### Quiver not refilling

1. Do you have arrows/bolts in a supply container?
2. Is the quiver equipped?
3. Are the arrows the correct type for your weapon?

### Items going to wrong container

1. Verify container role assignments
2. Check slot order matches your in-game backpack layout
3. Reset container configuration and re-assign

### "Schedule execution error" or nil function errors

This usually means a partial or outdated `Containers.lua` file. Replace it with the latest version and restart the client. If the error persists after restart, the server may have reached its open container limit (~20) — close some backpacks manually and re-open them via the "Reopen All" button.

### Containers closing immediately after opening

The server has a limit of ~20 open containers. The bot enforces a safety margin at 19 — when the limit is reached, BFS pauses and resumes when a container closes. Keep your assigned containers under 15-18 to leave room for loot bags and other dynamically opened containers.
