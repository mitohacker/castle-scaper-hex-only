# Castle Scaper Realistic

Castle Scaper with a realistic look. The same Townscaper-style building (click a block onto an irregular grid on the sea; round towers, cone
roofs, wall walks with battlements, gate passages, courtyards, cottages, doors, windows, arches, corbels, stairs and a layer of details all come
out of what is around each block), drawn as a real stone castle on a rocky islet: procedural limestone, sandstone, render, granite and brick with
joints, cracks, lichen, moss and a weathered sea line; slate and clay-tile roofs; oak, iron and glass props; a see-through sea with waves, foam,
caustics on its floor and the castle's reflection, far islands on the horizon, smoke, gulls and a sailing boat; an analytic sky; real light, soft shadows, ambient occlusion and bounce light, god rays,
depth of field, a filmic grade and a lens. Four lights (golden hour, overcast, bright noon, dusk with lit windows) and four qualities (low to ultra, from 390 to 80 fps
at 1080p). Every texture is procedural; the look was fitted to Tripo image-gen mock-ups of the game's own castle (`../castle-scaper-realistic-art`).

Godot 4.7 (GDScript). A copy of Castle Scaper (which is unchanged).

```bat
launch-castle-scaper-realistic.bat      :: play
verify-castle-scaper-realistic.bat      :: compile, core suite (headless), editor suite (windowed, memory guard)
```

| | |
|---|---|
| left click | put a block (on the sea, on top, or beside: the face under the mouse decides) |
| right click | take it away |
| right drag / left or middle drag / wheel | turn / move / zoom |
| 1-0 - = or the swatches | material |
| Ctrl+Z / Ctrl+Y / Ctrl+S / Ctrl+N | undo / redo / save / empty sea |
| L / G | the light: golden hour, overcast, bright noon, dusk / the quality: low, medium, high, ultra |
| B / P / F / Space | birds / details / frame / slow turn |

Design, rules, engine, the look and numbers: [SPEC.md](SPEC.md). What is left compared with Townscaper: [TOWNSCAPER_GAP.md](TOWNSCAPER_GAP.md).

Files: `scripts/cs_grid.gd`, `cs_town.gd`, `cs_build.gd`, `cs_props.gd`, `cs_starter.gd`, `cs_main.gd` + `cs_ui.gd` (Castle Scaper's);
`cs_look.gd` (lights and qualities), `cs_rocks.gd` (rock skirt and sea floor), `cs_reflect.gd` (the reflection); `cf_*.gd` (Castle Forge's engine,
triangulator, roofs, audit, birds); `shaders/cs_castle`, `cs_props`, `cs_rock`, `cs_sea`, `cs_seabed`, `cs_sky`, `cs_lens` `.gdshader` and
`cs_common.gdshaderinc`. `tools/shots.ps1` takes clean screenshots under the memory guard.
