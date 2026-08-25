# Simple Navigation and Startup Design

## Goal

Make nExBot approachable for new players without removing capabilities or
changing bot behavior. Replace route depth and duplicate destinations with one
stable configuration workspace, retain a compact in-game controller, and stop
startup work from freezing the client.

## Interaction model

The host bot panel becomes a compact controller: Cave, Target, Heal, and Loot
status/toggles, one Pause action, and one Open nExBot action. It does not contain
configuration forms.

Open nExBot shows one approximately 420x380 native `MainWindow` with a persistent
category rail and a single content pane. Selecting a category replaces the pane
without browser-style history, Back, Home, or More routes.

The categories and owners are:

- **Overview:** character, active profile, hunt state, current target, engine
  status, master pause, and a compact AI pulse.
- **Hunt:** Route, Targeting, Loot, and Supplies tabs.
- **Character:** Healing, Conditions, and Equipment tabs.
- **Automation:** Tools, Safety, and Scripts tabs.
- **Settings:** Profiles, Interface, and Diagnostics tabs.

Each capability has one navigation owner. Cross-feature context uses a short
link to that owner rather than rendering a second set of controls. Advanced
controls remain on their owning page in a collapsed Advanced section. A modal
is allowed only for one focused complex record, such as a waypoint, creature,
healing rule, or equipment condition.

Category and tab selection persist for the session. Reopening the window returns
to the last view; opening from a contextual action selects the owning view. No
navigation action mutates bot state.

## Behavior compatibility

The redesign calls the existing domain methods used by the current UI. It does
not rename storage keys, change profile formats, alter defaults, adjust limits,
or change when engine state takes effect. Existing validation, persistence,
toggle behavior, profile selection, callbacks, and safety checks remain the
source of truth.

Before moving a workflow, tests characterize its current operation and observable
side effects. A legacy UI path is deleted only after every caller routes through
the new owner and parity tests pass. Unsupported controls remain on their current
working surface until a narrow domain API exists; they are never replaced by a
dead button.

## Visual system

The client owns backgrounds and typography. nExBot inherits native `MainWindow`,
panel, scrollbar, list, input, checkbox, switch, and item-slot appearances. It
does not introduce replacement window textures, background images, font files,
or font scaling.

nExBot's stylesheet is limited to layout and semantic emphasis:

- selected navigation and tabs use one restrained client-compatible highlight;
- primary, destructive, and compact icon CTAs have consistent states;
- rows use a 20px rhythm with aligned labels, values, and actions;
- meaningful Tibia items use native `UIItem` sprites at 24-32px;
- section spacing and separators express hierarchy without decorative cards;
- `verdana-11px-rounded` is the default readable font, with the existing
  monochrome/terminus fonts reserved for metadata and diagnostics.

Labels use player language and active verbs. Disabled actions explain the
missing prerequisite. Empty states tell the player what to configure next.

The AI pulse is read-only and limited to four values already owned by the AI
and analyzer runtimes: AI state, current decision, confidence, and one current
hunt outcome metric. Missing or disabled runtimes show an honest inactive state;
the Overview never starts analysis work or computes expensive metrics itself.

## Startup freeze investigation

Startup work is separated into required and deferrable phases. The existing
`loadTimes` data is extended with category timing and first-two-second scheduled
handler timing so the real freeze is measured before behavior changes.

Required synchronous initialization is limited to storage, profiles, client
compatibility, event/tick infrastructure, combat, healing, navigation safety,
and the compact controller. Intelligence analysis, analytics, diagnostics,
editor-window construction, cosmetic tools, and configuration pages load in
small scheduled batches after the first usable frame.

The cockpit no longer runs Bot Doctor inspection every 250ms. Diagnostics are
cached and refreshed on a slow interval or when the Diagnostics page explicitly
requests them. UI refresh compares a small screen-owned revision instead of
recursively fingerprinting large snapshots.

Deferred modules expose an honest loading state. Actions cannot execute until
their owner is ready, and load failures produce one sanitized message without
blocking the remaining batches.

## Verification

- Characterization tests cover every moved toggle, profile change, rule edit,
  save path, validation failure, and engine side effect.
- Navigation tests cover category/tab selection, contextual opening, session
  restoration, keyboard focus, disabled/loading states, and duplicate-owner
  prevention.
- Startup tests verify deterministic load phases, batch failure isolation, and
  that diagnostics are absent from the 250ms cockpit path.
- Lua parsing, the complete Busted suite, and `git diff --check` must pass.
- OTCv8 and OpenTibiaBR are checked at native scale for readable text, aligned
  rows, focus states, scrolling, item sprites, and unchanged client backgrounds.
- Real-client profiling records baseline and final total synchronous time,
  slowest categories, first-frame delay, and first-two-second peak handler time.

## Scope limits

No new dependency, asset pipeline, animation framework, theme engine, storage
schema, or speculative plugin system is added. Cleanup is limited to navigation,
presentation, startup loading, and legacy UI paths proven dead by call-site and
behavior tests.
