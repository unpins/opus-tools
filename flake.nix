{
  description = "Standalone build of the opus-tools (Opus audio encoder/decoder/info)";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # opus-tools installs three CLIs — `opusenc` (encode WAV/FLAC/AIFF → Opus),
  # `opusdec` (decode/play Opus) and `opusinfo` (inspect Opus streams);
  # ./multicall.nix post-links them into one `opusenc` dispatcher binary with
  # `opusdec`/`opusinfo` as argv[0]-dispatch UNPIN_META aliases. Unlike the
  # CMake suites (flac/libwebp), opus-tools is autotools and its three programs
  # share most of their objects (opus_header / diag_range / picture /
  # unicode_support), so the per-tool link command is captured from a verbose
  # relink (the autotools analog of CMake's link.txt) and only the colliding
  # `main`s are renamed.
  #
  # Windows goes through mingw — the deps (libogg, libopus, FLAC, libopusenc,
  # opusfile) cross-compile cleanly and the runtime is folded static in the
  # multicall link so the .exe carries no companion DLLs.
  #
  # The canonical binary is named `opusenc` (the flagship tool); the unpins CI
  # portability/smoke checks resolve result/bin/<name>, but the package is
  # `opus-tools`, so binName pins the dispatcher to opusenc while keeping the
  # repo/flake name. All three upstream man pages ship, matching nixpkgs'
  # opus-tools man output, so no winManRoot curation is needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "opus-tools";
      binName = "opusenc";
      smoke = [ "--version" ];
      smokePattern = "opusenc.*opus-tools";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; opusTools = pkgs.pkgsStatic.opus-tools; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; opusTools = (ulib.mingwStaticCross pkgs).opus-tools; };
    };
}
