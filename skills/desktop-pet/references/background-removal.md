# Background Removal for Character Images

Users often hand over character images that are full-bleed PNGs with a solid or gradient
gray background. A desktop pet should show only the character, so cut the background out
before wiring up the window. Do not ship the gray rectangle.

## Recommended Approach

Use macOS Vision for the silhouette and a per-row difference key to recover light parts
such as white hair or light clothing that Vision may under-segment. Take the per-pixel
maximum of the two masks.

1. Run `VNGenerateForegroundInstanceMaskRequest` and call
   `observation.generateScaledMaskForImage(forInstances:from:)`. The returned buffer is
   image-sized and `kCVPixelFormatType_OneComponent32Float` (`L00f`), not 8-bit.
2. Draw the source into an 8-bit RGBA buffer. For each row, estimate the background color
   as the median of the leftmost and rightmost 3px columns; the background is roughly
   uniform horizontally, so this tracks vertical gradients.
3. For each pixel, `residual = max(|r-bgR|, |g-bgG|, |b-bgB|)` and map it through a
   smoothstep between about 18 and 34. `alpha = max(visionMask, differenceAlpha)`.
4. Write a premultiplied RGBA image (`CGImageAlphaInfo.premultipliedLast`); CGContext does
   not accept non-premultiplied alpha.

`scripts/cutout.swift` is a complete implementation. Run it as:

```bash
swift scripts/cutout.swift input.png output.png
```

## Swift Compile and Sandbox Gotchas

Vision uses the ANE and CoreVideo, both of which fail inside an app sandbox. Run the
cutout with escalated permissions (outside the sandbox). It only reads the source image
and writes a transparent PNG.

The Swift toolchain can also misbehave when CommandLineTools and its SDK are out of sync:

```bash
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.2.sdk
swiftc -module-cache-path "$TMPDIR/pet-swiftcache" -sdk "$SDK" scripts/cutout.swift -o /tmp/pet-cutout
```

The explicit `-sdk` selects an SDK that matches the compiler, and the writable
`-module-cache-path` avoids the blocked `~/.cache/clang`. Pick the highest installed
`MacOSX*.sdk` under the Xcode developer directory.

## Sizing

After cutting out, resize to twice the intended CSS display width with `sips`:

```bash
sips --resampleWidth 680 full.png --out still.png
```

Keep the original files untouched and store the cutouts in a separate directory such as
`assets/images/`.
