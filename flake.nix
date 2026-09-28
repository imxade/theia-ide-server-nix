{
  description = "Automatically updated native Nix package for the Eclipse Theia IDE browser server";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPackages =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          source = import ./source.nix;
          server = pkgs.callPackage ./package.nix {
            inherit source;
            production = false;
          };
          prod = pkgs.callPackage ./package.nix {
            inherit source;
            production = true;
          };
        in
        {
          theia-ide-server = server;
          theia-ide-server-prod = prod;
          default = server;
        };
    in
    {
      packages = forAllSystems mkPackages;

      apps = forAllSystems (
        system:
        let
          p = mkPackages system;
        in
        {
          theia-ide-server = {
            type = "app";
            program = "${p.theia-ide-server}/bin/theia-ide-server";
            meta.description = "Run Eclipse Theia IDE as a native browser server";
          };
          theia-ide-server-prod = {
            type = "app";
            program = "${p.theia-ide-server-prod}/bin/theia-ide-server";
            meta.description = "Run the minified production Theia browser server";
          };
          default = self.apps.${system}.theia-ide-server;
        }
      );

      overlays.default = final: _prev: {
        theia-ide-server = self.packages.${final.system}.theia-ide-server;
        theia-ide-server-prod = self.packages.${final.system}.theia-ide-server-prod;
      };

      nixosModules.default = { ... }: {
        imports = [ ./nix/module.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };
      nixosModules.theia-ide-server = self.nixosModules.default;

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          p = mkPackages system;
        in
        {
          package = p.theia-ide-server;
          source-metadata =
            pkgs.runCommand "check-theia-source-metadata"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.nix
                ];
              }
              ''
                export NIX_STATE_DIR=$TMPDIR
                THEIA_REPO_ROOT=${self} ${pkgs.bash}/bin/bash ${./scripts/check-sources}
                touch $out
              '';
          scripts =
            pkgs.runCommand "check-theia-shell-scripts" { nativeBuildInputs = [ pkgs.shellcheck ]; }
              ''
                shellcheck ${./scripts/check-sources} ${./scripts/update-sources} ${./scripts/smoke-test} ${./scripts/validate-local}
                touch $out
              '';
          workflows = pkgs.runCommand "check-theia-workflows" { nativeBuildInputs = [ pkgs.actionlint ]; } ''
            actionlint -shellcheck= ${./.github/workflows/ci.yml} ${./.github/workflows/update.yml} ${./.github/workflows/maintenance.yml}
            touch $out
          '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              actionlint
              curl
              git
              jq
              nixfmt
              shellcheck
            ];
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "nix-formatter";
          runtimeInputs = [
            pkgs.nixfmt
            pkgs.findutils
          ];
          text = ''
            args=()
            files=()
            for arg in "$@"; do
              if [[ "$arg" == -* ]]; then
                args+=("$arg")
              else
                files+=("$arg")
              fi
            done
            if [ ''${#files[@]} -eq 0 ]; then
              find . -name '*.nix' -not -path '*/.*' -exec nixfmt "''${args[@]}" {} +
            else
              nixfmt "$@"
            fi
          '';
        }
      );
    };
}
