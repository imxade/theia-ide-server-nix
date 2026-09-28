# theia-ide-server-nix

Native, automatically updated Nix packaging for the **browser/server build of Eclipse Theia IDE**.

This repository intentionally does **not** use Docker and does not package the Electron desktop application. It builds the official `applications/browser` target and runs its Node.js backend directly on NixOS/Linux.

## Goals

- Native Node.js Theia backend, no Docker daemon/container overhead.
- No Electron/desktop GUI in the package.
- Loopback-only server by default (`127.0.0.1:3000`).
- Reproducible source and Yarn dependency hashes.
- Automatic stable-release updates with local HTTP smoke testing before commits.
- x86_64-linux and aarch64-linux.
- Default lower-build-resource browser bundle matching upstream's current browser-container build, with an optional minified production output.

The default package deliberately skips upstream `download:plugins`. The official browser app itself is complete, but large bundled VS Code extension packs, Java, Maven, and an SSH server are not included. Add language runtimes or VS Code plugins separately when you actually need them.

## Bootstrap

The distributed bootstrap archive contains fake hashes in `source.nix`. On a NixOS machine, run:

```sh
nix flake lock
./scripts/update-sources
./scripts/validate-local
```

Do not publish the bootstrap fake hashes.

## Run locally

```sh
mkdir -p "$HOME/theia-workspace"
nix run .#theia-ide-server -- \
  "$HOME/theia-workspace" \
  --hostname=127.0.0.1 \
  --port=3000 \
  --no-cluster
```

Open `http://127.0.0.1:3000/` from your browser.

The default package intentionally follows the lower-resource build mode used by upstream's current browser image. For a minified production frontend, use:

```sh
nix run .#theia-ide-server-prod -- \
  "$HOME/theia-workspace" \
  --hostname=127.0.0.1 \
  --port=3000 \
  --no-cluster
```

Set `THEIA_TEST_PROD=1` when running `./scripts/validate-local` if you also want to build and smoke-test the production variant locally.

## NixOS service

```nix
{
  inputs.theia-ide-server.url = "github:YOUR_ACCOUNT/theia-ide-server-nix";

  outputs = { nixpkgs, theia-ide-server, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        theia-ide-server.nixosModules.default
        ({ ... }: {
          services.theia-ide-server = {
            enable = true;
            host = "127.0.0.1";
            port = 3000;
            # nodeOptions = "--max-old-space-size=1024";
          };
        })
      ];
    };
  };
}
```

The module deliberately defaults to loopback and does not open the firewall. If you expose Theia remotely, put it behind an authenticated TLS reverse proxy rather than publishing the raw IDE backend directly.

## Local validation

```sh
./scripts/validate-local
```

Validation includes ShellCheck, actionlint, Nix formatting/evaluation, the default server build, and a native localhost smoke test that starts Theia with a temporary workspace and verifies that `http://127.0.0.1:<ephemeral-port>/` responds.

The smoke test uses no Docker and does not require a graphical session.

## Automatic updates

The scheduled updater:

1. discovers the highest stable `vX.Y.Z` tag in `eclipse-theia/theia-ide`;
2. verifies the tag's root and browser application versions;
3. calculates the exact `fetchFromGitHub` source hash;
4. calculates the exact `fetchYarnDeps` hash;
5. refuses mutation of an already recorded stable tag;
6. builds and locally smoke-tests the native server;
7. commits only after validation passes.

The update job runs daily. Monthly maintenance refreshes the pinned nixpkgs input and records a successful heartbeat only after validation.

A downstream flake still pins this repository in its own `flake.lock`. Automatic updates here do not override a consumer's intentional lock.

## Resource boundary

Removing Docker avoids a second daemon/container filesystem and lets the service share the host's Nix store. It does **not** make Theia itself tiny: Theia IDE is a substantial Node/browser application. The default package avoids the largest optional pieces (Electron, bundled VS Code plugins, JDK, Maven, SSH server), and `services.theia-ide-server.nodeOptions` can be used to impose a V8 heap ceiling if necessary.
