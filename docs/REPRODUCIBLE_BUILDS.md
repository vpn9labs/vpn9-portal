# VPN9 Portal Reproducible Builds

## Overview

VPN9 Portal implements deterministic, reproducible builds to ensure transparency, security, and trustworthiness. Anyone can independently verify that our published Docker images match exactly what would be built from the source code.

This differentiates VPN9 from other VPN providers by demonstrating our commitment to:
- **Transparency**: All build processes are open and verifiable
- **Security**: No hidden backdoors or malicious code can be inserted
- **Trust**: Users can verify that binaries match the source code
- **Accountability**: All builds are attested and signed

## What are Reproducible Builds?

Reproducible builds are a set of software development practices that create an independently-verifiable path from source to binary code. A build is reproducible if given the same source code, build environment, and build instructions, any party can recreate bit-by-bit identical copies of all specified artifacts.

## Quick Start

### Building a Reproducible Image

```bash
# Using make
make -f Makefile.reproducible build BUILD_VERSION=v1.0.0

# Using script directly
./scripts/reproducible-build.sh

# With custom parameters
BUILD_VERSION=v1.0.0 \
PLATFORMS=linux/amd64,linux/arm64 \
./scripts/reproducible-build.sh
```

### Verifying a Build

```bash
# Verify an existing build
./scripts/verify-build.sh v1.0.0

# Rebuild and verify reproducibility
./scripts/verify-build.sh v1.0.0 --rebuild

# Using make
make -f Makefile.reproducible verify BUILD_VERSION=v1.0.0
```

## Build Process

### 1. Deterministic Base Images

We use specific Docker image digests rather than tags:
```dockerfile
FROM docker.io/library/ruby:3.4.5-slim@sha256:92e7819e4c5c3a5b1b7e4e8f4c5e4c8d...
```

### 2. Fixed Timestamps

All builds use `SOURCE_DATE_EPOCH` to ensure consistent timestamps:
```bash
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
```

### 3. Pinned Dependencies

All dependencies are locked to specific versions:
- Ruby gems via `Gemfile.lock` with frozen flag
- Node packages via `bun.lock` with frozen lockfile
- System packages with explicit versions

### 4. Build Attestation

Each build generates:
- SHA256/SHA512 checksums
- SBOM (Software Bill of Materials)
- SLSA provenance attestation
- Signature (when configured)

## Architecture

```
┌─────────────────────────────────────────────┐
│                Source Code                   │
│         (Git commit + timestamp)             │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│           Reproducible Build                 │
│  • Fixed base images (SHA256)               │
│  • Pinned dependencies                      │
│  • SOURCE_DATE_EPOCH                        │
│  • Deterministic file ordering              │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│             Build Artifacts                  │
│  • Docker image                             │
│  • Checksums (SHA256/SHA512)                │
│  • SBOM (Software Bill of Materials)        │
│  • Attestation (SLSA Provenance)            │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│              Verification                    │
│  • Anyone can rebuild                       │
│  • Compare checksums                        │
│  • Verify attestation                       │
└─────────────────────────────────────────────┘
```

## File Structure

```
vpn9-portal/
├── Dockerfile                  # Reproducible Dockerfile (default)
├── Makefile.reproducible        # Build automation
├── scripts/
│   ├── reproducible-build.sh   # Main build script
│   └── verify-build.sh         # Verification script
├── builds/                     # Build outputs (git-ignored)
│   ├── vpn9-portal-v1.0.0.tar # Exported image
│   ├── checksums-v1.0.0.sha256 # Checksums
│   ├── sbom-v1.0.0.spdx       # Software BOM
│   └── attestations/
│       └── attestation-v1.0.0.json
└── .github/
    └── workflows/
        └── reproducible-build.yml # CI/CD automation
```

## Verification Instructions

### For Users

To verify that a VPN9 Portal image is authentic and matches the source:

1. **Download the verification script**:
```bash
curl -O https://raw.githubusercontent.com/vpn9/vpn9-portal/main/scripts/verify-build.sh
chmod +x verify-build.sh
```

2. **Verify a specific version**:
```bash
./verify-build.sh v1.0.0
```

3. **Check the verification report**:
```bash
cat builds/verification/verification-report-v1.0.0.txt
```

### For Security Researchers

To perform a complete independent verification:

1. **Clone the repository**:
```bash
git clone https://github.com/vpn9labs/vpn9-portal.git
cd vpn9-portal
```

2. **Checkout the specific version**:
```bash
git checkout v1.0.0
```

3. **Rebuild from source**:
```bash
./scripts/verify-build.sh v1.0.0 --rebuild
```

4. **Compare with published image**:
```bash
# Pull the published image
docker pull vpn9/vpn9-portal:v1.0.0

# The script will automatically compare checksums
```

## Build Parameters

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BUILD_VERSION` | Version tag for the build | Git tag or commit hash |
| `BUILD_COMMIT` | Git commit hash | Current HEAD |
| `SOURCE_DATE_EPOCH` | Unix timestamp for reproducibility | Last commit timestamp |
| `IMAGE_NAME` | Docker image name | vpn9/vpn9-portal |
| `PLATFORMS` | Target platforms | linux/amd64,linux/arm64 |
| `VERIFY_REPRODUCIBLE` | Verify build reproducibility | false |

### Makefile Targets

```bash
# Show help
make -f Makefile.reproducible help

# Build image
make -f Makefile.reproducible build

# Verify reproducibility
make -f Makefile.reproducible verify

# Push to registry
make -f Makefile.reproducible push

# Complete release
make -f Makefile.reproducible release
```

## Continuous Integration

Our GitHub Actions workflow automatically:
1. Builds reproducible images on every tag
2. Generates and signs attestations
3. Creates SBOMs for supply chain security
4. Publishes verification artifacts
5. Runs reproducibility tests

## Security Considerations

### Supply Chain Security

- All base images use SHA256 digests
- Dependencies are locked and verified
- Build process is transparent and auditable
- Attestations provide provenance

### Verification Trust

- Builds can be independently reproduced
- Checksums are published with releases
- Optional signing with cosign/sigstore
- SLSA Level 3 provenance

## Troubleshooting

### Build Differences

If builds are not reproducible, check:

1. **Different SOURCE_DATE_EPOCH**:
```bash
echo $SOURCE_DATE_EPOCH
git log -1 --format=%ct
```

2. **Modified dependencies**:
```bash
git diff Gemfile.lock
git diff bun.lock
```

3. **Docker version differences**:
```bash
docker --version
docker buildx version
```

### Common Issues

**Issue**: "Images differ"
**Solution**: Ensure SOURCE_DATE_EPOCH matches and no local modifications exist

**Issue**: "Checksums don't match"
**Solution**: Verify you're building from the exact same commit

**Issue**: "Build fails"
**Solution**: Check Docker buildx is properly configured

## Comparison with Other VPN Providers

| Provider | Reproducible Builds | Open Source | Build Attestation | SBOM |
|----------|-------------------|-------------|-------------------|------|
| **VPN9** | ✅ Full | ✅ Yes | ✅ Yes | ✅ Yes |
| Mullvad | ⚠️ Android only | ✅ Yes | ❌ No | ❌ No |
| ProtonVPN | ❌ No | ⚠️ Partial | ❌ No | ❌ No |
| ExpressVPN | ❌ No | ❌ No | ❌ No | ❌ No |
| NordVPN | ❌ No | ❌ No | ❌ No | ❌ No |

## Future Improvements

- [ ] Implement reproducible builds for client applications
- [ ] Add reproducible OS images for VPN servers
- [ ] Integrate with Binary Transparency logs
- [ ] Implement deterministic builds for all platforms
- [ ] Add automated reproducibility monitoring

## Contributing

We welcome contributions to improve our reproducible build process:

1. Test reproducibility on different platforms
2. Report any non-deterministic behavior
3. Suggest improvements to the build process
4. Help verify and attest builds

## References

- [Reproducible Builds Project](https://reproducible-builds.org/)
- [SLSA Framework](https://slsa.dev/)
- [Supply Chain Levels for Software Artifacts](https://slsa.dev/spec/v1.0/levels)
- [Mullvad's Reproducible Builds](https://mullvad.net/en/blog/tag/reproducible-builds/)
- [Docker Reproducible Builds](https://docs.docker.com/build/attestations/slsa-provenance/)

## License

The reproducible build system is part of VPN9 Portal and is licensed under the same terms as the main project.

---

*Last updated: January 2025*
*Build system version: 1.0.0*