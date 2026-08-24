// nExBot Icon Catalog — original 24x24 stroke icon family.
// Each entry: { name, body } where `body` is the inner SVG markup.
// A shared wrapper adds the 24x24 viewBox, stroke styling, and currentColor.
// This file is the source of truth. tools/icons/build.mjs renders
// ui/assets/icons/*.svg and ui/assets/icons/generated/*_<size>.png.

export const WRAPPER = (body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

// ---------------------------------------------------------------------------
// Module icons
// ---------------------------------------------------------------------------
export const MODULES = {
  dashboard: `<rect x="3" y="3" width="8" height="8" rx="1.5"/><rect x="13" y="3" width="8" height="8" rx="1.5"/><rect x="3" y="13" width="8" height="8" rx="1.5"/><rect x="13" y="13" width="8" height="8" rx="1.5"/>`,
  cavebot: `<path d="M4 19 L10 7 L14 13 L20 5"/><circle cx="20" cy="5" r="1.6"/><circle cx="4" cy="19" r="1.6"/>`,
  targetbot: `<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 1.5 V5 M12 19 V22.5 M1.5 12 H5 M19 12 H22.5"/>`,
  healing: `<path d="M12 3 L20 8 V16 L12 21 L4 16 V8 Z"/><path d="M9 12 h6 M12 9 v6"/>`,
  looting: `<path d="M4 7 L12 3 L20 7 V17 L12 21 L4 17 Z"/><path d="M4 7 L12 11 L20 7"/><path d="M12 11 V21"/>`,
  supplies: `<path d="M10 3 h4 v5 l6 6 V20 H4 V14 L10 8 Z"/><path d="M8 17 h8"/>`,
  scripts: `<path d="M6 3 h9 l4 4 V21 H6 Z"/><path d="M15 3 V7 H19"/><path d="M9 12 l-2 2 2 2 M13 12 l2 2 -2 2"/>`,
  intelligence: `<circle cx="12" cy="12" r="8"/><path d="M12 4 a8 8 0 0 0 0 16 a5 5 0 0 0 0 -6 a3 3 0 0 0 0 -4 Z"/>`,
  learning: `<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 5 V3 M12 21 V19 M5 12 H3 M21 12 H19"/>`,
  monsters: `<path d="M12 3 L17 7 V13 L12 21 L7 13 V7 Z"/><circle cx="9.5" cy="10" r="1"/><circle cx="14.5" cy="10" r="1"/>`,
  navigation: `<circle cx="12" cy="12" r="8"/><path d="M14.5 9.5 L12 15 L9.5 9.5 L12 12 Z"/>`,
  profiles: `<circle cx="12" cy="8" r="4"/><path d="M4 21 c0-4 4-6 8-6 s8 2 8 6"/>`,
  settings: `<circle cx="12" cy="12" r="3"/><path d="M12 3 v3 M12 18 v3 M3 12 h3 M18 12 h3 M5.6 5.6 l2.1 2.1 M16.3 16.3 l2.1 2.1 M18.4 5.6 l-2.1 2.1 M7.7 16.3 l-2.1 2.1"/>`,
  diagnostics: `<path d="M3 12 h4 l3-7 4 14 3-7 h4"/>`,
  replay: `<circle cx="12" cy="12" r="8"/><path d="M12 7 v5 l3 2"/><path d="M8 4 V7 H5"/>`,
};

// ---------------------------------------------------------------------------
// Action icons
// ---------------------------------------------------------------------------
export const ACTIONS = {
  add: `<path d="M12 5 V19 M5 12 H19"/>`,
  remove: `<path d="M5 12 H19"/>`,
  edit: `<path d="M4 20 l4-1 11-11-3-3L5 16 Z"/><path d="M14 6 l3 3"/>`,
  save: `<path d="M5 3 h11 l3 3 V21 H5 Z"/><path d="M8 3 V8 H14 V3 M8 21 V14 H16 V21"/>`,
  import: `<path d="M12 3 V15 M7 10 l5 5 5-5"/><path d="M4 20 h16"/>`,
  export: `<path d="M12 15 V3 M7 8 l5-5 5 5"/><path d="M4 20 h16"/>`,
  refresh: `<path d="M4 12 a8 8 0 1 0 3-6"/><path d="M7 3 v4 h4"/>`,
  search: `<circle cx="11" cy="11" r="6"/><path d="M16 16 L21 21"/>`,
  filter: `<path d="M4 5 h16 L14 13 V19 L10 21 V13 Z"/>`,
  close: `<path d="M6 6 L18 18 M18 6 L6 18"/>`,
  info: `<circle cx="12" cy="12" r="9"/><path d="M12 11 v5 M12 7.5 v.5"/>`,
  warning: `<path d="M12 3 L22 20 H2 Z"/><path d="M12 10 v4 M12 17 v.5"/>`,
  success: `<circle cx="12" cy="12" r="9"/><path d="M8 12.5 l2.5 2.5 L16 9.5"/>`,
  paused: `<path d="M9 5 V19 M15 5 V19"/>`,
  active: `<path d="M7 4 L19 12 L7 20 Z"/>`,
  expand: `<path d="M5 9 L12 16 L19 9"/>`,
  collapse: `<path d="M5 15 L12 8 L19 15"/>`,
  reorder: `<path d="M7 6 h10 M7 12 h10 M7 18 h10"/><circle cx="4.5" cy="6" r="0.8"/><circle cx="4.5" cy="12" r="0.8"/><circle cx="4.5" cy="18" r="0.8"/>`,
  record: `<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/>`,
  stop: `<path d="M7 7 h10 v10 H7 Z"/>`,
};

// ---------------------------------------------------------------------------
// Navigation / game action icons
// ---------------------------------------------------------------------------
export const NAVIGATION = {
  waypoint: `<path d="M12 3 L19 10 L12 21 L5 10 Z"/><circle cx="12" cy="10" r="2.5"/>`,
  route: `<circle cx="5" cy="5" r="2.5"/><circle cx="19" cy="19" r="2.5"/><path d="M7.5 5 H14 a4 4 0 0 1 0 8 H10 a4 4 0 0 0 0 8 H16.5"/>`,
  "stairs-up": `<path d="M6 20 V12 L12 12 V7 L18 7"/><path d="M15 4 l3 3 -3 3"/><path d="M6 16 h6 M6 12 h6"/>`,
  "stairs-down": `<path d="M6 4 V12 L12 12 V17 L18 17"/><path d="M15 20 l3-3 -3-3"/><path d="M6 8 h6 M6 12 h6"/>`,
  ladder: `<path d="M7 4 V20 M17 4 V20"/><path d="M7 8 h10 M7 13 h10 M7 18 h10"/>`,
  hole: `<path d="M12 3 L21 8 V16 L12 21 L3 16 V8 Z"/><path d="M8 12 L16 12"/>`,
  rope: `<path d="M8 4 a7 7 0 0 1 8 0 v7 a4 4 0 0 1 -8 0 Z"/><path d="M8 18 V21 M16 18 V21"/>`,
  shovel: `<path d="M7 4 L20 17 L18 19 L5 6 Z"/><path d="M5 19 L8 16 M4 20 L8 16"/>`,
  door: `<rect x="5" y="4" width="14" height="16" rx="1.5"/><circle cx="14" cy="12" r="1.2"/><path d="M5 10 h2"/>`,
  obstacle: `<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 8 v8 M16 8 v8"/>`,
  recovery: `<path d="M12 4 a8 8 0 1 1 -8 8"/><path d="M4 12 V4 h8"/><path d="M12 9 v6 h-3"/>`,
  target: `<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>`,
  shield: `<path d="M12 3 L20 6 V11 a8 8 0 0 1 -8 10 a8 8 0 0 1 -8 -10 V6 Z"/><path d="M9 12 l2 2 4-4"/>`,
  potion: `<path d="M10 3 h4 v4.5 L19 13 V21 H5 V13 L10 7.5 Z"/><path d="M8.5 17 h7"/>`,
  backpack: `<path d="M7 7 H17 V20 H7 Z"/><path d="M9 7 a3 3 0 0 1 6 0"/><path d="M12 10 v6 M9 13 h6"/>`,
};

// ---------------------------------------------------------------------------
// Status glyphs used inside badges / status strips
// ---------------------------------------------------------------------------
export const STATUS = {
  "status-ok": `<circle cx="12" cy="12" r="8"/><path d="M8 12.5 l2.5 2.5 L16 9.5"/>`,
  "status-paused": `<circle cx="12" cy="12" r="8"/><path d="M10 9 v6 M14 9 v6"/>`,
  "status-warning": `<path d="M12 3 L22 20 H2 Z"/><path d="M12 10 v4 M12 17 v.5"/>`,
  "status-error": `<circle cx="12" cy="12" r="8"/><path d="M9 9 L15 15 M15 9 L9 15"/>`,
  "status-active": `<circle cx="12" cy="12" r="8"/><path d="M10 8 L16 12 L10 16 Z"/>`,
  "status-info": `<circle cx="12" cy="12" r="8"/><path d="M12 11 v5 M12 7.5 v.5"/>`,
};
