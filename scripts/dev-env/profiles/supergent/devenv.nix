{ pkgs, ... }:

{
  env = {
    USE_DEVENV = "1";
    PORTLESS = "1";
    SUPERGENT_BASE_URL = "http://supergent.localhost:1355";
    SUPERGENT_LAB_BASE_URL = "http://lab.supergent.localhost:1355";
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
    shellcheck
  ];

  enterShell = ''
    echo "Supergent devenv shell active."
    echo "Run: scripts/dev-supergent.sh"
  '';
}
