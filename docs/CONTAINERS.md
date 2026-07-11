# Containers

Automated container management, auto-opening, quiver handling.

## Quick Start

1. Open **Containers** panel (Main tab)
2. Assign roles: Slot 0 = Main BP, Slot 1 = Loot, Slot 2 = Supplies, Slot 3 = Runes
3. Enable **Auto Open on Login**

## Container Roles

| Role | Purpose |
|------|---------|
| Main Backpack | Primary container holding others |
| Loot Container | Monster drops during hunting |
| Supplies Container | Potions, food, consumables |
| Runes Container | Attack/utility runes |

## Auto-Open System

BFS queue with re-scan on timeout:

1. Wait 500ms for containers to load
2. Open assigned containers
3. Scan for nested containers, queue for opening
4. Handle paginated containers
5. Re-scan parent on safety timeout
6. Skip monster corpses (dead, remains, body of)
7. Enforce server limit (max 19 open)
8. Emit `containers:open_all_complete`

### Architecture

| Component | Responsibility |
|-----------|----------------|
| ContainerBFS | BFS queue with O(1) pop |
| ContainerTracker | Prevent duplicate opens (4s grace) |
| ContainerScanner | Scan for nested containers |
| `getCachedContainers()` | Per-tick cache |

## Quiver Management

For Paladins — monitors ammo count, refills from supplies container. Works with all arrow/bolt types. Enabled by default.

## Configuration

| Setting | Default |
|---------|---------|
| Auto Open | OFF |
| Auto Stack | ON |
| Sort Containers | OFF |
| Close Empty | OFF |

## Setup Examples

**Knight:**
```
Main BP: Golden Backpack
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
└── Runes: Blue Backpack (SD / Magic Wall)
```

**Paladin:**
```
Main BP: Adventurer's Bag
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
├── Ammo: Grey Backpack (arrow reserve)
└── Quiver: Auto-managed
```

## EventBus

```lua
EventBus.on("containers:open_all_complete", function()
  print("All containers opened!")
end)
```

## Troubleshooting

**Not opening:** Auto Open enabled? Containers assigned? Wait a few seconds. Check console.

**Quiver not refilling:** Arrows/bolts in supply container? Quiver equipped? Correct type?

**Items going wrong:** Verify slot order matches in-game layout.

**Closing immediately:** Server limit ~20. Bot enforces 19. Keep assigned under 15–18.
