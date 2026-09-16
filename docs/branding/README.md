# Rosterra branding

The refreshed identity uses a white R monogram with a mint shift-block leg on an indigo background. The large silhouette stays readable in app icons, authentication screens, sidebars, and payslips.

`rosterra-icon-master.png` is the original artwork generated using the built-in image generation tool. Keep this source when exporting new sizes.

From the repository root, regenerate all app assets with:

```sh
swift scripts/generate-app-icon.swift Rosterra/Resources/Assets.xcassets/AppIcon.appiconset
```

The exporter writes the opaque 1024px iOS icon, all ten macOS sizes with rounded corners and transparent margins, and the shared AppLogo image. Existing asset names remain stable for all consumers.

## Generation prompt

Use case: logo-brand
Asset type: final production square app icon for Rosterra, a staff roster and shift scheduling application for iOS and macOS.
Primary request: redesign the logo as one beautifully proportioned, distinctive geometric R monogram subtly constructed from rounded schedule blocks. A strong near-white R with a single mint green diagonal leg or lower shift block, cohesive and immediately legible at 32 pixels. Simple bold silhouette, carefully balanced negative space.
Color palette: rich indigo background (#4F46E5 to #3730A3 very subtle gradient), near-white main mark, mint #6EE7B7 accent.
Style: premium minimal flat vector-like graphic, crisp clean edges, precise geometry, restrained softly rounded corners on the monogram.
Composition: one centered monogram occupying roughly 62 percent of square width and height, generous equal optical padding. Full bleed opaque indigo background all the way to every edge. Square 1024 by 1024 artwork.
Constraints: no text or wordmark other than the R symbol; no calendar border, no clock, no people, no tiny details, no drop shadows, no 3D, no texture, no mockup, no outer rounded square or transparent corners. Deliver just the ready-to-use icon artwork.
