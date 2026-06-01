{
  description = "Standalone build of the opus-tools (Opus audio encoder/decoder/info)";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # opus-tools installs three CLIs — `opusenc` (encode WAV/FLAC/AIFF → Opus),
  # `opusdec` (decode/play Opus) and `opusinfo` (inspect Opus streams);
  # ./multicall.nix post-links them into one `opus-tools` dispatcher binary with
  # `opusenc`/`opusdec`/`opusinfo` as argv[0]-dispatch UNPIN_META aliases. Unlike
  # the CMake suites (flac/libwebp), opus-tools is autotools and its three
  # programs share most of their objects (opus_header / diag_range / picture /
  # unicode_support), so the per-tool link command is captured from a verbose
  # relink (the autotools analog of CMake's link.txt) and only the colliding
  # `main`s are renamed.
  #
  # Windows goes through mingw — the deps (libogg, libopus, FLAC, libopusenc,
  # opusfile) cross-compile cleanly and the runtime is folded static in the
  # multicall link so the .exe carries no companion DLLs.
  #
  # The canonical binary is named `opus-tools` (the package name), matching the
  # unpins/action-build contract that result/bin/<package_name> is the binary it
  # portability/smoke-checks — so binName is left at its default (= name) and the
  # real tool names (opusenc/opusdec/opusinfo) are the aliases. The bare
  # `opus-tools` dispatcher falls through to the flagship encoder, so
  # `opus-tools --version` prints opusenc's banner (matching smokePattern). All
  # three upstream man pages ship, matching nixpkgs' opus-tools man output, so no
  # winManRoot curation is needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "opus-tools";
      smoke = [ "--version" ];
      smokePattern = "opusenc.*opus-tools";
      # On native aarch64-darwin, nixpkgs writes meson's `cpu_family = arm64`
      # (transitional uname), which libopus' meson.build doesn't canonicalize to
      # `aarch64`, so its NEON intrinsics branch is skipped and the build errors
      # ("no intrinsics support for arm64"). nix-lib carries the one-line source
      # fix as `nativeFixes.libopus`; opus-tools doesn't depend on libopus
      # directly — it comes via libopusenc + opusfile — so inject the patched
      # libopus into both. The patch is an inert extra match-list entry on every
      # other platform, so it's applied unconditionally.
      build = pkgs:
        let
          ps = pkgs.pkgsStatic;
          fixedOpus = ulib.nativeFixes.libopus ps;
          opusTools = ps.opus-tools.override {
            libopusenc = ps.libopusenc.override { libopus = fixedOpus; };
            opusfile = ps.opusfile.override { libopus = fixedOpus; };
          };
        in
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs opusTools; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; opusTools = (ulib.mingwStaticCross pkgs).opus-tools; };
    };
}
