# DronePlan

Copyright (c) 2026 acche. All rights reserved.

This repository is public, but it is not open source. No reuse rights are
granted without written permission. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
Contribution rules are defined in [`CONTRIBUTING.md`](CONTRIBUTING.md).

DronePlan is a Windows-first waypoint planning and KMZ export tool for DJI RC 2 workflows.

The current repository focuses on one practical delivery path:

1. Plan waypoint missions on a desktop map
2. Generate DJI Fly compatible KMZ/WPML mission files
3. Replace an existing placeholder mission `.kmz` on Windows storage or microSD

## Current Scope

Implemented now:
- Manual waypoint planning on a desktop map
- Flight plan parameter editing
- KMZ/WPML generation in Rust
- Tauri desktop app for planning and export
- Windows-first RC 2 sync attempt via local helper, with KMZ export as fallback

Not implemented in this repository:
- Direct macOS to RC 2 sync
- DJI SDK based RC 2 communication
- Web application
- Mobile app
- AI mission planning module

## Why Windows-first

This project does not currently treat macOS as a valid RC 2 transfer platform.

The active delivery path is:

`Plan mission -> Generate KMZ -> Import through Windows or microSD -> Open in DJI Fly on RC 2`

See:
- [`docs/RC2_USB_Transfer.md`](docs/RC2_USB_Transfer.md)
- [`docs/RC2_Windows_Import.md`](docs/RC2_Windows_Import.md)

## Repository Layout

```text
DronePlan/
├── crates/droneplan-core/     # Rust core for models, geo, KMZ/WPML generation
├── apps/desktop/              # Tauri 2 + React desktop app
├── docs/                      # RC 2 workflow notes and constraints
├── .github/workflows/         # Windows CI build
└── AGENT.md                   # Project status and constraints for contributors
```

## Tech Stack

- Rust
- Tauri 2
- React
- TypeScript
- Leaflet

## Local Development

### Prerequisites

- Rust stable
- Node.js 20+
- npm

### Core library

```bash
cargo build -p droneplan-core
cargo test -p droneplan-core
```

### Desktop app

```bash
cd apps/desktop
npm install
npm run build
npm run tauri dev
```

### Desktop build

```bash
cd apps/desktop
npm run tauri build
```

## Current User Workflow

1. Create a placeholder mission in DJI Fly
2. Build the mission in DronePlan
3. Export or replace the placeholder `.kmz`
4. Copy/import via Windows or microSD
5. Re-open the mission in DJI Fly and verify preview before flight

## Known Gaps

- Windows direct sync is still heuristic and targets the latest placeholder mission
- Survey grid generation is not finished
- CI is limited to Windows build validation

## License

This repository is released as `UNLICENSED` in package metadata and is protected
by the repository-level terms in [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
