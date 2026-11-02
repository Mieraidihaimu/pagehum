# Pagehum app icon

A folded ivory page with text strokes and sound waves on cobalt blue connects
Pagehum's reading library with spoken audio. The artwork was created with the
built-in image generation tool on 2 November 2026.

## Assets

The app target already selects `AppIcon` in both Debug and Release. All images
live in `Pagehum/Assets.xcassets/AppIcon.appiconset/`.

- `AppIcon-iOS.png`: opaque, full-bleed 1024 × 1024 artwork. The system applies
  its icon mask.
- `AppIcon-macOS-1024.png`: 1024 × 1024 master with a rounded tile, shadow, and
  transparent outer padding for the Mac Dock, including macOS 15.
- `AppIcon-macOS-{16,32,64,128,256,512}.png`: size exports from the Mac master.
  `Contents.json` maps these to all ten Mac 1× and 2× slots.

Only the default iOS appearance is supplied; there are no empty appearance slots.
The asset format follows Apple's [asset catalog icon guidance](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
and [app icon schema](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/AppIconType.html).

To regenerate the smaller Mac exports without changing the artwork, run from
the repository root on macOS:

```sh
icon_dir=Pagehum/Assets.xcassets/AppIcon.appiconset
for pixel_size in 16 32 64 128 256 512; do
  sips -z "$pixel_size" "$pixel_size" "$icon_dir/AppIcon-macOS-1024.png" \
    --out "$icon_dir/AppIcon-macOS-$pixel_size.png"
done
```

## Verification

Both asset catalogs compiled successfully with Xcode 27's `actool`, targeting
iOS 18.6 (iPhone and iPad) and macOS 15.6. The Mac output includes `AppIcon.icns`;
the iOS output declares primary icons for iPhone and iPad. All eleven catalog
slots resolve to PNGs with the expected pixel dimensions. The iOS image has no
alpha channel, and the Mac exports retain transparent padding. The 32px and
128px Mac exports were also inspected visually.

## Generation prompts

### iOS artwork

```text
Use case: logo-brand
Asset type: production app icon artwork for Pagehum, a native Mac and iPhone app that reads saved articles, PDFs, and text aloud.
Primary request: Create one beautifully polished, memorable square app icon. A single sculptural ivory paper page with a softly curled top-right corner, centered on a rich blue background, with three short blue horizontal text strokes on the left of the page transitioning into three blue rounded sound-wave bars on the right. Reading turning into listening, distilled into one bold, clean symbol. The curled corner should be subtle and not add clutter. The overall page silhouette is softly rounded, upright, and immediately legible at tiny sizes.
Style/medium: refined Apple-native icon craftsmanship; simple dimensional paper with gentle depth and soft, restrained contact shadow, exceptionally clean edges, minimal forms, mostly front-facing. High contrast.
Color palette: warm ivory page, saturated cobalt blue matching the app's blue accent, subtly deeper blue toward the bottom of the background. No additional colors.
Composition/framing: exact square 1024 by 1024, one centered large page glyph occupying approximately 62 percent of the canvas width and 66 percent of the height. Full-bleed opaque blue background reaches every image edge. Generous negative space for OS corner masking.
Constraints: this is the actual image asset, not a mockup. Entire image square with no pre-rounded outer corners, no outer frame, no transparent padding. No lettering, words, monograms, watermark, grid, scene, device, presentation board, or multiple options. Do not add headphones, books, play triangles, microphones, sparkles, or extraneous objects. The audio motif must be bold and sparse enough to survive at 32px.
```

### Mac adaptation

The iOS artwork was the edit target, with transparent background enabled.

```text
Use case: precise-object-edit
Asset type: macOS 15 legacy app icon derived from the provided Pagehum icon artwork.
Input image: edit target, the approved blue Pagehum icon. Preserve its ivory folded page and blue reading/sound symbol exactly.
Primary request: Package the exact existing icon as a standard macOS app icon with transparent outer padding: scale the entire supplied square artwork uniformly to occupy 82 percent of the square canvas, centered; clip only the blue background's outside corners to the standard smooth macOS rounded-square/squircle shape. Add a very subtle soft shadow just beneath the rounded blue tile. The blue tile must be about 824 by 824 pixels on a 1024 by 1024 transparent canvas. Preserve the entire original composition within that tile. The cream page and blue horizontal lines plus three curved sound waves stay exactly as in the input.
Constraints: change only the outside tile's shape and transparent padding; keep the original artwork, relative proportions, blue palette, lighting, and interior details. This must be one isolated icon on a genuinely transparent background, including all four corners and padding. No mockup, grid, words, new objects, white background, or checkerboard painted into the pixels.
```
