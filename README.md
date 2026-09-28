# theia-ide-server-nix

Native, automatically updated Nix packaging for the **browser/server distribution of Eclipse Theia IDE**.

This repository provides a standalone, container-free Nix package and NixOS module for Eclipse Theia IDE. It builds the official `applications/browser` target and runs its Node.js backend directly on Linux hosts without Docker, Podman, Electron, or a graphical desktop environment.

Current packaged version: **1.75.0** (upstream Git tag `v1.75.0`).

## Architecture & Design

```text
Nix-built Theia browser application
        ↓
Node.js 24 backend
        ↓
applications/browser/lib/backend/main.js
        ↓
127.0.0.1:<port>
        ↓
ordinary external web browser
```

- **Native Nix package**: Runs natively on Node.js 24. No Docker daemon, Podman, containerd, or container filesystem overhead.
- **Pure browser/server application**: No Electron, Chromium, X11 server, Wayland compositor, or graphical desktop dependencies required at runtime. Unsetting `DISPLAY` and `WAYLAND_DISPLAY` has zero impact on server operation.
- **Localhost-first security model**: Binds strictly to `127.0.0.1` by default. Does not expose `0.0.0.0` or open firewall ports automatically. If remote access is desired, place the backend behind an authenticated TLS reverse proxy (such as nginx or Caddy with OAuth/OIDC/mutual TLS).
- **Reproducible builds**: Fixed-output source hash (`fetchFromGitHub`) and Yarn offline dependency mirror (`fetchYarnDeps`). No runtime downloads.
- **Lean runtime closure**: Prunes development workspaces (Electron desktop, launcher, updater). Deliberately avoids bundling massive default VS Code extension packs, Java/Maven toolchains, and SSH daemons. Add language servers, compilers, and extensions separately when needed.
- **Supported platforms**: `x86_64-linux` (built and smoke-tested) and `aarch64-linux` (evaluated).

## Package Outputs

The flake provides two package variants:

1. **`theia-ide-server`** (default):
   Follows the lower-resource browser build mode used by upstream's browser image (`yarn browser build`). Optimizes for lower practical build-resource consumption while delivering the full browser IDE experience.
   - Closure size: **760.7 MiB** (includes Node.js 24, bash, git, and openssh).
   - Direct package size: **402 MiB**.

2. **`theia-ide-server-prod`**:
   Builds the optimized, minified production frontend bundle (`yarn browser build:prod`).
   - Closure size: **466.1 MiB**.
   - Direct package size: **113 MiB**.

## Measured Local Runtime Performance

Measurements taken on local Linux host with Node.js 24.20.0:

| Metric | `theia-ide-server` (default) | `theia-ide-server-prod` |
|---|---|---|
| Startup-to-HTTP-readiness | ~2.08 s | ~4.12 s |
| Primary backend RSS | ~237 MiB | ~274 MiB |
| Total process tree RSS | ~237 MiB | ~274 MiB |
| Child processes spawned | 0 | 0 |
| Memory-constrained test (`--max-old-space-size=1024`) | Passed (~2.09 s readiness) | Passed |
| Memory-constrained test (`--max-old-space-size=512`) | Passed (~2.09 s readiness) | Passed |

## Running Locally

### Direct execution with Nix Flakes

Run the default server:

```sh
mkdir -p "$HOME/theia-workspace"
nix run github:imxade/theia-ide-server-nix -- \
  "$HOME/theia-workspace" \
  --hostname=127.0.0.1 \
  --port=3000 \
  --no-cluster
```

Or run the minified production variant:

```sh
nix run github:imxade/theia-ide-server-nix#theia-ide-server-prod -- \
  "$HOME/theia-workspace" \
  --hostname=127.0.0.1 \
  --port=3000 \
  --no-cluster
```

Open `http://127.0.0.1:3000/` in any external web browser.

## NixOS Module

To run Theia as a systemd service on NixOS:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    theia-ide-server.url = "github:imxade/theia-ide-server-nix";
    theia-ide-server.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, theia-ide-server, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        theia-ide-server.nixosModules.default
        {
          services.theia-ide-server = {
            enable = true;
            host = "127.0.0.1";
            port = 3000;
            workspace = "/var/lib/theia-ide-server/workspace";

            # Optional: impose a V8 heap ceiling for resource-constrained hosts
            nodeOptions = "--max-old-space-size=1024";

            # Optional: use the minified production package
            # package = theia-ide-server.packages.x86_64-linux.theia-ide-server-prod;
          };
        }
      ];
    };
  };
}
```

The service runs under a dedicated `theia` system user and group with `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem = "strict"`, and explicitly restricted state directories. Loopback bind is enforced by default; firewall ports are not opened automatically.

## Downstream Flake Locking

This repository automatically discovers and builds new stable releases of Eclipse Theia IDE. However, downstream flakes that consume this repository will continue to pin an exact commit in their own `flake.lock`. Upstream updates here do not automatically override a downstream user's lock until `nix flake update theia-ide-server` is explicitly executed by the consumer.

## Automated Maintenance & CI

1. **Daily Update Workflow** (`.github/workflows/update.yml`):
   - Runs daily at 03:41 UTC.
   - Queries `eclipse-theia/theia-ide` for the newest stable semantic release `vX.Y.Z`.
   - Rejects drafts and prereleases.
   - Verifies root and browser application manifests.
   - Calculates exact `fetchFromGitHub` and `fetchYarnDeps` hashes.
   - Refuses mutation if an existing stable tag has changed hashes unexpectedly.
   - Runs linting (`shellcheck`, `actionlint`), formatting (`nix fmt -- --check`), flake check (`nix flake check`), build, and localhost HTTP smoke test.
   - Commits and pushes only when a new stable version is validated.

2. **Monthly Maintenance Workflow** (`.github/workflows/maintenance.yml`):
   - Runs on the 1st of each month at 06:17 UTC.
   - Updates the pinned `nixpkgs` input.
   - Validates package evaluation, builds, and runs the localhost smoke test.
   - Writes `.github/.last-maintenance` heartbeat only upon full validation success.

All GitHub Action references are pinned to immutable commit SHAs with semantic version comments.

## Local Validation

Run the complete local validator script:

```sh
./scripts/validate-local
```

Set `THEIA_TEST_PROD=1` to test both the default and production package variants:

```sh
THEIA_TEST_PROD=1 ./scripts/validate-local
```

## Limitations & Scope

- **Language Tools**: Compilers, SDKs (such as JDK, Rust, Go, Python), and language servers are intentionally not bundled into the IDE closure. Supply them in your system environment or development shells.
- **VS Code Extensions**: The official upstream `download:plugins` target (bundled Open VSX extension pack) is omitted to minimize package size. Extensions can be installed via the Theia UI or Open VSX registry.
- **Authentication**: Raw Theia does not provide built-in multi-user authentication. Do not bind to public interfaces without an authenticated HTTPS reverse proxy.
