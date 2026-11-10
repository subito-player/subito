# Subito logo

- `subito-dark.svg`: the app icon (light italic s, GO-green dot, dark tile). Default.
- `subito-light.svg`: the same on cream, for dark backgrounds and the macOS dark appearance.
- `subito-lockup-dark.svg` / `subito-lockup-light.svg`: icon plus the italic name, for the README header (light and
  dark mode). The letters are outlines shaped with HarfBuzz, so the font's own spacing is kept.
- `../AppIcon.icon`: Icon Composer source of the app icon (default = dark tile, dark appearance = cream tile);
  `make app` compiles it with `actool` into `Assets.car` (macOS 26) and `AppIcon.icns` (macOS 14 and 15).

The s is Playfair Display Italic at weight 800 (SIL Open Font License 1.1, The Playfair Display Project Authors),
converted to outlines, so nothing depends on the font being installed.
