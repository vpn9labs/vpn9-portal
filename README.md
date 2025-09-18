# VPN9 Portal

**Rails portal: website, admin, and public API for VPN9. Anonymous accounts, crypto payments, zero-log posture by design.**

VPN9 is a privacy-focused VPN service that open sources all of its code. This repository contains the Rails application that powers the VPN9 website, user portal, admin panel, and public API.

## Key Features

### Privacy First Architecture
- **Zero-logs policy**: No connection tracking, IP logging, or user activity monitoring
- **Anonymous accounts**: Passphrase-based authentication without requiring personal information
- **No device tracking**: The Rails app doesn't know which devices connect or which relays users choose
- **Stateless JWT tokens**: Self-contained access tokens with hashed, rotating refresh tokens
- **Client-side key generation**: WireGuard keys generated in browser, never touch servers

### Payment & Subscriptions
- **Cryptocurrency payments**: Bitcoin and other cryptocurrencies via Bitcart integration
- **Anonymous payments**: No personal information required for purchases
- **Flexible plans**: Multiple subscription tiers with different device limits
- **Automatic activation**: Subscriptions activate immediately upon payment confirmation

### Affiliate System
- **Built-in affiliate program**: Complete tracking and commission management
- **Fraud detection**: Automated detection of suspicious referral patterns
- **Flexible payouts**: Support for multiple payout methods
- **Marketing tools**: Banner generators, link builders, and email templates

### Admin Dashboard
- **User management**: View and manage user accounts and subscriptions
- **Relay management**: Configure VPN server locations and relays
- **Analytics**: Subscription and revenue analytics (privacy-preserving)
- **Launch notifications**: Collect emails for service updates (optional)

## Technology Stack

- **Framework**: Rails 8.0.2
- **Database**: PostgreSQL (production), SQLite (development)
- **Authentication**: Argon2 password hashing, JWT access + refresh tokens for API
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Background Jobs**: Solid Queue
- **Caching**: Solid Cache
- **WebSockets**: Solid Cable
- **Deployment**: Kamal (Docker-based)

## Architecture Overview

### Authentication Flow
1. Users sign up with optional email, receive a 7-word passphrase
2. Passphrase is hashed with Argon2 and stored securely
3. Users can add custom passwords to their passphrase
4. Recovery codes provided for account recovery

### API Authentication
- Stateless JWT access tokens with 24-hour expiry
- Rotating refresh tokens stored only as hashes for revocation
- Tokens contain minimal data (user ID, subscription expiry)
- Relays validate tokens independently without callbacks

### Payment Flow
1. User selects plan and cryptocurrency
2. System generates payment address via Bitcart
3. User sends payment to provided address
4. Webhook confirms payment and activates subscription
5. No personal information collected during payment

## Installation

### Prerequisites
- Ruby 3.3+
- PostgreSQL 16+ (production) or SQLite (development)
- Node.js 20+ or Bun
- Redis (optional, for caching)

### Development Setup

1. Clone the repository:
```bash
git clone https://github.com/vpn9labs/vpn9-portal.git
cd vpn9-portal
```

2. Install dependencies:
```bash
bundle install
bun install # or npm install
```

3. Set up environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Set up the database:
```bash
rails db:create
rails db:migrate
rails db:seed # Optional: loads sample data
```

5. Generate JWT keys (development only):
```bash
# Keys are auto-generated in development
# For production, set JWT_PRIVATE_KEY and JWT_PUBLIC_KEY env vars
```

6. Start the development server:
```bash
./bin/dev
```

Visit http://localhost:3000

### Docker Setup

```bash
docker-compose -f docker-compose.dev.yml up
```

## Configuration

### Required Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost/vpn9_production

# JWT Keys (Base64 encoded)
JWT_PRIVATE_KEY=base64_encoded_private_key
JWT_PUBLIC_KEY=base64_encoded_public_key

# Payment Processor
PAYMENT_PROCESSOR=bitcart
BITCART_BASE_URL=http://localhost:8091
BITCART_API_KEY=your_api_key
BITCART_STORE_ID=your_store_id
WEBHOOK_HOST=your-domain.com

# Rails
RAILS_MASTER_KEY=your_master_key
SECRET_KEY_BASE=your_secret_key_base

# Optional
ENABLE_AFFILIATES=true
TEASER_MODE=false # Set to true to show teaser page
```

### Bitcart Setup

VPN9 uses Bitcart for cryptocurrency payment processing. To set up Bitcart:

1. Deploy Bitcart using their Docker setup
2. Create a store in Bitcart admin
3. Configure cryptocurrencies you want to accept
4. Set the API credentials in your environment

## API Documentation

### Public Endpoints

#### Authentication
- `POST /api/v1/auth/token` - Get VPN access token
  - Body: `{ "passphrase": "seven word passphrase here" }`
  - Returns: JWT token valid for 24 hours plus refresh token

- `POST /api/v1/auth/refresh` - Exchange refresh token for new access token
  - Body: `{ "refresh_token": "opaque refresh token" }`
  - Returns: new JWT token and rotated refresh token

- `GET /api/v1/auth/verify` - Verify token validity
  - Header: `Authorization: Bearer <token>`

#### Relays
- `GET /api/v1/relays` - Get list of available VPN servers
  - Header: `Authorization: Bearer <token>`
  - Returns: Array of relay configurations

#### DNS Leak Test
- `GET /api/v1/dns_leak_test` - Test for DNS leaks
- `GET /api/v1/dns_leak_test/results` - Get test results

### Admin API
All admin endpoints require authentication via `/admin/session`

## Testing

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/user_test.rb

# Run system tests
rails test:system
```

## Deployment

### Production Deployment with Kamal

1. Configure `.kamal/secrets` with production credentials
2. Update `config/deploy.yml` with your servers
3. Deploy:
```bash
kamal setup # First time only
kamal deploy
```

### Supply Build Metadata and Digest

During build and deploy, we set immutable build metadata and inject the actual image digest for runtime attestation:

```bash
# Build args (non-sensitive metadata)
docker build \
  --build-arg BUILD_VERSION=$(git describe --tags --always) \
  --build-arg BUILD_COMMIT=$(git rev-parse HEAD) \
  --build-arg BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t docker.io/vpn9/vpn9-portal:$(git describe --tags --always) .

# Push and capture digest
docker push docker.io/vpn9/vpn9-portal:$(git describe --tags --always)
digest=$(docker inspect docker.io/vpn9/vpn9-portal:$(git describe --tags --always) --format='{{index .RepoDigests 0}}' | sed 's/.*@//')
echo "Digest: $digest"

# Deploy behind a read-only Docker socket proxy and allow the app to resolve
# its own image digest via the Docker Engine API (no docker.sock mount).
```

Kubernetes example to pin by digest and surface it in the pod:

```yaml
containers:
  - name: vpn9-portal
    image: docker.io/vpn9/vpn9-portal@sha256:<digest>
    env:
      - name: DOCKER_PROXY_URL
        value: http://127.0.0.1:2375
```

## Image Verification, SBOM, and Attestation

The image embeds non-sensitive build metadata at `/usr/share/vpn9/build-info.json` and exposes a runtime attestation endpoint.

### Verify the running image digest

- Docker:
```bash
docker inspect <container_id> --format '{{.Image}}'
docker inspect docker.io/vpn9/vpn9-portal:<version> --format '{{index .RepoDigests 0}}'
```

- Kubernetes:
```bash
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[?(@.name=="vpn9-portal")].imageID}'
# docker-pullable://docker.io/vpn9/vpn9-portal@sha256:...
```

### Verify signature with Cosign

```bash
cosign verify docker.io/vpn9/vpn9-portal@sha256:<digest>
```

### Check build metadata from inside the container

```bash
cat /usr/share/vpn9/build-info.json
# { "version": "v1.2.3", "commit": "<sha>", "created": "<timestamp>" }
```

Note: In production and other non-development/test environments, the application will refuse to boot if `/usr/share/vpn9/build-info.json` is missing or invalid. This enforces that all deployments are traceable to a specific build.

### Runtime attestation endpoint

- `GET /api/v1/attestation` returns:
  - build_version, build_commit, build_timestamp (from build-info.json/ENV)
  - image_digest (from injected file/env)
  - verification URLs and checksums

- `GET /api/v1/attestation/verify` compares the injected digest to the expected one when provided and includes a signed proof if server keys are configured.

### SBOM and Provenance

- We publish SBOM and provenance alongside releases. Verify that the SBOM corresponds to the signed image digest.

### Recommended user workflow

1. Run a read-only Docker socket proxy on the host and expose it to the app.
2. Do not mount `/var/run/docker.sock` into the app container.
3. The app will query the Engine for its own image and expose the resolved `RepoDigests` in `/api/v1/attestation`.

### Manual Deployment

1. Precompile assets:
```bash
RAILS_ENV=production rails assets:precompile
```

2. Run migrations:
```bash
RAILS_ENV=production rails db:migrate
```

3. Start server:
```bash
RAILS_ENV=production rails server
```

## Privacy & Security

### Zero-Logs Implementation
- No IP addresses stored anywhere in the application
- No connection timestamps or duration tracking
- No device identifiers or fingerprinting
- No correlation between users and relay usage
- Relay servers operate independently without reporting back

### Data Minimization
- Optional email addresses (encrypted if provided)
- Passphrases hashed with Argon2
- Minimal JWT token payload
- No personal information required for signup
- Automatic data deletion for closed accounts

### Security Features
- Argon2id password hashing (memory-hard, resistant to GPU attacks)
- RSA-signed JWT tokens
- Content Security Policy headers
- SQL injection protection via Rails ORM
- XSS protection built into Rails views
- CSRF protection on all forms

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow
1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Code Style
- Follow Ruby Style Guide
- Use Rubocop for linting: `rubocop`
- Keep methods small and focused
- Write descriptive commit messages

## License

This project is open source and available under the [GNU Affero General Public License v3.0 (AGPLv3)](LICENSE).
By using, modifying, or deploying this software as a network service, you agree to the terms of the AGPLv3. See the LICENSE file for details.

## Support

- **VPN9**: [vpn9.com](https://vpn9.com)
- **Issues**: [GitHub Issues](https://github.com/vpn9labs/vpn9-portal/issues)

## Acknowledgments

- Built with Ruby on Rails
- Payment processing by Bitcart
- WireGuard protocol for VPN connections
- Open source community for invaluable tools and libraries

---

**VPN9**: Privacy-first VPN service with open source transparency.
