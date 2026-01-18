/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Anaglyph_to_SBS_or_TAB.slang
 *
 * Based on and inspired by the RetroArch/libretro shader:
 *   anaglyph-to-sbs.glsl from the libretro/glsl-shaders collection.
 *   Upstream collection: https://github.com/libretro/glsl-shaders
 *
 * This file is distributed under the GNU GPL v3 (or later).
 * Include a copy of the GPL license text (e.g. COPYING) when distributing.
 *
 * Modifications/rewrites and added features (SBS/TAB packing, aspect handling,
 * multiple anaglyph schemes, intensity blending, extra output modes) by: Effie Colton, 2026.
 */

#version 450

#pragma name Anaglyph_to_SBS_or_TAB
#pragma format R8G8B8A8_UNORM

// Anaglyph schemes (common):
// 1=Red/Cyan        (R / G+B)
// 2=Red/Green       (R / G)
// 3=Red/Blue        (R / B)
// 4=Green/Magenta   (G / R+B)
// 5=Amber/Blue      (R+G / B)
// 6=Magenta/Cyan    (R+B / G+B)
#pragma parameter anaglyph_mode "Anaglyph Mode (1=R/C 2=R/G 3=R/B 4=G/M 5=Amber/B 6=M/C)" 1.0 1.0 6.0 1.0

// Output layout:
// 0=Composite (add both eyes into one image)
// 1=SBS (L|R)
// 2=SBS Swap (R|L)
// 3=TAB (T over B)
// 4=TAB Swap (B over T)
#pragma parameter force_layout "Force Layout (0=Composite 1=SBS 2=SBSswap 3=TAB 4=TABswap)" 0.0 0.0 4.0 1.0

// Aspect interpretation:
// 0=Full (use OutputSize if available, else SourceSize)
// 1=TAB  (treat output height as half-height)
// 2=SBS  (treat output width as half-width)
#pragma parameter force_aspect "Force Aspect (0=Full 1=TAB 2=SBS)" 0.0 0.0 2.0 1.0

// Separation (normalized): -1..1 maps to -0.5..0.5 UV
// Always snapped to pixel steps for clean alignment.
#pragma parameter h_sep "Horizontal Separation (-1..1 => -0.5..0.5 UV)" 0.0 -1.0 1.0 0.001
#pragma parameter v_sep "Vertical Separation (-1..1 => -0.5..0.5 UV)"   0.0 -1.0 1.0 0.001

#pragma parameter ana_zoom  "Zoom"      1.000 0.25 4.00 0.005
#pragma parameter WIDTH     "Stretch X" 1.000 0.25 4.00 0.005
#pragma parameter HEIGHT    "Stretch Y" 1.000 0.25 4.00 0.005

// Filter intensity:
// 0 = no filter (per-eye shows full colour, composite uses a simple average)
// 1 = full filter
#pragma parameter intensity "Filter Intensity" 1.0 0.0 1.0 0.01

// Output modes:
// 0=Lens  (what each eye would see through the filters, intensity-blended)
// 1=Mono  (scheme-consistent mono, intensity-blended vs normal luma)
// 2=Red   (mono shown in red channel, for debugging/alignment)
// 3=Desat (lens output partially desaturated)
// 4=Luma  (standard Rec.709 luma of the lens output)
#pragma parameter output_mode "Output (0=Lens 1=Mono 2=Red 3=Desat 4=Luma)" 0.0 0.0 4.0 1.0

layout(set = 0, binding = 0, std140) uniform UBO
{
    mat4 MVP;
    vec4 SourceSize;
    vec4 OutputSize;

    float anaglyph_mode;
    float force_layout;
    float force_aspect;

    float h_sep;
    float v_sep;

    float ana_zoom;
    float WIDTH;
    float HEIGHT;

    float intensity;

    float output_mode;
} registers;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTex;

void main()
{
    gl_Position = registers.MVP * Position;
    vTex = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTex;
layout(location = 0) out vec4 FragColor;
layout(binding = 1) uniform sampler2D Source;

float snap_to_step(float x, float step)
{
    return floor(x / step + 0.5) * step;
}

float clamp01(float x)
{
    return max(0.0, min(1.0, x));
}

vec4 sample_safe(vec2 uv)
{
    if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0)
        return vec4(0.0);
    return texture(Source, uv);
}

vec2 fit_inside(vec2 uv, float srcAsp, float dstAsp)
{
    vec2 p = uv - 0.5;
    if (dstAsp > srcAsp) p.x *= (dstAsp / srcAsp);
    else                 p.y *= (srcAsp / dstAsp);
    return p + 0.5;
}

// Rec.709 luma
float luma709(vec3 rgb)
{
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

// Scheme-specific mono intensity (matches the filter pairing)
float eye_intensity(vec4 s, int scheme, int whichFilterEye)
{
    if (scheme == 1) return (whichFilterEye == 0) ? s.r : (s.g + s.b) * 0.5;                // R/C
    if (scheme == 2) return (whichFilterEye == 0) ? s.r : s.g;                              // R/G
    if (scheme == 3) return (whichFilterEye == 0) ? s.r : s.b;                              // R/B
    if (scheme == 4) return (whichFilterEye == 0) ? s.g : (s.r + s.b) * 0.5;                // G/M
    if (scheme == 5) return (whichFilterEye == 0) ? (s.r + s.g) * 0.5 : s.b;                // Amber/B
    if (scheme == 6) return (whichFilterEye == 0) ? (s.r + s.b) * 0.5 : (s.g + s.b) * 0.5;  // M/C
    return luma709(s.rgb);
}

// Filtered RGB for the scheme (no intensity blending here)
vec3 filter_view(vec4 s, int scheme, int whichFilterEye)
{
    if (scheme == 1) return (whichFilterEye == 0) ? vec3(s.r,0,0)     : vec3(0,s.g,s.b); // R/C
    if (scheme == 2) return (whichFilterEye == 0) ? vec3(s.r,0,0)     : vec3(0,s.g,0);   // R/G
    if (scheme == 3) return (whichFilterEye == 0) ? vec3(s.r,0,0)     : vec3(0,0,s.b);   // R/B
    if (scheme == 4) return (whichFilterEye == 0) ? vec3(0,s.g,0)     : vec3(s.r,0,s.b); // G/M
    if (scheme == 5) return (whichFilterEye == 0) ? vec3(s.r,s.g,0)   : vec3(0,0,s.b);   // Amber/B
    if (scheme == 6) return (whichFilterEye == 0) ? vec3(s.r,0,s.b)   : vec3(0,s.g,s.b); // M/C

    float m = eye_intensity(s, scheme, whichFilterEye);
    return vec3(m);
}

vec3 desaturate(vec3 rgb, float k)
{
    float l = luma709(rgb);
    return mix(rgb, vec3(l), clamp01(k));
}

void main()
{
    // ----- choose effective output size for pixel snapping -----
    vec2 outSz = (registers.OutputSize.x > 8.0 && registers.OutputSize.y > 8.0)
               ? registers.OutputSize.xy
               : registers.SourceSize.xy;

    // ----- aspect handling -----
    float srcAsp = registers.SourceSize.x / max(registers.SourceSize.y, 1.0);

    float fullAsp = outSz.x / max(outSz.y, 1.0);
    int fa = int(registers.force_aspect + 0.5);

    float dstAsp = fullAsp;
    if (fa == 1) dstAsp = fullAsp * 2.0; // TAB: effective height halved -> aspect doubled
    if (fa == 2) dstAsp = fullAsp * 0.5; // SBS: effective width halved  -> aspect halved

    // ----- build working UV in fragment (stable, known-good structure) -----
    vec2 uv = vTex;
    uv = fit_inside(uv, srcAsp, dstAsp);

    float z  = snap_to_step(registers.ana_zoom, 0.005);
    float sx = snap_to_step(registers.WIDTH,    0.005);
    float sy = snap_to_step(registers.HEIGHT,   0.005);

    uv = (uv - 0.5) * z  + 0.5;
    uv = (uv - 0.5) * vec2(sx, sy) + 0.5;

    // ----- separation (normalized -> UV), snapped to pixel steps -----
    float h = registers.h_sep * 0.5;
    float v = registers.v_sep * 0.5;

    float pxX = 1.0 / max(outSz.x, 1.0);
    float pxY = 1.0 / max(outSz.y, 1.0);

    h = snap_to_step(h, pxX);
    v = snap_to_step(v, pxY);

    int scheme = int(registers.anaglyph_mode + 0.5);
    if (scheme < 1) scheme = 1;
    if (scheme > 6) scheme = 6;

    int outm = int(registers.output_mode + 0.5);
    int lay  = int(registers.force_layout + 0.5);

    bool wantSBS = (lay == 1 || lay == 2);
    bool wantTAB = (lay == 3 || lay == 4);

    vec2 dL, dR;
    if (wantSBS)      { dL = vec2(-h, 0.0); dR = vec2( h, 0.0); }
    else if (wantTAB) { dL = vec2(0.0, -v); dR = vec2(0.0,  v); }
    else              { dL = vec2(-h, -v);  dR = vec2( h,  v); }

    float t = clamp01(registers.intensity);

    // ----- packed layouts (SBS/TAB) -----
    if (lay != 0)
    {
        int whichEye = 0; // 0=left view, 1=right view
        vec2 localUV = uv;

        // FIX: avoid fract() wrapping/tiling. Only show one L and one R.
        if (wantSBS)
        {
            float x2 = localUV.x * 2.0;

            // Outside packed region -> black, not repeated
            if (x2 <= 0.0 || x2 >= 2.0)
            {
                FragColor = vec4(0.0);
                return;
            }

            int pane = (x2 >= 1.0) ? 1 : 0;                 // 0 = left half, 1 = right half
            localUV.x = x2 - float(pane);                    // map into [0..1] without wrapping

            whichEye = pane;
            if (lay == 2) whichEye = 1 - whichEye;           // SBS swap
        }
        else
        {
            float y2 = localUV.y * 2.0;

            if (y2 <= 0.0 || y2 >= 2.0)
            {
                FragColor = vec4(0.0);
                return;
            }

            int pane = (y2 >= 1.0) ? 1 : 0;                 // 0 = top half, 1 = bottom half
            localUV.y = y2 - float(pane);

            whichEye = pane;
            if (lay == 4) whichEye = 1 - whichEye;          // TAB swap
        }

        vec4 sL = sample_safe(localUV + dL);
        vec4 sR = sample_safe(localUV + dR);

        vec4 s   = (whichEye == 0) ? sL : sR;
        int  fil = (whichEye == 0) ? 0  : 1;

        vec3 masked = filter_view(s, scheme, fil);
        vec3 lens   = mix(s.rgb, masked, t); // intensity blends filter "opacity"

        if (outm == 0) // Lens
        {
            FragColor = vec4(lens, 1.0);
            return;
        }
        else if (outm == 3) // Desat (of lens)
        {
            FragColor = vec4(desaturate(lens, 0.60), 1.0);
            return;
        }
        else if (outm == 4) // Luma (Rec.709 of lens)
        {
            float L = luma709(lens);
            FragColor = vec4(vec3(L), 1.0);
            return;
        }
        else
        {
            // Mono/Red: blend between normal luma and scheme-mono using intensity
            float mono_unf = luma709(s.rgb);
            float mono_sch = eye_intensity(s, scheme, fil);
            float mono     = mix(mono_unf, mono_sch, t);

            if (outm == 2) FragColor = vec4(mono, 0.0, 0.0, 1.0); // Red
            else           FragColor = vec4(vec3(mono), 1.0);      // Mono
            return;
        }
    }

    // ----- composite output -----
    vec4 sL = sample_safe(uv + dL);
    vec4 sR = sample_safe(uv + dR);

    vec3 avg = (sL.rgb + sR.rgb) * 0.5;

    vec3 maskedSum = filter_view(sL, scheme, 0) + filter_view(sR, scheme, 1);
    vec3 lensSum   = mix(avg, maskedSum, t); // at t=0 show normal-looking image, at t=1 show full anaglyph composite

    if (outm == 0) // Lens
    {
        FragColor = vec4(lensSum, 1.0);
        return;
    }
    if (outm == 3) // Desat
    {
        FragColor = vec4(desaturate(lensSum, 0.60), 1.0);
        return;
    }
    if (outm == 4) // Luma
    {
        float L = luma709(lensSum);
        FragColor = vec4(vec3(L), 1.0);
        return;
    }

    // Mono/Red (scaled to 0..1-ish)
    float mono_unf = luma709(avg);
    float mono_sch = (eye_intensity(sL, scheme, 0) + eye_intensity(sR, scheme, 1)) * 0.5;
    float mono     = mix(mono_unf, mono_sch, t);

    if (outm == 2) FragColor = vec4(mono, 0.0, 0.0, 1.0); // Red
    else           FragColor = vec4(vec3(mono), 1.0);      // Mono
}
