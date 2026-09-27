# Apple Music Remote — Graphic Assets & Visual Resources

Official visual design assets and Xcode Asset Catalog for Apple Music Remote (macOS & iOS).

---

## 🎨 Asset Catalog Structure (`Assets.xcassets`)

- **`AppIcon.appiconset`**: Complete cross-platform App Icon assets supporting:
  - iOS / iPadOS (iPhone, iPad, Marketing 1024x1024)
  - macOS Big Sur+ HIG (16x16, 32x32, 128x128, 256x256, 512x512 @1x/@2x)
- **`AccentColor.colorset`**: Dynamic Apple Music Pink (`#FA233B` / `#FF2D55`) adapting to Light/Dark mode.
- **`Colors/`**: Brand color palette:
  - `BrandPink.colorset` (`#FA233B`)
  - `BrandPurple.colorset` (`#7928CA`)
  - `BrandCyan.colorset` (`#00F2FE`)
  - `BrandGold.colorset` (`#FFD700`)
  - `GlassBackground.colorset` (`#0C0A18`)
  - `LiveBadge.colorset` (`#FF2D55`)
  - `SurfaceDark.colorset` (`#171720`)
- **`StationCovers/`**: Curated Station Covers (1000x1000 master PNG & vector SVG):
  - `CoverPersonal.imageset` — "Моя станция" / Personal Station
  - `CoverDiscovery.imageset` — "Станция открытий" / Discovery Station
  - `CoverAppleMusic1.imageset` — Apple Music 1 Live
  - `CoverHits.imageset` — Apple Music Hits
  - `CoverCountry.imageset` — Apple Music Country
  - `CoverChill.imageset` — Chill & Lo-Fi
  - `CoverPop.imageset` — Pop Hits Radio
  - `CoverRock.imageset` — Rock Classics
  - `CoverHipHop.imageset` — Hip-Hop & Rap
  - `CoverElectronic.imageset` — Dance & Electronic
  - `CoverDeepHouse.imageset` — Deep House & Melodic
  - `CoverJazz.imageset` — Jazz & Blues

---

## 📱 Icon Formats & Master Files

- **`AppIconMaster.svg`**: Master full-bleed vector icon (1024x1024)
- **`AppIconMac.svg`**: Master macOS squircle vector icon with standard Big Sur HIG geometry (1024x1024)
- **`Icons/AppIconMaster-1024.png`**: High-resolution 1024x1024 raster icon
- **`Icons/iOS/`**: Complete set of iOS raster PNGs (@1x, @2x, @3x)
- **`Icons/macOS/`**: Complete set of macOS raster PNGs and compiled `AppIcon.icns`
- **`StationCovers/`**: Individual 1000x1000 SVGs and rendered PNGs for all 12 stations

---

## 🛠 Asset Generation Pipeline

To regenerate all raster PNGs and Asset Catalogs from vector SVGs:
```bash
python3 /Users/kirill/Documents/projects/amr/SharedAssets/generate_assets.py
```
