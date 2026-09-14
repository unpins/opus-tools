{
  description = "opus-tools (Opus audio encoder/decoder/info) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # opus-tools installs three CLIs — `opusenc` (encode WAV/FLAC/AIFF → Opus),
  # `opusdec` (decode/play Opus) and `opusinfo` (inspect Opus streams); nix-lib
  # folds them into one `opus-tools` dispatcher binary with
  # `opusenc`/`opusdec`/`opusinfo` as argv[0]-dispatch UNPIN_META aliases.
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
      # opus-tools' configure runs AC_CHECK_PROG(pkg-config) for the *unprefixed*
      # name; under a static/cross stdenv the wrapper is host-prefixed, so
      # HAVE_PKG_CONFIG=no and the FLAC probe falls back to a bare `-lFLAC` test
      # that can't resolve libogg statically ("FLAC 1.1.3 required"). Force the
      # flag so every PKG_CHECK_MODULES takes the pkg-config path. AC_CHECK_PROG
      # is a no-op when the var is preset.
      #
      # libao is dropped on every target: nixpkgs still lists it, but opus-tools
      # 0.2 has no AO reference left in Makefile.am/configure.ac (opusdec plays
      # through OSS on Linux and waveOut on Windows), so it never linked — it was
      # only built, for nothing.
      #
      # nixpkgs' installCheck is a versionCheckHook on `opusenc`; it is replaced
      # by a real round trip, run wherever the build host can execute the result
      # (native, i686-from-x86_64, darwin — not the crosses, not mingw):
      #   - raw PCM -> opusenc -> opusinfo must report 2 channels and exactly 1 s;
      #   - opusdec must give back all 192000 bytes, as raw and as WAV;
      #   - the same encode and decode through stdin/stdout ('-') must be
      #     byte-identical to the file ones (--serial pins the Ogg serial number
      #     opusenc otherwise randomizes) — the path a Windows CRT left in text
      #     mode corrupts and no file argument covers.
      # The probe is `seq` digits cut to size, read from a file so no producer
      # dies of SIGPIPE under pipefail.
      noAo = builtins.filter (d: (d.pname or "") != "libao");
      opusFixes = scope: drv: drv.overrideAttrs (o: {
        preConfigure = (o.preConfigure or "") + ''
          export HAVE_PKG_CONFIG=yes
        '';
        # pkgsStatic promotes buildInputs into propagatedBuildInputs, so both.
        buildInputs = noAo (o.buildInputs or [ ]);
        propagatedBuildInputs = noAo (o.propagatedBuildInputs or [ ]);
        doCheck = false;
        doInstallCheck = scope.stdenv.buildPlatform.canExecute scope.stdenv.hostPlatform;
        nativeInstallCheckInputs = [ ];
        installCheckPhase = ''
          runHook preInstallCheck
          _b="''${bin:-$out}/bin"
          seq 1 34000 > digits
          head -c 192000 digits > p.raw
          "$_b/opusenc" --quiet --serial 1 --raw p.raw p.opus
          "$_b/opusenc" --quiet --serial 1 --raw - - < p.raw > s.opus
          cmp s.opus p.opus || {
            echo "opusenc writes a different stream through stdin/stdout"; exit 1; }
          "$_b/opusinfo" p.opus > info.txt
          grep -q 'Channels: 2' info.txt && grep -q 'Playback length: 0m:01.000s' info.txt || {
            cat info.txt; echo "opusinfo did not report the probe stream"; exit 1; }
          "$_b/opusdec" --quiet p.opus back.raw
          test "$(wc -c < back.raw)" -eq 192000 || {
            echo "opusdec did not decode the whole stream"; exit 1; }
          "$_b/opusdec" --quiet p.opus back.wav
          "$_b/opusdec" --quiet --force-wav - - < p.opus > s.wav
          cmp s.wav back.wav || {
            echo "opusdec reads stdin or writes stdout differently"; exit 1; }
          echo "installCheck: opusenc/opusinfo/opusdec round trip, files and stdin/stdout"
          runHook postInstallCheck
        '';
      });
      # Lift the meta.platforms = unix guard on the xiph codec libs (libopusenc,
      # opusfile) for the mingw cross. They are portable C and cross-compile to
      # mingw cleanly; the restriction is over-conservative upstream metadata.
      # Overriding meta doesn't change the store path, only the eval guard.
      winInputs = pkgs: drv: drv.overrideAttrs (old: {
        buildInputs =
          let
            metaAllow = d: d.overrideAttrs (o: {
              meta = (o.meta or { }) // { platforms = pkgs.lib.platforms.all; broken = false; };
            });
            xiph = [ "libopusenc" "opusfile" ];
          in
          builtins.map (d: if builtins.elem (d.pname or "") xiph then metaAllow d else d)
            (old.buildInputs or [ ]);
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "opus-tools";
      smoke = [ "--unpin-program=opusenc" "--version" ];
      smokePattern = "opusenc.*opus-tools";
      # opusdec opens http(s):// URLs, so it resolves hostnames.
      dnsFallback = true;

      # Build via the unpin-llvm engine + emit a bitcode multicall module: the
      # engine compiles opus-tools to bitcode and the standalone self-folds
      # opusenc/opusdec/opusinfo into one `opus-tools` binary on every target,
      # windows included. Pure C — no requires.cxx.
      engine = "unpin-llvm";
      multicall = {
        windows = true;
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
        # engine path: apps → bitcode → selfFold.
        opusFixes ps opusTools;
      windowsBuild = pkgs:
        let
          # OPENSSLDIR/ENGINESDIR/MODULESDIR default to openssl's own $out, so
          # the .exe carried live references to `openssl-…-w64-mingw32` and its
          # `-etc`. The retarget is set-wide ONLY in the engine's native scope
          # (nix-lib/native-overlay/openssl.nix) -- the mingw and cosmo scopes
          # have none, so each consumer has to do it. C:/ssl is what the
          # standalone `openssl` package already uses for its own mingw build.
          # Gated on the host: an overlay passed to `.extend` reaches the build
          # platform's package set too, and ungated it rebuilt the native openssl
          # (and everything above it, curl and git included) for nothing.
          mingw = (ulib.mingwStaticCross pkgs).extend (final: prev:
            prev.lib.optionalAttrs prev.stdenv.hostPlatform.isWindows {
              openssl = prev.openssl.overrideAttrs (ulib.retargetOpenssl "C:/ssl");
            });
        in
        opusFixes mingw (winInputs pkgs mingw.opus-tools);
    };
}
