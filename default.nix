{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;

  mkTerraformProvider = lib.makeOverridable (
    {
      owner,
      repo,
      version,
      url,
      sha256,
    }:
    let
      inherit (pkgs.go) GOARCH GOOS;
      tofuRegistry = "registry.opentofu.org";
      # The canonical path where the provider binary will be installed.
      installPath = "$out/libexec/terraform-providers/${tofuRegistry}/${owner}/${repo}/${version}/${GOOS}_${GOARCH}";
    in
    pkgs.stdenv.mkDerivation {
      pname = "tfprovider-${owner}-${repo}";
      inherit version;

      src = pkgs.fetchurl {
        inherit url sha256;
      };

      buildPhase = ":";
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.unzip ];

      installPhase = ''
        # 1. Create the canonical directory and install the provider.
        mkdir -p "${installPath}"
        unzip -o $src -d "${installPath}"
        chmod +x "${installPath}"/terraform-provider-*
      '';
      passthru = {
        providerName = repo;
        providerSource = "${tofuRegistry}/${owner}/${repo}";
      };
    }
  );

  importJSON =
    {
      owner,
      repo,
      file,
    }:
    let
      data = builtins.fromJSON (builtins.readFile file);
    in
    lib.listToAttrs (
      lib.flatten (
        map (
          versionInfo:
          let
            target = lib.findFirst (
              t: t.os == pkgs.stdenv.hostPlatform.go.GOOS && t.arch == pkgs.stdenv.hostPlatform.go.GOARCH
            ) null versionInfo.targets;
          in
          lib.optional (target != null) {
            name = versionInfo.version;
            value = mkTerraformProvider {
              inherit owner repo;
              version = versionInfo.version;
              url = target.download_url;
              sha256 = target.shasum;
            };
          }
        ) data.versions
      )
    );

  files = lib.filesystem.listFilesRecursive ./providers;
in
lib.foldl' (
  acc: file:
  let
    split = lib.splitString "/" (toString file);
    end2 = lib.takeEnd 2 split;

    owner = builtins.unsafeDiscardStringContext (lib.head end2);
    repo = builtins.unsafeDiscardStringContext (lib.removeSuffix ".json" (lib.last end2));
  in
  lib.recursiveUpdate acc {
    ${owner} = {
      ${repo} = importJSON {
        inherit owner repo file;
      };
    };
  }
) { } files
