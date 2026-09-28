# Publication checklist

The archive is intentionally a bootstrap repository. Before publication on a real NixOS host:

- run `./scripts/update-sources` and ensure no fake hashes remain;
- create `flake.lock`;
- verify current stable upstream tag independently;
- verify source and Yarn hashes independently;
- pin every GitHub Action `uses:` reference to a full immutable commit SHA;
- run ShellCheck and actionlint;
- run `nix flake check --print-build-logs`;
- build and smoke-test `theia-ide-server`; optionally validate `theia-ide-server-prod` with `THEIA_TEST_PROD=1`;
- run `./scripts/smoke-test` against localhost;
- measure/report startup time and idle RSS on the local host;
- confirm the installed package has no Electron application and no Docker runtime dependency;
- test the NixOS module locally if the machine can rebuild/switch a test configuration;
- test updater idempotence and stable-tag mutation fail-closed behavior;
- pin Actions, publish, then verify hosted CI and scheduled workflow no-change paths.
