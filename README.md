# ArtifactDock

ArtifactDock is a lightweight, self-hosted OCI Distribution registry written primarily in MoonBit. It stores container images, Wasm packages, and other OCI artifacts on a local filesystem and exposes the standard `/v2/` HTTP API.

The project is intentionally complementary to MoonBit's existing ecosystem: `mizchi/oci_wasm` and `mizchi/wacon` provide clients and runtimes, while [MoonOCI](https://mooncakes.io/docs/oyjh0381/moonoci@0.1.4) builds local OCI layouts. ArtifactDock supplies the missing deployable server boundary.

## Status

The first release targets a reliable single-node registry suitable for local development, CI fixtures, and private Wasm distribution:

- OCI `/v2/` discovery
- Content-addressed SHA-256 blob storage
- Monolithic and chunked blob uploads (`POST`, `PATCH`, `PUT`)
- Blob `HEAD`/`GET`
- Blob byte-range `GET` for resuming interrupted downloads (`206`/`416`)
- Manifest `PUT`, `HEAD`, `GET` by tag or digest, with UTF-8 JSON/schema validation
- Manifest media-type preservation for Wasm and other OCI artifacts
- ASCII sorted tag listing with OCI `n`/`last` pagination and next-page links
- Restart-safe filesystem persistence and atomic writes

Authentication, garbage collection, remote object storage, replication, and referrers are deliberately follow-up work. The server does not build images or execute containers.

## Run

Install MoonBit, then run:

```powershell
moon run src -- --root ./artifactdock-data --host 127.0.0.1 --port 5000
```

The server listens on `http://127.0.0.1:5000`. A minimal push/pull smoke test is in [`examples/push-pull.ps1`](examples/push-pull.ps1).

## Development

```powershell
moon fmt
moon check --target native
moon test --target native
moon build --target native
```

The implementation follows the [OCI Distribution Specification](https://github.com/opencontainers/distribution-spec/blob/main/spec.md). The conformance suite is the long-term compatibility target.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
