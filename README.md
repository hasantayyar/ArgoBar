# ArgoBar

Mac menu bar app for ArgoCD sync, health, and deployment image at a glance.

Native macOS app that polls your ArgoCD server and shows watched applications with sync status, health, destination, last sync time, and the primary container image from the first Rollout or Deployment. Authentication reuses the token from `argocd login`. The app does not implement its own login flow.

## Features

- Menu bar icon with aggregate status (healthy / warning / error / unauthenticated)
- Per-app sync and health indicators
- Last sync time from operation or reconcile timestamp
- Primary workload image (`container:tag`) from the first Rollout or Deployment manifest
- Click a row to open the app in the ArgoCD web UI
- Settings for server, project/namespace, watched apps, and poll interval
- Watch all apps in a project or a specific list
- **Multiple ArgoCD endpoints**, each with its own server, projects, and app selection

## Prerequisites

- macOS 14+
- Xcode 15+ (full Xcode, not Command Line Tools only) for building from source
- `argocd` CLI installed and logged in to each server you want to watch:

```bash
brew install argocd
argocd login <your-argocd-server>
```

Add flags your instance requires, for example `--grpc-web` or `--sso`.

Tokens expire periodically. When expired, the menu shows the login command to run again.

## Build and run

### Option A: Xcode (recommended)

```bash
open ArgoCDMenubar.xcodeproj
```

Select the **ArgoCDMenubar** scheme, then **Product → Run** (⌘R).

### Option B: xcodebuild

```bash
xcodebuild -project ArgoCDMenubar.xcodeproj -scheme ArgoCDMenubar -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/ArgoCDMenubar-*/Build/Products/Debug/ArgoCDMenubar.app
```

### Option C: Swift Package + app bundle script

```bash
./scripts/build-app.sh
open ArgoCDMenubar.app
```

## Usage

1. Launch the app. A menu bar icon appears (no Dock icon).
2. If not authenticated, the menu shows the `argocd login` command to run in Terminal.
3. Open **Settings…** to configure:
   - One or more **endpoints** (ArgoCD servers) in the sidebar
   - Per endpoint: display name, server host, enabled toggle, auth status
   - **Watch groups** per endpoint. Each group watches one ArgoCD project or namespace filter.
   - Per group: all apps or a selected app list; discover apps in project
   - Global poll interval (30-300 seconds, default: 60)
4. Click app rows to open them in the ArgoCD web UI (uses the correct server per app).

## Architecture

| Component | Role |
|---|---|
| `TokenReader` | Reads bearer token from `~/.config/argocd/config`, validates JWT expiry |
| `ArgoCDClient` | Lists apps and fetches Rollout/Deployment manifests via REST API |
| `AppSettings` | Endpoints, watch groups, poll interval (persisted as JSON) |
| `StatusStore` | Parallel polling across endpoints, grouped menu sections |
| `MenuContentView` | Menu dropdown grouped by endpoint |
| `SettingsView` | Sidebar endpoint list + detail editor |

### API usage

- List apps: `GET /api/v1/applications?projects={project}`
- Workload manifest: `GET /api/v1/applications/{app}/resource?namespace=&resourceName=&kind=&group=&version=`

Image extraction picks the first Rollout or Deployment in `status.resources`, fetches its manifest, and reads the primary container image (skipping common sidecar container names).

## Sample CLI helper

[`scripts/list-argocd-apps.sh`](scripts/list-argocd-apps.sh) is an optional example script for listing applications from the terminal. Useful when debugging auth or comparing API output with the app. Not required to build or run the menubar app.

```bash
./scripts/list-argocd-apps.sh --server argocd.example.com --project default
ARGOCD_SERVER=argocd.example.com ./scripts/list-argocd-apps.sh --json
```

Run `./scripts/list-argocd-apps.sh --help` for options. Log in with `argocd login` first, or pass `--login` and set `ARGOCD_LOGIN_ARGS` if your instance needs extra flags.

## Project layout

```
ArgoCDMenubar/
  ArgoCDMenubarApp.swift       # MenuBarExtra + Settings window
  Models/                      # AppStatus, AppSettings, ArgoCDEndpoint
  Services/                    # TokenReader, ArgoCDClient, StatusStore
  Views/                       # MenuContentView, SettingsView, MenuBarIconView
scripts/
  build-app.sh
  generate-app-icon.sh
  list-argocd-apps.sh          # optional sample/debug helper
```

## License

MIT. See [LICENSE](LICENSE).

## Brand assets

Argo logos are derived from the [CNCF Argo project artwork](https://github.com/cncf/artwork/tree/master/projects/argo). See [ArgoCDMenubar/Resources/Brand/ATTRIBUTION.md](ArgoCDMenubar/Resources/Brand/ATTRIBUTION.md).
