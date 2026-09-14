# opus-tools

The [opus-tools](https://www.opus-codec.org/) command-line programs — encode, decode and inspect [Opus](https://opus-codec.org/) audio. A single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/opus-tools/actions/workflows/opus-tools.yml/badge.svg)](https://github.com/unpins/opus-tools/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install opus-tools`.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin opus-tools --unpin-program=opusenc song.wav song.opus
unpin opus-tools --unpin-program=opusdec song.opus song.wav
```

Or install them and call each by name, which is usually what you want:

```bash
unpin install opus-tools
opusenc song.wav song.opus
```

`unpin install opus-tools` creates the `opusenc`, `opusdec`, and `opusinfo` commands.

## Programs

| command    | what it does                                          |
| ---------- | ----------------------------------------------------- |
| `opusenc`  | encode WAV / FLAC / AIFF / raw PCM to Opus            |
| `opusdec`  | decode Opus back to WAV / raw PCM                     |
| `opusinfo` | show stream, header and tag info for an Opus file     |

`opusenc` reads FLAC and Ogg FLAC input, and `opusdec` can decode Opus from a
local file or an `http(s)://` URL.

## Man pages

All three upstream man pages are embedded in the binary — read them with
`unpin man opus-tools <program>`, e.g. `unpin man opus-tools opusenc`.

## Build locally

```bash
nix build github:unpins/opus-tools
./result/bin/opus-tools --unpin-program=opusenc --version
```

Or run directly:

```bash
nix run github:unpins/opus-tools -- --unpin-program=opusenc --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/opus-tools/releases) page has standalone binaries for manual download.

## Build notes

- One binary at `bin/opus-tools` carries all three programs. `unpin install
  opus-tools` puts `opusenc`, `opusdec` and `opusinfo` on your PATH; from the
  bare binary, pick one with `--unpin-program=<program>`. It is not a
  positional argument.
- **HTTPS:** `opusdec https://…` checks the server against the host's CA
  certificates, or against Mozilla's root certificates built into the binary
  when the host has none (a minimal container, for example). On Windows the
  built-in roots are combined with the system's trusted root store.
- Every build encodes, inspects and decodes a real stream before it is
  accepted, through files and through standard input/output alike.
- **Windows:** a single `.exe` with no companion DLLs.
