# Anaglyph to SBS or TAB

Convert **anaglyph 3D** (e.g. red/cyan) into **Side-by-Side (SBS)** or **Top-and-Bottom (TAB)** using either:
- a **ReShade** shader (`.fx`) for games
- a **RetroArch/Slang** shader (`.slang`) for emulators / ShaderGlass

## What it does

### Supported anaglyph modes (input)
- **Red/Cyan**
- **Red/Green**
- **Red/Blue**
- **Green/Magenta**
- **Amber/Blue**
- **Magenta/Cyan**

### Output layouts
- **Composite** (both eyes combined)
- **Side-by-Side** (Left to Right)
- **Side-by-Side Swap** (Right to Left)
- **Top-and-Bottom** (Top over Bottom)
- **Top-and-Bottom Swap** (Bottom over Top)
- **Full Side-by-Side**
- **Half Side-by-Side**
- **Full Top-and-Bottom**
- **Half Top-and-Bottom**

### Output colours
- **Lens (filtered colour)**
- **Mono (grayscale)**
- **Red (debug)**
- **Desat (partially desaturated)**
- **Luma (custom weights)**

## Files included
- `shaders/reshade/Anaglyph_to_SBS_or_TAB.fx`
- `shaders/retroarch/Anaglyph_to_SBS_or_TAB.slang`

## Install (ReShade)
1. Copy `shaders/reshade/Anaglyph_to_SBS_or_TAB.fx` into your ReShade `Shaders` folder.
2. Enable it in the ReShade overlay.

## Install (RetroArch)
1. Copy `shaders/retroarch/Anaglyph_to_SBS_or_TAB.slang` into your RetroArch shader folder.
2. Load it from RetroArch’s shader menu.

## Install (ShaderGlass)
ShaderGlass can load RetroArch `.slang` shaders:
1. Import `shaders/retroarch/Anaglyph_to_SBS_or_TAB.slang` into [ShaderGlass](https://github.com/mausimus/ShaderGlass).
2. Enable it and select your desired layout/output in preferences.

## Credits
Inspired by the RetroArch/libretro shader `anaglyph-to-sbs.glsl` from `libretro/glsl-shaders`:
https://github.com/libretro/glsl-shaders

## License
GPL-3.0-or-later. See `LICENSE`.
