// nExBot Icon Build — deterministic SVG + PNG generation.
//
// Renders every icon in catalog.mjs to:
//   ui/assets/icons/<name>.svg                         (source of truth output)
//   ui/assets/icons/generated/<name>_<size>.png        (runtime assets)
//
// Sizes: 16, 20, 24, 32. PNGs are committed; SVG remains the canonical source.
// Runtime never converts SVG — PNGs are pre-rendered by this script.
//
// Usage: node tools/icons/build.mjs
// Requires: @resvg/resvg-js (dev dependency)

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";
import { MODULES, ACTIONS, NAVIGATION, STATUS, WRAPPER } from "./catalog.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const svgDir = join(root, "ui", "assets", "icons");
const pngDir = join(svgDir, "generated");
const sizes = [16, 20, 24, 32];

const all = { ...MODULES, ...ACTIONS, ...NAVIGATION, ...STATUS };

async function render(svgText, size) {
  const resvg = new Resvg(svgText, {
    fitTo: { mode: "width", value: size },
    background: "rgba(0,0,0,0)",
  });
  const png = resvg.render().asPng();
  return png;
}

let written = 0;
await mkdir(svgDir, { recursive: true });
await mkdir(pngDir, { recursive: true });

for (const [name, body] of Object.entries(all)) {
  const svgText = WRAPPER(body);
  await writeFile(join(svgDir, `${name}.svg`), svgText, "utf8");
  written++;
  for (const size of sizes) {
    const png = await render(svgText, size);
    await writeFile(join(pngDir, `${name}_${size}.png`), png);
  }
}

console.log(`[icons] wrote ${written} icons × ${sizes.length} sizes → ${pngDir}`);
