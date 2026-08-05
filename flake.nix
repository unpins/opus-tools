{
  description = "opus-tools (Opus audio encoder/decoder/info) as a single self-contained binary";

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
  # real tool names (opusenc/opusdec/opusinfo) are the aliases. All
  # three upstream man pages ship, matching nixpkgs' opus-tools man output, so no
  # winManRoot curation is needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "opus-tools";
      smoke = [ "--unpin-program=opusenc" "--version" ];
      smokePattern = "opusenc.*opus-tools";

      # Build via the unpin-llvm engine + emit a bitcode multicall module: the
      # engine compiles opus-tools to bitcode and the standalone self-folds
      # opusenc/opusdec/opusinfo into one `opus-tools` binary, on Linux and darwin
      # alike. Windows (mingw, no engine → native objects) goes through
      # windowsBuild's objcopy fold instead — objcopy cannot rewrite bitcode, so
      # ./multicall.nix must NOT run over an engine build. Pure C — no
      # requires.cxx.
      engine = "unpin-llvm";
      multicall = {
        programs = [
          { name = "opusenc"; }
          { name = "opusdec"; }
          { name = "opusinfo"; }
        ];
      };
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
          # `.override` swaps only the named deps; opus-tools keeps the stdenv it
          # already carries — the engine stdenv (enginePkgs swaps
          # pkgsStatic.opus-tools), so the link-capture sidecars still get written.
          opusTools = ps.opus-tools.override {
            libopusenc = ps.libopusenc.override { libopus = fixedOpus; };
            opusfile = ps.opusfile.override { libopus = fixedOpus; };
          };
        in
        # engine path: apps → bitcode → selfFold. opus-tools' configure runs
        # AC_CHECK_PROG(pkg-config) for the *unprefixed* name; under the static
        # stdenv the wrapper is host-prefixed, so HAVE_PKG_CONFIG=no and the FLAC
        # probe falls back to a bare `-lFLAC` test that can't resolve libogg
        # statically ("FLAC 1.1.3 required"). Force the flag so every
        # PKG_CHECK_MODULES takes the pkg-config path. (multicall.nix does the
        # same on the windows fold path.)
        opusTools.overrideAttrs (o: {
          preConfigure = (o.preConfigure or "") + ''
            export HAVE_PKG_CONFIG=yes
          '';
          doCheck = false;
          doInstallCheck = false;
        });
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; opusTools = (ulib.mingwStaticCross pkgs).opus-tools; };
    };
}
