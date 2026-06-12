{
  description = "HashiCorp tools — pre-built binaries from releases.hashicorp.com";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      versions = builtins.fromJSON (builtins.readFile ./versions.json);

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      eachSystem = nixpkgs.lib.genAttrs systems;

      platformOf = {
        x86_64-linux = "linux_amd64";
        aarch64-linux = "linux_arm64";
        x86_64-darwin = "darwin_amd64";
        aarch64-darwin = "darwin_arm64";
      };

      splitVer = v: builtins.filter builtins.isString (builtins.split "\\." v);

      latestOf = vers:
        builtins.head (builtins.sort (a: b: builtins.compareVersions a b > 0) vers);

      mkPackage = pkgs: pname: version: shas:
        let
          platform = platformOf.${pkgs.stdenv.hostPlatform.system};
          hash = shas.${platform} or null;
        in
        if hash == null then null
        else pkgs.stdenv.mkDerivation {
          inherit pname version;
          src = pkgs.fetchurl {
            url = "https://releases.hashicorp.com/${pname}/${version}/${pname}_${version}_${platform}.zip";
            inherit hash;
          };
          nativeBuildInputs = [ pkgs.unzip ];
          sourceRoot = ".";
          unpackPhase = "unzip $src";
          dontBuild = true;
          installPhase = "install -D -m0755 ${pname} $out/bin/${pname}";
          dontPatchShebangs = true;
          meta = with pkgs.lib; {
            homepage = "https://releases.hashicorp.com/${pname}";
            description = "HashiCorp ${pname} ${version} (pre-built binary)";
            sourceProvenance = [ sourceTypes.binaryNativeCode ];
            license = licenses.bsl11;
          };
        };

      mkAllPackages = pkgs:
        let
          lib = nixpkgs.lib;

          productPackages = product: info:
            let
              vs = info.versions or {};
              allVers = builtins.attrNames vs;
              mk = ver: mkPackage pkgs product ver vs.${ver};

              # terraform_1_15_6 — exact
              exact = builtins.listToAttrs (map (ver: {
                name = "${product}_${builtins.concatStringsSep "_" (splitVer ver)}";
                value = mk ver;
              }) allVers);

              # terraform_1_15 — latest patch within minor
              minorPkgs = lib.mapAttrs' (slug: vers:
                lib.nameValuePair "${product}_${slug}" (mk (latestOf vers))
              ) (lib.groupBy (v:
                let p = splitVer v;
                in "${builtins.elemAt p 0}_${builtins.elemAt p 1}"
              ) allVers);

              # terraform_1 — latest within major
              majorPkgs = lib.mapAttrs' (slug: vers:
                lib.nameValuePair "${product}_${slug}" (mk (latestOf vers))
              ) (lib.groupBy (v: builtins.elemAt (splitVer v) 0) allVers);

              # terraform — overall latest
              latest =
                if info ? latest && builtins.hasAttr info.latest vs
                then { ${product} = mk info.latest; }
                else {};

            in exact // minorPkgs // majorPkgs // latest;

        in
        lib.filterAttrs (_: v: v != null)
          (builtins.foldl'
            (acc: name: acc // productPackages name versions.${name})
            {}
            (builtins.attrNames versions));

    in
    {
      packages = eachSystem (system:
        mkAllPackages nixpkgs.legacyPackages.${system}
      );

      overlays.default = final: _prev: {
        hashicorp = mkAllPackages final;
      };
    };
}
