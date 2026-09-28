{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  yarnConfigHook,
  nodejs,
  yarn,
  python3,
  pkg-config,
  makeWrapper,
  bashInteractive,
  gitMinimal,
  openssh,
  libsecret,
  libxkbfile,
  xorg,
  source,
  production ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = if production then "theia-ide-server-prod" else "theia-ide-server";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "eclipse-theia";
    repo = "theia-ide";
    rev = "v${source.version}";
    hash = source.srcHash;
  };

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = finalAttrs.src + "/yarn.lock";
    hash = source.yarnHash;
  };

  nativeBuildInputs = [
    yarnConfigHook
    nodejs
    yarn
    python3
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    libsecret
    libxkbfile
    xorg.libX11
  ];

  strictDeps = true;
  dontYarnBuild = true;
  dontYarnInstall = true;

  # Native Node addons must build against the Node runtime supplied by Nix.
  npm_config_nodedir = nodejs;

  # The browser target does not need Electron downloads.
  ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  postPatch = ''
    # Resource-conscious native build: keep only the official browser application
    # and the product extension as Yarn workspaces. This avoids installing/building
    # the Electron, updater, launcher, and next-channel workspaces.
    python3 - <<'PY'
import json
from pathlib import Path
p = Path("package.json")
data = json.loads(p.read_text())
data["workspaces"] = ["applications/browser", "theia-extensions/product"]
p.write_text(json.dumps(data, indent=2) + "\n")
PY
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    # Match the upstream browser build, but deliberately skip download:plugins.
    # That avoids bundling the large VS Code extension pack and language toolchains.
    yarn --offline build:extensions

    ${if production then
      ''yarn --offline browser build:prod''
    else
      ''yarn --offline browser build''}

    # Upstream performs a second install after generating the application so that
    # applications/browser carries the runtime dependency layout it needs.
    yarn --offline --pure-lockfile

    # Follow the upstream browser image cleanup strategy to avoid shipping root
    # development dependencies. Keep the generated browser application and the
    # product extension only.
    yarn autoclean --init
    printf '%s\n' '*.ts' '*.ts.map' '*.spec.*' >> .yarnclean
    yarn autoclean --force

    rm -rf \
      .git \
      node_modules \
      applications/electron \
      applications/electron-next \
      theia-extensions/launcher \
      theia-extensions/updater

    test -f applications/browser/lib/backend/main.js
    test -d applications/browser/node_modules

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/theia-ide" "$out/bin"
    cp -a . "$out/share/theia-ide/"

    makeWrapper ${nodejs}/bin/node "$out/bin/theia-ide-server" \
      --add-flags "$out/share/theia-ide/applications/browser/lib/backend/main.js" \
      --set-default NODE_ENV production \
      --set-default USE_LOCAL_GIT true \
      --set-default SHELL ${bashInteractive}/bin/bash \
      --prefix PATH : ${lib.makeBinPath [ bashInteractive gitMinimal openssh ]}

    runHook postInstall
  '';

  postFixup = ''
    # Guard against accidentally retaining the desktop application in the closure.
    test ! -e "$out/share/theia-ide/applications/electron"
    test ! -e "$out/share/theia-ide/applications/electron-next"
  '';

  passthru = {
    updateScript = ./scripts/update-sources;
  };

  meta = {
    description = "Native browser/server distribution of Eclipse Theia IDE";
    homepage = "https://github.com/eclipse-theia/theia-ide";
    license = lib.licenses.mit;
    mainProgram = "theia-ide-server";
    platforms = lib.platforms.linux;
  };
})
