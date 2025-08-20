# Runtime Verification for VPN9

## How Users Can Verify VPN9 is Running Reproducible Builds

VPN9 implements multiple layers of verification to ensure that our production servers are running exactly the code we claim, built in a reproducible manner.

## 🔍 Verification Methods

### 1. Web-Based Verification Dashboard
Visit [https://vpn9.com/verify](https://vpn9.com/verify) to:
- View current deployment attestation
- See build metadata and checksums
- Perform automatic verification checks
- Access transparency logs

### 2. API-Based Verification

#### Get Current Attestation
```bash
curl https://vpn9.com/api/v1/attestation | jq .
```

Returns:
```json
{
  "deployment": {
    "image_digest": "sha256:abc123...",
    "build_version": "v1.0.0",
    "build_commit": "dae214e1...",
    "deployed_at": "2025-01-19T10:00:00Z"
  },
  "verification": {
    "docker_image": "ghcr.io/vpn9labs/vpn9-portal:v1.0.0",
    "source_url": "https://github.com/vpn9labs/vpn9-portal/tree/dae214e1",
    "attestation_url": "..."
  }
}
```

#### Perform Live Verification
```bash
curl https://vpn9.com/api/v1/attestation/verify | jq .
```

### 3. Manual Verification Process

#### Step 1: Get Production Build Info
```bash
# Fetch current production metadata
PROD_VERSION=$(curl -s https://vpn9.com/api/v1/attestation | jq -r .deployment.build_version)
PROD_COMMIT=$(curl -s https://vpn9.com/api/v1/attestation | jq -r .deployment.build_commit)
PROD_DIGEST=$(curl -s https://vpn9.com/api/v1/attestation | jq -r .deployment.image_digest)
```

#### Step 2: Pull and Verify Docker Image
```bash
# Pull the exact image running in production
docker pull ghcr.io/vpn9labs/vpn9-portal:${PROD_VERSION}

# Check its digest matches
docker inspect ghcr.io/vpn9labs/vpn9-portal:${PROD_VERSION} --format='{{.Id}}' | grep ${PROD_DIGEST}
```

#### Step 3: Rebuild from Source
```bash
# Clone repository
git clone https://github.com/vpn9labs/vpn9-portal.git
cd vpn9-portal

# Checkout exact commit
git checkout ${PROD_COMMIT}

# Run reproducible build
./scripts/reproducible-build.sh

# Compare the results
./scripts/verify-build.sh ${PROD_VERSION}
```

#### Step 4: Compare Checksums
```bash
# Download published checksums
curl -O https://github.com/vpn9labs/vpn9-portal/releases/download/${PROD_VERSION}/checksums-${PROD_VERSION}.sha256

# Verify local build matches
sha256sum -c checksums-${PROD_VERSION}.sha256
```

## 🛡️ Security Guarantees

### What This Proves
1. **Source Transparency** - Exact source code is publicly available
2. **Build Reproducibility** - Anyone can recreate the exact binary
3. **No Hidden Code** - No backdoors or modifications possible
4. **Deployment Integrity** - Production runs the verified build

### What This Prevents
- Secret backdoors in production
- Modified binaries different from source
- Supply chain attacks
- Hidden tracking or logging code

## 📊 Transparency Log

All builds are logged with:
- Build timestamp
- Git commit hash
- Docker image digest
- Attestation signature
- SBOM (Software Bill of Materials)

Access at: [https://vpn9.com/verify#transparency-log](https://vpn9.com/verify#transparency-log)

## 🔐 Cryptographic Proofs

### Build Attestation
Each build includes SLSA provenance attestation:
```bash
# Download attestation
curl -O https://github.com/vpn9labs/vpn9-portal/releases/download/${VERSION}/attestation-${VERSION}.json

# Verify with cosign (if configured)
cosign verify-attestation ghcr.io/vpn9labs/vpn9-portal:${VERSION}
```

### Runtime Signature
Production servers sign their attestation:
```bash
# Get signed attestation
curl https://vpn9.com/api/v1/attestation/verify | jq .proof
```

## 🚦 Continuous Monitoring

### Automated Checks
- GitHub Actions verifies reproducibility on every build
- Production self-attestation every hour
- External monitoring services verify deployment

### Third-Party Verification
Independent security researchers can:
1. Set up monitoring of our attestation endpoint
2. Periodically rebuild and verify
3. Alert if discrepancies found

## 📱 Client Verification

VPN clients can verify server authenticity:
```javascript
// In VPN client code
async function verifyServer(serverUrl) {
  const response = await fetch(`${serverUrl}/api/v1/attestation`);
  const attestation = await response.json();
  
  // Verify build version matches expected
  // Verify signature if present
  // Check against known good builds
}
```

## 🤝 Trust Model

### You Don't Need to Trust Us
- All code is open source
- Builds are reproducible
- Runtime is verifiable
- Monitoring is transparent

### You Can Verify
1. **Before Connecting** - Check our verification page
2. **While Connected** - Query attestation API
3. **Independently** - Rebuild and compare yourself
4. **Continuously** - Set up automated monitoring

## 🆚 Comparison with Other VPNs

| Feature | VPN9 | Mullvad | Others |
|---------|------|---------|--------|
| Open Source Server | ✅ | ❌ | ❌ |
| Reproducible Server Builds | ✅ | ❌ | ❌ |
| Runtime Attestation | ✅ | ❌ | ❌ |
| Live Verification API | ✅ | ❌ | ❌ |
| Transparency Log | ✅ | ⚠️ | ❌ |
| SLSA Attestation | ✅ | ❌ | ❌ |

## 🛠️ Tools for Verification

### Official Tools
- Web Dashboard: https://vpn9.com/verify
- Verification Script: `./scripts/verify-build.sh`
- API Endpoints: `/api/v1/attestation`

### Community Tools
- [vpn9-verifier](https://github.com/community/vpn9-verifier) - Independent verification bot
- [vpn9-monitor](https://github.com/community/vpn9-monitor) - Continuous monitoring service

## 📝 Verification Checklist

For maximum confidence, verify:

- [ ] Current attestation via API
- [ ] Docker image digest matches
- [ ] Rebuild from source succeeds
- [ ] Checksums match published
- [ ] SBOM is accurate
- [ ] No modified files in runtime
- [ ] SSL certificate valid
- [ ] DNS configuration correct

## 🔗 Additional Resources

- [Reproducible Builds Documentation](./REPRODUCIBLE_BUILDS.md)
- [GitHub Repository](https://github.com/vpn9labs/vpn9-portal)
- [Build Artifacts](https://github.com/vpn9labs/vpn9-portal/releases)
- [Security Policy](./SECURITY.md)

## 📧 Report Issues

If you find discrepancies:
- Email: security@vpn9.com
- GitHub Issues: https://github.com/vpn9labs/vpn9-portal/issues
- Bug Bounty: https://vpn9.com/security/bug-bounty

---

*Last updated: January 2025*
*Verification system version: 1.0.0*