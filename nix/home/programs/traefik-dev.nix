{ ... }:

{
  # traefik-dev: dev-gateway reverse proxy config + compose file. The
  # compose file is launched via the `wt traefik up` workflow.

  xdg.configFile."traefik-dev/traefik.yml".source =
    ../../../common/traefik-dev/.config/traefik-dev/traefik.yml;
  xdg.configFile."traefik-dev/compose.yml".source =
    ../../../common/traefik-dev/.config/traefik-dev/compose.yml;
}
