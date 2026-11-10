# Art Spec v2: Alien Landfall, Isometric (DRAFT, Nov 9 2026)
Replaces Art Spec v1 (Cold War paper map). Archive v1 as docs/art/ART_SPEC_v1.md; don't delete it. Mockup: art_v2_iso_mockup.jpg (shows the look only; labels and stats are filler).

**Look:** an original homage to late-90s alien-planet 4X games. The planet is painted, readable, and a little hostile, made of rust flats, ochre highlands, fungal pink stands, and a teal sea. Use simple shading (flat color, one highlight, one shadow), no photo textures. Everything comes from data/art_palette.json.

## Projection
- Use flat-top hexes squashed 2:1. The top face is 96x48px (scaled from the v1 hex: x stays, y x0.5).
- Elevation is an int from -3 to +4 (8 levels): -3 trench, -2 deep ocean, -1 ocean, 0 shallows, +1 lowland, +2 upland, +3 highland, +4 peaks. Each level shifts the top face 10px, with sea levels drawn below the waterline. Terrain type and elevation are separate values.
- **Ramps (visual only, David Nov 9):** draw a ramp on every 1-level step between land neighbors, using a tilted slope strip with a lighter slope color and 3 to 4 stair-tick lines on the higher tile's front edge. Movement isn't gated by ramps, so any land neighbor 1 level apart is passable per the Designer's rules. A difference of 2 or more is drawn as a sheer cliff.
- Ocean depth shading: shallows #2F9C9A, ocean #14505A, deep #0E3A48, trench #08222E.
- Draw a side skirt on the 3 front-facing edges down to the neighbor's height. The skirt is the terrain color darkened 35% (left) and 20% (right).
- There's no camera rotation. One zoom level is fine for the MVP.

## Palette (starting values)
- Terrain tops:
  - Rust plains #A4532F
  - Fungal forest #B0558F with vein accents #6E2F6B
  - Ochre hills #C9A04E
  - Highland or mountain #D8B872, with rock #8A6A3A
  - Shallow ocean #2F9C9A
  - Ocean #14505A
  - Crater #2A1E1E
  - Scorched #5C3A2C
- Grid: a 1px line, black at alpha 0.20. Coast foam: a 2px line at #9FE0D0, alpha 0.5, on land-water edges.
- UI: background #0D1614, panel #15211E, bevel light #4F6B62, bevel dark #070C0B, text amber #E6B85C, data teal #5FD3C0, dim #7C8C84, alert #E0583A.
- Faction slots (10): #3FA7D6, #D64545, #E3C14B, #5DBB63, #9B6FD1, #E07B39, #3CC4B0, #D65FA0, #C9C9C9, #7A8FE0. Land factions use slots 0 to 6 and sea factions use 7 to 9. All of them stay distinct against rust, ochre, and teal.

## Terrain looks (existing types plus new ones)
- **Plains:** rust top with a speckle overlay, typically +1 lowland.
- **Forest (fungus):** rust base (typically +1 lowland) plus 2 to 4 squiggly, worm-like tendril clusters per tile (coiling tubes, no caps), #B0558F with darker veins #6E2F6B and a #E07AB8 highlight.
- **Fungus density and blending:** each fungus tile has a `fungus_density` from 1 to 4 (1 sparse worms, 2 clusters, 3 dense tangle, 4 solid mass). It's drawn from a 6-bit neighbor mask: edges toward fungus neighbors get tendrils that bridge and join across the edge, and other edges get thin trailing ends. **Critical mass:** at density 4, or with 5 or more fungus neighbors, the tile renders as a continuous mat that bleeds over its edges. Touching mass tiles merge into one blob, and the grid line under them fades to alpha 0.05. Procedural is fine (seeded per tile for a stable look). Growth and critical-mass rules belong to Game Designer; the art only reads density plus neighbors.
- **Hills:** ochre, typically +2 upland, with a soft rim highlight.
- **Mountains:** highland color, +3 highland or +4 peaks, with a rock skirt.
- **Shallow ocean** (new): elevation 0, lighter, ringing the coasts.
- **Ocean** (new): elevation -1 (ocean), -2 (deep), or -3 (trench), shaded darker with depth, with an optional slow wave tint.
- **Crater** keeps its v1 role.
- Placeholders can be procedural polygons. Sprites come later.

## Bases (cities)
- A small domed module sprite or polygon, about 40x32, sitting on the tile top.
- A name plate below it on a panel #15211E with a 1px faction-color border, showing NAME and the population number in amber.
- A capital gets a faction-color beacon dot on the dome. Bases must never look like units.

## Units
- An upright plate 28x34, like a standee, anchored at the bottom center of the tile top, plus a soft shadow ellipse (black at alpha 0.3).
- The plate fill is the faction color darkened 35%, with a 2px frame at #E6E0C8.
- The NATO symbol is kept: X for infantry, oval for armor, dot for artillery. A sea unit uses a hull wedge.
- ORG and STR bars sit under the plate at 3px each. Selected is a 2px teal #5FD3C0 ring on the tile. Spent counters are at alpha 0.55.
- A stack shows the top unit plus a small count badge.
- Arrows keep the v1 curved Bezier, drawn on the tile-top plane and lifted by the target's elevation.

## UI chrome (datalink terminal)
- Dark panels, 2px bevels (light at top-left, dark at bottom-right), and a subtle 1px scanline overlay at alpha 0.06.
- Monospace font. Headers are caps amber at 13px, data is teal at 12px.
- Top bar is 32px with the year or turn centered. The right panel is 240px, anchored right (fixing the v1 nit). Icons are line art in teal.

## Godot implementation notes (for sizing)
1. **Hex to screen:** `p = hex_to_pixel_flat(cell); screen = Vector2(p.x, p.y * 0.5) - Vector2(0, elev * 12)`. Keep the game logic in axial or offset coordinates and change only the view.
2. **Draw order:** go row by row from back to front (by screen y, then x). For each row, draw the skirts, then the tops, then the decor, then that row's bases and units. Because units are interleaved with tiles, a taller tile in front correctly hides a unit behind it. Alternatively, put tiles and units as nodes in one y_sort_enabled Node2D. Draw arrows, selection, and the UI last.
3. **Click picking:** undo the y-scale and test candidate tiles from highest elevation and front-most first, using a point-in-polygon check on each tile's raised top face, because a tall tile can cover the one behind it. Fall back to the flat inverse.
4. **Data:** add a per-tile `elevation` to the map data, and add `iso: {tile_w: 96, tile_h: 48, step: 10, min_elev: -3, max_elev: 4, skirt_dark: [0.35, 0.20]}`, `factions[10]`, `ui{}`, and the new terrain keys to art_palette.json.
5. **Rough size:** 3 to 4 PRs: (a) projection, elevation, skirts, and picking; (b) palette, terrain looks, and coast; (c) bases and unit standees on iso; (d) the datalink UI theme.

**Needs David's eyes:** the 2:1 squash and 10px step feel, whether the fungal pink reads as alien and not candy, and whether 10 faction colors are distinguishable on rust.
