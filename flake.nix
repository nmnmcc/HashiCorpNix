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
        builtins.foldl'
          (a: b: if builtins.compareVersions a b >= 0 then a else b)
          (builtins.head vers)
          (builtins.tail vers);

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
          nativeBuildInputs = [ pkgs.unzip pkgs.autoPatchelfHook ];
          buildInputs = [ pkgs.stdenv.cc.cc.lib ];
          sourceRoot = ".";
          unpackPhase = "unzip $src";
          dontBuild = true;
          installPhase = "install -D -m0755 ${pname} $out/bin/${pname}";
          dontStrip = true;
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
          platform = platformOf.${pkgs.stdenv.hostPlatform.system};

          productPairs = product: info:
            let
              vs = info.versions or {};
              allVers = builtins.filter
                (ver: builtins.hasAttr platform vs.${ver})
                (builtins.attrNames vs);
              mk = ver: mkPackage pkgs product ver vs.${ver};

              # splitVer per version, computed once via lazy attrset
              parts = builtins.listToAttrs (map (ver: {
                name = ver;
                value = splitVer ver;
              }) allVers);

              # terraform_1_15_6 — exact
              exact = map (ver: {
                name = "${product}_${builtins.concatStringsSep "_" parts.${ver}}";
                value = mk ver;
              }) allVers;

              # terraform_1_15 — latest patch within minor
              minorPairs = lib.mapAttrsToList (slug: vers: {
                name = "${product}_${slug}";
                value = mk (latestOf vers);
              }) (lib.groupBy (ver:
                let p = parts.${ver};
                in "${builtins.elemAt p 0}_${builtins.elemAt p 1}"
              ) allVers);

              # terraform_1 — latest within major
              majorPairs = lib.mapAttrsToList (slug: vers: {
                name = "${product}_${slug}";
                value = mk (latestOf vers);
              }) (lib.groupBy (ver:
                builtins.elemAt parts.${ver} 0
              ) allVers);

              # terraform — overall latest (best version with this platform)
              latestPair =
                if allVers != []
                then [{ name = product; value = mk (latestOf allVers); }]
                else [];

            in exact ++ minorPairs ++ majorPairs ++ latestPair;

        in
        builtins.listToAttrs (
          builtins.concatMap
            (product: productPairs product versions.${product})
            (builtins.attrNames versions)
        );

    in
    {
      packages = eachSystem (system:
        mkAllPackages nixpkgs.legacyPackages.${system}
      );

      overlays.default = final: _prev: {
        hashicorp = mkAllPackages final;
      };

      overlays.override = _final: prev:
        let all = mkAllPackages prev;
        in { hashicorp = all; } // (builtins.intersectAttrs prev all);
    };
}
