# HashiCorpNix

将 releases.hashicorp.com 上所有 HashiCorp 工具的预构建二进制打包为 Nix
flake。

nixpkgs 从源码构建 HashiCorp 工具（BSL 许可，无二进制缓存），本 flake
直接获取官方二进制文件——无需编译，即装即用。

## 包含内容

releases.hashicorp.com 上所有提供 `.zip` 二进制的产品，涵盖全部已发布的
稳定版本。

核心工具包括 `terraform`、`vault`、`consul`、`nomad`、`packer`、
`boundary`、`waypoint`、`vagrant`、`sentinel`、`consul-template`、
`terraform-ls` 等。

支持的系统：`x86_64-linux`、`aarch64-linux`、`x86_64-darwin`、
`aarch64-darwin`。

## 版本层级

每个产品提供四个粒度级别：

| 包名 | 解析为 |
| --- | --- |
| `terraform` | 最新稳定版 |
| `terraform_1` | 最新 1.x.y |
| `terraform_1_15` | 最新 1.15.x |
| `terraform_1_15_6` | 精确 1.15.6 |

## 快速开始

直接运行任意工具：

```sh
nix run github:nmnmcc/HashiCorpNix#terraform
nix run github:nmnmcc/HashiCorpNix#vault -- --help
nix run github:nmnmcc/HashiCorpNix#consul_1 -- version
```

## Flake 配置

添加为 flake 输入：

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

## 使用 overlay

overlay 将所有包放在 `pkgs.hashicorp` 命名空间下：

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

## 锁定版本

通过版本层级控制更新粒度：

```nix
# 始终使用最新版
hashicorp.packages.${system}.terraform

# 锁定 1.x 主版本
hashicorp.packages.${system}.terraform_1

# 锁定 1.15 次版本
hashicorp.packages.${system}.terraform_1_15

# 精确版本，永不变化
hashicorp.packages.${system}.terraform_1_15_6
```

## 直接使用

无需 flake 配置即可运行：

```sh
nix shell github:nmnmcc/HashiCorpNix#terraform_1_15
terraform version
```

或构建特定版本：

```sh
nix build github:nmnmcc/HashiCorpNix#vault_1_19_2
./result/bin/vault version
```

## 更新

如果你的系统使用本 flake 作为输入，像其他输入一样更新即可：

```sh
nix flake update hashicorp
```

本仓库通过 GitHub Actions 每 6 小时自动更新。更新脚本扫描
`releases.hashicorp.com/index.json`，获取新版本的 SHA256 校验和，并将变更
提交到 `versions.json`。

## 工作原理

1. `update.py` 从 HashiCorp 获取全局产品索引。
2. 对每个提供 `.zip` 构建的稳定版产品，下载 `SHA256SUMS` 并将哈希转换为
   Nix SRI 格式。
3. 新版本增量合并到 `versions.json`。
4. `flake.nix` 读取 `versions.json`，使用 `fetchurl` + `unzip` 生成包。

## 故障排查

如果 Nix 提示包不可用，请检查你的系统是否属于上述四个支持平台之一。

部分较早的 HashiCorp 产品可能不提供所有平台的二进制文件。例如 `vagrant`
仅为 `x86_64-linux` 提供 `.zip`；其他平台使用 `.dmg` 或 `.deb`，不在本
flake 的覆盖范围内。

查看当前系统可用的包：

```sh
nix flake show github:nmnmcc/HashiCorpNix --system x86_64-linux
```

## 许可

打包的二进制文件由 HashiCorp 在
[Business Source License 1.1](https://www.hashicorp.com/bsl) 下分发。本
flake 将这些发布版打包供 Nix 使用。
