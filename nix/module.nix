{ config, lib, pkgs, ... }:

let
  cfg = config.services.theia-ide-server;
  inherit (lib) mkEnableOption mkIf mkOption types;
  args = [
    cfg.workspace
    "--hostname=${cfg.host}"
    "--port=${toString cfg.port}"
    "--no-cluster"
  ] ++ cfg.extraArgs;
  escapedArgs = lib.escapeShellArgs args;
in
{
  options.services.theia-ide-server = {
    enable = mkEnableOption "Eclipse Theia IDE browser server";

    package = mkOption {
      type = types.package;
      default = pkgs.theia-ide-server or (throw "services.theia-ide-server.package must be set when the overlay is not imported");
      description = "The native Theia IDE server package to run.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address on which Theia listens. Keep loopback unless protected by an authenticated reverse proxy.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "TCP port on which Theia listens.";
    };

    workspace = mkOption {
      type = types.str;
      default = "/var/lib/theia-ide-server/workspace";
      description = "Default workspace opened by the server.";
    };

    user = mkOption {
      type = types.str;
      default = "theia";
      description = "User account used by the service.";
    };

    group = mkOption {
      type = types.str;
      default = "theia";
      description = "Group used by the service.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional arguments passed to the Theia backend.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables for Theia.";
    };

    nodeOptions = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "--max-old-space-size=1024";
      description = "Optional NODE_OPTIONS, useful for imposing a V8 heap ceiling on constrained hosts.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the configured TCP port in the NixOS firewall.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.openFirewall || cfg.host != "127.0.0.1";
        message = "services.theia-ide-server.openFirewall is unnecessary while binding only to 127.0.0.1";
      }
    ];

    users.groups = mkIf (cfg.group == "theia") {
      theia = { };
    };

    users.users = mkIf (cfg.user == "theia") {
      theia = {
        isSystemUser = true;
        group = cfg.group;
        home = "/var/lib/theia-ide-server";
        createHome = true;
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.theia-ide-server = {
      description = "Eclipse Theia IDE browser server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = cfg.environment // {
        HOME = "/var/lib/theia-ide-server";
        XDG_CONFIG_HOME = "/var/lib/theia-ide-server/config";
        XDG_DATA_HOME = "/var/lib/theia-ide-server/data";
      } // lib.optionalAttrs (cfg.nodeOptions != null) {
        NODE_OPTIONS = cfg.nodeOptions;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "theia-ide-server";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/theia-ide-server";
        ExecStartPre = "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${cfg.workspace}";
        ExecStart = "${cfg.package}/bin/theia-ide-server ${escapedArgs}";
        Restart = "on-failure";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/theia-ide-server" cfg.workspace ];
        UMask = "0077";
      };
    };
  };
}
