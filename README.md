# opus-tools

Standalone build of the [opus-tools](https://www.opus-codec.org/) command-line
programs — encode, decode and inspect [Opus](https://opus-codec.org/) audio.

[![CI](https://github.com/unpins/opus-tools/actions/workflows/opus-tools.yml/badge.svg)](https://github.com/unpins/opus-tools/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin opus-tools opusenc song.wav song.opus
unpin opus-tools opusdec song.opus song.wav
```

To install the programs onto your PATH:

```bash
unpin install opus-tools
```

`unpin install opus-tools` creates the `opusenc`, `opusdec`, and `opusinfo` commands.

## Programs

| command    | what it does                                          |
| ---------- | ----------------------------------------------------- |
| `opusenc`  | encode WAV / FLAC / AIFF / raw PCM to Opus            |
| `opusdec`  | decode (or play) Opus back to WAV / raw PCM           |
| `opusinfo` | show stream, header and tag info for an Opus file     |

`opusenc` reads FLAC and Ogg FLAC input, and `opusdec` can decode Opus from a
local file or an `http(s)://` URL.

## Build locally

```bash
nix build github:unpins/opus-tools
./result/bin/opusenc --version
```

Or run directly:

```bash
nix run github:unpins/opus-tools -- --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/opus-tools/releases) page has standalone binaries for manual download.

## Build notes

- One multicall binary holds all three tools. `opus-tools` is the canonical name
  (a busybox-style dispatcher); `opusenc`, `opusdec` and `opusinfo` dispatch on
  `argv[0]`. The tools share the heavy static archives — libopusenc / libopus /
  libFLAC / libogg, plus opusfile + opusurl (URL decode) — linked once, so the
  binary carries a single copy of each codec library.
- opus-tools is autotools and sets per-tool CFLAGS, so each shared source is
  compiled once per tool. The tools are folded together post-link by renaming
  each tool's `main` → `<tool>_main` (and prefixing its other globals) with
  `objcopy`, then linking the renamed objects against the shared archives; the
  exact archive list is read from each tool's real link command, captured with a
  verbose relink.
- **Windows** is built with mingw; the runtime is folded static in the multicall
  link, so the `.exe` has no companion DLLs.
- All three upstream man pages (`opusenc.1`, `opusdec.1`, `opusinfo.1`) are
  embedded in the binary.
