# Brand assets

The app icon is derived from the official [Argo project icon](https://github.com/cncf/artwork/tree/master/projects/argo/icon/color) in the [CNCF artwork repository](https://github.com/cncf/artwork).

The menu bar icon uses the official monochrome Argo icon from the [CNCF artwork black/white variants](https://github.com/cncf/artwork/tree/master/projects/argo/icon).

Argo CD is part of the CNCF Argo project. Use of the logo is subject to the [CNCF trademark and logo policy](https://www.cncf.io/brand-guidelines/).

## Source files

- `argo-icon.svg`: color app icon (Dock/Finder)
- `argocd-menubar.svg`: black template icon (menu bar)
- `argocd-menubar-white.svg`: white variant (reference only)

## Built assets

The app ships pre-rendered PNGs in `Assets.xcassets` (`AppIcon.appiconset`, `MenuBarIcon.imageset`). You do not need any extra tooling to build the app. Clone the repository and open it in Xcode.

To regenerate icons after changing an SVG (maintainers only):

```bash
./scripts/generate-app-icon.sh
```

Requires [ImageMagick](https://imagemagick.org/) (`magick` on `PATH`). Commit the updated PNGs along with any SVG changes.
