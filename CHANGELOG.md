# Changelog

## [Unreleased]

### Fixed

- `opusdec https://…` failed certificate verification on Fedora, RHEL,
  openSUSE, macOS and every Windows machine: the binary only looked for CA
  certificates where Debian and Ubuntu keep them. It now uses the host's CA
  certificates wherever the common systems keep them, and falls back to
  Mozilla's root certificates built into the binary on a host that has none.
  On Windows the built-in roots are combined with the system's trusted root
  store, leaving out certificates Windows marks as untrusted, and nothing
  under `C:\ssl` is trusted. `SSL_CERT_FILE` and `SSL_CERT_DIR` still take
  precedence.

### Added

- On Linux, hostnames in `opusdec` URLs now resolve on a machine whose DNS
  resolver is missing or unreachable — Android, or a container with no
  `/etc/resolv.conf` — once you point unpins at a name server.
