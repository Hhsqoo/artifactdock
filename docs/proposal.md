# ArtifactDock：MoonBit 原生 OCI 制品仓库服务端

## 项目简介

ArtifactDock 是一个用 MoonBit 编写、可自行部署的轻量级 OCI Distribution 服务端。它接收、校验、持久化并分发容器镜像、Wasm 包和其他 OCI 制品，为 MoonBit 生态补上“客户端和运行时之外的仓库服务端”这一基础设施环节。

## 方向与价值

OCI Distribution 已经成为容器和 Wasm 制品的通用协议，但 MoonBit 生态目前已有的相关项目主要是读取仓库的客户端、运行时或本地 OCI Layout 构建器，并没有一个面向开发者、CI 和私有部署的 MoonBit 原生仓库服务端。ArtifactDock 采用文件系统内容寻址存储，零数据库依赖，下载即可运行，适合本地开发、自动化测试、边缘设备和小型私有部署。

## 预期使用场景

1. **Wasm 包分发**：团队将 MoonBit 编译出的 Wasm 模块推送到 ArtifactDock，开发机或运行时按 tag/digest 拉取。
2. **CI 集成测试**：CI 启动临时 ArtifactDock，验证镜像/制品的 push、pull、digest 校验和重启后恢复，不依赖 Docker Registry 容器。
3. **边缘与内网部署**：在资源有限或无法接入公有云的环境中运行单文件服务，存储企业内部的 OCI 制品。
4. **OCI 教学与实验**：通过可读的 MoonBit 实现观察 `/v2/`、blob upload、manifest 和 tag 的协议交互。

## 核心功能

- `/v2/` API 探活与版本发现。
- SHA-256 内容寻址 blob 存储、去重、`HEAD`/`GET`。
- `POST`/`PATCH`/`PUT` 单体或分块上传，并在提交时验证 digest。
- Manifest 按 tag 或 digest 写入、读取和 `HEAD` 查询，校验 UTF-8 JSON 与 `schemaVersion: 2`，并保留制品媒体类型。
- `tags/list` 查询、原子文件写入、进程重启后的文件系统持久化。
- 可复现的 PowerShell push/pull 示例、MoonBit 单元测试和 GitHub Actions CI。

## 范围边界与维护路线

首个版本聚焦单节点、文件系统后端和 OCI Distribution 核心读写路径；暂不包含认证授权、垃圾回收、远程对象存储、复制和容器运行时。后续按真实使用反馈增加 token auth、referrers/SBOM、可插拔存储后端、配额和 OCI conformance 测试矩阵，保持协议层与存储层解耦，便于长期维护。

## 原创性与参考

这是原创的 MoonBit 服务端实现，不是代码移植。调研 Mooncakes 后，`mizchi/oci_wasm` 是只读 OCI 客户端，`mizchi/wacon` 是 Wasm 容器运行时，`oyjh0381/moonoci` 构建本地 OCI Image Layout，`zploc/loci` 提供库级存储/传输抽象；它们都没有提供可直接部署的 OCI Distribution HTTP 仓库服务。ArtifactDock 与这些项目互补，而不是重复其功能。

协议依据：[OCI Distribution Specification](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)。项目地址：[github.com/Hhsqoo/artifactdock](https://github.com/Hhsqoo/artifactdock)。许可证：Apache-2.0。

## 实现路径

使用 `moonbitlang/async` 的 HTTP、socket、文件系统和 IO API，使用 `gmlewis/sha256` 计算摘要；先完成核心路径和可复现示例，再以 OCI conformance 用例、真实 Wasm 制品和 CI 反馈驱动迭代。所有功能保持公开 Git 历史、文档和测试同步更新。
