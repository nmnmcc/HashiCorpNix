# HashiCorpNix

Nix flake for every HashiCorp tool — pre-built binaries from
releases.hashicorp.com.

Translations: [简体中文](README.zh-CN.md).

Unlike nixpkgs which builds from source (BSL-licensed, no binary cache),
this flake fetches official binaries directly. No compilation, instant
installs.

## What you get

Every product on releases.hashicorp.com that ships a `.zip` binary for
Linux or macOS, across all released stable versions.

Core tools include `terraform`, `vault`, `consul`, `nomad`, `packer`,
`boundary`, `waypoint`, `vagrant`, `sentinel`, `consul-template`,
`terraform-ls`, and many more.

Supported systems: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`,
`aarch64-darwin`.

## Version hierarchy

Each product is available at four granularity levels:

| Package | Resolves to |
| --- | --- |
| `terraform` | latest stable version |
| `terraform_1` | latest 1.x.y |
| `terraform_1_15` | latest 1.15.x |
| `terraform_1_15_6` | exactly 1.15.6 |

## Quick start

Run any tool directly:

```sh
nix run github:nmnmcc/HashiCorpNix#terraform
nix run github:nmnmcc/HashiCorpNix#vault -- --help
nix run github:nmnmcc/HashiCorpNix#consul_1 -- version
```

## Flake setup

Add as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hashicorp.url = "github:nmnmcc/HashiCorpNix";
  };

  outputs = { nixpkgs, hashicorp, ... }: {
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in pkgs.mkShell {
      packages = [
        hashicorp.packages.x86_64-linux.terraform
        hashicorp.packages.x86_64-linux.vault
      ];
    };
  };
}
```

## Using the overlay

Two overlays are provided:

| Overlay | Effect |
| --- | --- |
| `overlays.default` | Adds `pkgs.hashicorp.*` — no existing packages are touched |
| `overlays.override` | Same as default, plus replaces top-level `pkgs.*` names that match (e.g. `pkgs.terraform`, `pkgs.vault`) |

### `overlays.default` — namespaced

All packages live under `pkgs.hashicorp`, nothing in nixpkgs is changed:

```nix
{
  nixpkgs.overlays = [
    hashicorp.overlays.default
  ];

  environment.systemPackages = with pkgs.hashicorp; [
    terraform
    vault
    consul
    nomad_2
  ];
}
```

### `overlays.override` — replace nixpkgs packages

Packages that share a name with an existing nixpkgs attribute are replaced
at the top level. NixOS options like `services.vault.package` will
automatically use the binary from this flake:

```nix
{
  nixpkgs.overlays = [
    hashicorp.overlays.override
  ];

  # pkgs.terraform, pkgs.vault, etc. now come from this flake
  environment.systemPackages = with pkgs; [
    terraform
    vault
    consul
    nomad
  ];
}
```

## Pinning a version

Use the version hierarchy to control how aggressively you track updates:

```nix
# Always the latest
hashicorp.packages.${system}.terraform

# Stay on the 1.x major track
hashicorp.packages.${system}.terraform_1

# Pin to the 1.15 minor track
hashicorp.packages.${system}.terraform_1_15

# Exact version, never changes
hashicorp.packages.${system}.terraform_1_15_6
```

## Using the packages directly

You can run the packages without a flake setup:

```sh
nix shell github:nmnmcc/HashiCorpNix#terraform_1_15
terraform version
```

Or build a specific version:

```sh
nix build github:nmnmcc/HashiCorpNix#vault_1_19_2
./result/bin/vault version
```

## Updating

If your system uses this flake as a flake input, update it like any other
input:

```sh
nix flake update hashicorp
```

This repository is updated automatically every 6 hours via GitHub Actions.
The update script scans `releases.hashicorp.com/index.json`, fetches
SHA256 checksums for new releases, and commits the changes to
`versions.json`.

## How it works

1. `update.py` fetches the global product index from HashiCorp.
2. For each product with stable versions that ship `.zip` builds, it
   downloads `SHA256SUMS` and converts hashes to Nix SRI format.
3. New versions are merged incrementally into `versions.json`.
4. `flake.nix` reads `versions.json` and generates packages using
   `fetchurl` + `unzip`.

## Troubleshooting

If Nix says the package is not available, check whether your system is one
of the four supported platforms listed above.

Some older HashiCorp products may not ship binaries for all platforms. For
example, `vagrant` only provides a `.zip` for `x86_64-linux`; other
platforms use `.dmg` or `.deb` instead and are not covered by this flake.

To see which packages are available for your system:

```sh
nix flake show github:nmnmcc/HashiCorpNix --system x86_64-linux
```

## License

The packaged binaries are distributed by HashiCorp under the
[Business Source License 1.1](https://www.hashicorp.com/bsl). This flake
packages those releases for Nix.
