# Changelog

All notable changes to nExBot are documented in this file.

## [Unreleased]

### Added
- Container Panel v6 — Event-driven container opener using EventBus and OTClient APIs
  - Queues direct `item` references and `parentId_slot` keys to support multiple sibling backpacks reliably
  - `onAddItem` now immediately queues new container items when they appear in open containers
  - Emits `containers:open_all_complete` after a full open run
- Developer Notes section in `docs/CONTAINERS.md`

### Fixed
- Fixed critical bug where `ContainerOpener.processNext()` expected `entry.item` but queue entries lacked the `item` field
- Resolved race conditions and duplicate legacy code in `core/Containers.lua`
- Ensured `isExcludedContainer` and helper functions are defined before use
- `minimizeContainer`, `renameContainer`, and `openQuiver` are now consistently invoked and available during processing
- Fixed `g_clock` nil error when loading certain modules

### Changed
- Container open flow simplified and made more reliable by scanning all open containers each pass and relying on EventBus for real-time behavior
- Quiver auto-open integrated into main open flow (paladin ammo access)
- Walking smoothing and movement parameters fine-tuned for better pathing and less jitter

### Other
- Friend Healer UI: added ability to add/remove spells directly from the friend healer panel
- Removed unused and duplicate files to clean the codebase

---

## [2025-12-XX] v1.0.0
- Initial public release notes.
