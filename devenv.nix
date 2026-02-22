{ pkgs, ... }:

{
  env = {
    USE_DEVENV = "1";
    PORTLESS = "1";
    SUPERLOOP_UI_BASE_URL = "http://superloop-ui.localhost:1355";
  };

  packages = with pkgs; [
    bash
    coreutils
    git
    jq
    gnugrep
    gnused
    nodejs_20
    bun
    python3
    bats
    shellcheck
  ];

  scripts.dev-env-doctor.exec = "bash scripts/dev-env-doctor.sh";

  enterShell = ''
    echo "Superloop devenv shell active."
    echo "Run: scripts/dev-env-doctor.sh"
  '';
}
