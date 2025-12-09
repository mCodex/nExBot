# 📦 Containers Documentation

**Smart container management and loot organization**

---

## 📖 Overview

The Container Panel automates container management:
- Auto-open containers on login
- Organize items between backpacks
- Smart quiver arrow management
- Drag-and-drop configuration

---

## 🚀 Quick Start

### Setting Up Containers

1. **Open Container Panel**
   - Click the Containers tab in main window

2. **Assign Container Roles**
   - Click a container slot
   - Select the container type:
     - Main Backpack
     - Loot Container
     - Supplies
     - Runes
     - Quiver

3. **Enable Auto-Open**
   - Toggle "Auto Open on Login"

---

## 🎒 Container Types

### Standard Containers

<details>
<summary><b>🎒 Main Backpack</b></summary>

Your primary backpack containing everything.

**Best Practice:**
- Use a large backpack (Cap Bag, Adventurer's Bag)
- Contains other specialized containers
- Should be in slot 0

</details>

<details>
<summary><b>💰 Loot Container</b></summary>

Where monster drops go automatically.

**Configuration:**
- Enable "Auto Loot to Container"
- Set in TargetBot loot settings
- Use Beach Bag for capacity

> [!TIP]
> Use a container with 36 slots for maximum efficiency!

</details>

<details>
<summary><b>🧪 Supplies Container</b></summary>

Potions and consumables.

**Best Items:**
- Health Potions
- Mana Potions
- Spirit Potions
- Food

</details>

<details>
<summary><b>✨ Runes Container</b></summary>

Attack and utility runes.

**Best Items:**
- Sudden Death Runes
- Avalanche Runes
- Great Fireball Runes
- Magic Wall Runes

</details>

---

### Quiver System

<details>
<summary><b>🏹 Quiver Container</b></summary>

Automatic arrow/bolt management for Paladins.

**How it works:**
1. Monitors equipped ammunition
2. Detects when quiver is running low
3. Automatically refills from supplies
4. Works with all arrow/bolt types

**Supported Ammo:**
| Type | Item ID |
|------|---------|
| Arrows | 3447 |
| Bolts | 3446 |
| Power Bolts | 3450 |
| Infernal Bolts | 6528 |
| Prismatic Bolts | 16143 |
| Spectral Bolts | 35901 |
| Crystalline Arrows | 15793 |
| Diamond Arrows | 28415 |
| Spectral Arrows | 35902 |

> [!NOTE]
> Quiver management is enabled by default! No toggle needed.

</details>

---

## ⚙️ Configuration Options

### Panel Settings

| Setting | Description | Default |
|---------|-------------|---------|
| **Auto Open** | Open containers on login | OFF |
| **Auto Stack** | Stack identical items | ON |
| **Sort Containers** | Organize item positions | OFF |
| **Close Empty** | Close empty containers | OFF |

### Container Assignment

```
Slot 0: Main Backpack
Slot 1: Loot Container
Slot 2: Supplies
Slot 3: Runes
Slot 4: Quiver (if Paladin)
```

> [!TIP]
> Keep the same container order for all characters!

---

## 🔄 Auto-Management Features

### On Login

1. Waits for containers to load (500ms delay)
2. Opens assigned containers
3. Checks for quiver refill
4. Triggers initial organization

### During Hunting

1. Monitors container contents
2. Auto-refills quiver when low
3. Tracks capacity usage
4. Alerts when loot bag is full

### On Depot Visit

1. Works with Depositor module
2. Transfers loot to depot
3. Refills supplies from depot
4. Resets container state

---

## 📝 Usage Examples

<details>
<summary><b>Standard Knight Setup</b></summary>

```
Main BP: Golden Backpack
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
└── Runes: Blue Backpack (SD/Magic Wall)
```

</details>

<details>
<summary><b>Paladin Setup (with Quiver)</b></summary>

```
Main BP: Adventurer's Bag
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
├── Ammo: Grey Backpack (arrows reserve)
└── Quiver: Auto-managed!
```

</details>

<details>
<summary><b>Mage Setup</b></summary>

```
Main BP: Jewelled Backpack
├── Supplies: Beach Bag (mana potions)
├── Loot: Beach Bag (drops)
└── Runes: Blue Backpack (attack runes)
```

</details>

---

## ⚠️ Common Issues

<details>
<summary><b>Containers not opening on login</b></summary>

**Check:**
1. Is Auto-Open enabled?
2. Are containers correctly assigned?
3. Wait a few seconds after login
4. Check if containers exist in inventory

</details>

<details>
<summary><b>Quiver not refilling</b></summary>

**Check:**
1. Do you have arrows in a container?
2. Is the quiver equipped?
3. Are arrows the correct type?
4. Check container accessibility

</details>

<details>
<summary><b>Items going to wrong container</b></summary>

**Solution:**
1. Verify container assignments
2. Check container slot order
3. Reset container configuration
4. Re-assign each container

</details>

---

## 💡 Pro Tips

> [!TIP]
> **Organization:** Use different colored backpacks to identify contents at a glance.

> [!TIP]
> **Capacity:** Use Beach Bags (36 slots) for loot to maximize hunting time.

> [!TIP]
> **Quiver:** Keep 1000+ arrows in reserve for long hunts.

> [!TIP]
> **Auto-Open:** Enable to save time on login and after deaths.
