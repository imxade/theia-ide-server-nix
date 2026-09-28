# Independent Audit and Validation Report

## Audit Findings & Resolutions

1. **Bootstrap Fake Hashes**:
   - `source.nix` contained placeholder hashes (`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`).
   - Resolved by running `./scripts/update-sources` against upstream release `v1.75.0`.
   - Independently verified `srcHash` (`sha256-9L5moX4yAitAe9A7q2CL6Gu/nwK0bNbVasIoDqUuykg=`) and `yarnHash` (`sha256-QCeDdmFLCX7TI638TtIDoeYlIKivk7SmVEJO30p8TBE=`).

2. **Formatter Hang in Nix Flakes**:
   - Flake previously pointed `formatter` directly to `pkgs.nixfmt`.
   - When invoked via `nix fmt -- --check`, `nixfmt` read from standard input and hung indefinitely.
   - Fixed by wrapping `pkgs.nixfmt` in a `pkgs.writeShellApplication` script that automatically targets repository `.nix` files when called with flags or without arguments.

3. **Missing Host Dependencies in Updater**:
   - `scripts/update-sources` previously hard-required `jq`, which is not part of standard system utilities on clean NixOS hosts.
   - Fixed by providing fallback manifest parsing via `python3` (already available).
   - Added fail-safe `--extra-experimental-features 'nix-command flakes'` flags to all nix invocations.

4. **Electron Build Failure in theia-ide-product-ext**:
   - The product extension `theia-extensions/product` contained Electron-specific files in `src/electron-main/icon-contribution.ts` referencing Electron APIs not present in browser builds.
   - Fixed in `package.nix` `postPatch` by stripping `electronMain` from `theia-extensions/product/package.json` and removing `src/electron-main`. The browser frontend module compiles cleanly without Electron dependencies.

5. **Offline Yarn Mirror Invalidation via HOME Override**:
   - `package.nix` previously set `export HOME="$TMPDIR/home"` at the start of `buildPhase`, wiping out `~/.yarnrc` written by `yarnConfigHook` in `configurePhase`.
   - Fixed by exporting `HOME` in `preConfigure`, ensuring `yarnConfigHook` persists its offline mirror configuration throughout the derivation build.

6. **Puppeteer Postinstall Network Failure**:
   - Yarn install in `buildPhase` attempted to download browser binaries via puppeteer's postinstall script, failing in the network-isolated Nix sandbox.
   - Fixed by setting `PUPPETEER_SKIP_DOWNLOAD = "1"` and `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "1"`, and running `yarn --offline --pure-lockfile --ignore-scripts`.

7. **Dangling Symlink Failure in fixupPhase**:
   - Pruning root `node_modules` left broken symlinks in workspace `.bin` directories pointing to root `@theia/cli`, `tsc`, `tslint`, and `rimraf`.
   - Fixed by running `find . -xtype l -delete` prior to `fixupPhase`.

8. **Runtime Missing C++ Native Addon (`drivelist.node`)**:
   - Theia backend required `drivelist/build/Release/drivelist.node` at runtime.
   - Because `yarnConfigHook` skips install scripts, `drivelist` was never compiled, causing backend startup failure.
   - Fixed by adding `node-gyp` to `nativeBuildInputs` and compiling `drivelist` via `node-gyp rebuild` during `buildPhase`, placing the compiled binary in `applications/browser/node_modules/drivelist/build/Release/drivelist.node`.

9. **Deprecated Nixpkgs APIs**:
   - Replaced deprecated `xorg.libX11` with top-level `libx11`.

10. **GitHub Action Pinning**:
    - Pinned all GitHub Actions (`actions/checkout` and `cachix/install-nix-action`) to full immutable commit SHAs.

## Verification Checklist

- [x] Native Nix package builds with no Docker/Podman/container dependency
- [x] No Electron, Chromium, or GUI dependencies in closure or at runtime
- [x] Verified headless operation with `DISPLAY` and `WAYLAND_DISPLAY` unset
- [x] Verified localhost binding (`127.0.0.1`)
- [x] Real cryptographic SRI hashes in `source.nix`
- [x] Updater idempotence tested and verified
- [x] Stale metadata recovery tested and verified
- [x] Tag mutation fail-closed behavior tested and verified
- [x] ShellCheck clean across all scripts (exit code 0)
- [x] actionlint clean across all workflows (exit code 0)
- [x] `nix fmt -- --check` passes
- [x] `nix flake check --print-build-logs` passes
- [x] `aarch64-linux` package evaluation verified
- [x] `theia-ide-server` default build and localhost HTTP smoke test passed
- [x] `theia-ide-server-prod` production build and localhost HTTP smoke test passed
- [x] Memory constraint testing passed with `NODE_OPTIONS=--max-old-space-size=1024` and `512`
- [x] NixOS module evaluation and systemd service generation validated
