# ArtifactDock OCI Registry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a MoonBit-native, self-hosted OCI Distribution registry that accepts, validates, persists, and serves OCI blobs and manifests for container, Wasm, and other artifact media types.

**Architecture:** A single native HTTP process uses `moonbitlang/async/http` for the `/v2/` API and a filesystem-backed content-addressable store. Blobs are addressed by SHA-256; manifests are stored by repository and digest, while tags are small pointer files. Upload sessions are temporary files finalized only after digest validation and atomic rename.

**Tech Stack:** MoonBit native target, `moonbitlang/async` HTTP/socket/fs/io packages, `gmlewis/sha256`, Apache-2.0.

---

### Task 1: Project and package skeleton

**Files:**
- Create: `moon.mod`
- Create: `src/moon.pkg`
- Create: `src/main.mbt`
- Create: `README.md`
- Create: `LICENSE`

**Verification:** `moon check --target native` and `moon test --target native` pass in a host with a C compiler.

### Task 2: Digest and path validation

**Files:**
- Create: `src/digest.mbt`
- Create: `src/validation.mbt`
- Test: `src/validation_wbtest.mbt`

**Verification:** valid SHA-256 references and repository names are accepted; malformed or traversal-like paths are rejected.

### Task 3: Filesystem content-addressable store

**Files:**
- Create: `src/store.mbt`
- Test: `src/store_wbtest.mbt`

**Verification:** blob writes are deduplicated, digest mismatches are rejected, manifests and tags survive a process restart, and temporary uploads are atomically finalized.

### Task 4: OCI Distribution HTTP router

**Files:**
- Create: `src/registry.mbt`
- Modify: `src/main.mbt`
- Test: `src/registry_wbtest.mbt`

**Verification:** route, upload-range, Manifest JSON/schema, and digest-reference whitebox tests cover endpoint parsing and validation; the PowerShell smoke test exercises `GET /v2/`, blob upload, manifest `PUT/GET`, and `tags/list`.

### Task 5: Reproducible demo and CI

**Files:**
- Create: `examples/push-pull.ps1`
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`

**Verification:** README commands start the server and use a standard OCI client or curl to push and pull a Wasm-style artifact; CI runs format, check, build, and tests.
