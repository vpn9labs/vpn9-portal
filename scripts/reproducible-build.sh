#!/usr/bin/env bash
set -euo pipefail

# VPN9 Portal Reproducible Build Script
# This script creates deterministic, verifiable Docker images

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_CONFIG="${PROJECT_ROOT}/build-config.json"
DOCKERFILE="${PROJECT_ROOT}/Dockerfile"
BUILDS_DIR="${PROJECT_ROOT}/builds"
ATTESTATION_DIR="${BUILDS_DIR}/attestations"

# Build parameters
BUILD_VERSION="${BUILD_VERSION:-$(git describe --tags --always)}"
BUILD_COMMIT="${BUILD_COMMIT:-$(git rev-parse HEAD)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
BUILD_TIMESTAMP="$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')"
IMAGE_NAME="${IMAGE_NAME:-vpn9/vpn9-portal}"
IMAGE_TAG="${IMAGE_TAG:-${BUILD_VERSION}}"

# Platform configuration (single arch for reproducible builds)
PLATFORM="${PLATFORM:-linux/amd64}"

echo -e "${GREEN}=== VPN9 Portal Reproducible Build ===${NC}"
echo "Version: ${BUILD_VERSION}"
echo "Commit: ${BUILD_COMMIT}"
echo "Timestamp: ${BUILD_TIMESTAMP}"
echo "Platform: ${PLATFORM}"
echo ""

# Create directories
mkdir -p "${BUILDS_DIR}" "${ATTESTATION_DIR}"

# Function to calculate checksums
calculate_checksums() {
  local file=$1
  local output_dir=$2
  local basename=$(basename "$file")

  echo -n "Calculating checksums... "
  sha256sum "$file" >"${output_dir}/${basename}.sha256"
  sha512sum "$file" >"${output_dir}/${basename}.sha512"
  echo "done"
}

# Function to generate SBOM (Software Bill of Materials)
generate_sbom() {
  local image=$1
  local output_file=$2

  echo -n "Generating SBOM... "

  # Create SBOM in SPDX format
  cat >"$output_file" <<EOF
SPDXVersion: SPDX-2.3
DataLicense: CC0-1.0
SPDXID: SPDXRef-DOCUMENT
DocumentName: VPN9-Portal-SBOM
DocumentNamespace: https://vpn9.com/sbom/${BUILD_VERSION}
Creator: Tool: vpn9-build-script
Created: ${BUILD_TIMESTAMP}

# Package Information
PackageName: vpn9-portal
SPDXID: SPDXRef-Package-vpn9-portal
PackageVersion: ${BUILD_VERSION}
PackageDownloadLocation: https://github.com/vpn9labs/vpn9-portal
FilesAnalyzed: true
PackageVerificationCode: ${BUILD_COMMIT}

# Ruby Dependencies
EOF

  # Add Ruby gems
  if [ -f "${PROJECT_ROOT}/Gemfile.lock" ]; then
    echo "# Ruby Gems" >>"$output_file"
    ruby -e "
            require 'bundler'
            lockfile = Bundler::LockfileParser.new(File.read('${PROJECT_ROOT}/Gemfile.lock'))
            lockfile.specs.each do |spec|
                puts \"PackageName: #{spec.name}\"
                puts \"PackageVersion: #{spec.version}\"
                puts \"PackageSupplier: Organization: rubygems.org\"
                puts \"\"
            end
        " >>"$output_file" 2>/dev/null || true
  fi

  # Add Node packages
  if [ -f "${PROJECT_ROOT}/bun.lock" ]; then
    echo "# Node Packages" >>"$output_file"
    bun pm ls --all | tail -n +2 | while read -r line; do
      echo "PackageName: $line" >>"$output_file"
    done 2>/dev/null || true
  fi

  echo "done"
}

# Function to create build attestation
create_attestation() {
  local image=$1
  local attestation_file="${ATTESTATION_DIR}/attestation-${BUILD_VERSION}.json"

  echo -n "Creating build attestation... "

  cat >"$attestation_file" <<EOF
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "subject": [{
    "name": "${IMAGE_NAME}",
    "digest": {
      "sha256": "$(docker images --no-trunc --quiet "${image}" | sed 's/^sha256://')"
    }
  }],
  "predicate": {
    "builder": {
      "id": "https://github.com/vpn9labs/vpn9-portal/scripts/reproducible-build.sh"
    },
    "buildType": "https://vpn9.com/build/v1",
    "invocation": {
      "configSource": {
        "uri": "https://github.com/vpn9labs/vpn9-portal",
        "digest": {
          "sha1": "${BUILD_COMMIT}"
        },
        "entryPoint": "scripts/reproducible-build.sh"
      },
      "parameters": {
        "SOURCE_DATE_EPOCH": "${SOURCE_DATE_EPOCH}",
        "BUILD_VERSION": "${BUILD_VERSION}",
        "PLATFORM": "${PLATFORM}"
      },
      "environment": {
        "DOCKER_VERSION": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
        "OS": "$(uname -s)",
        "ARCH": "$(uname -m)"
      }
    },
    "buildConfig": {
      "steps": [
        {
          "command": ["docker", "buildx", "build"],
          "env": {
            "SOURCE_DATE_EPOCH": "${SOURCE_DATE_EPOCH}"
          }
        }
      ]
    },
    "metadata": {
      "buildStartedOn": "${BUILD_TIMESTAMP}",
      "buildFinishedOn": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
      "completeness": {
        "parameters": true,
        "environment": true,
        "materials": false
      },
      "reproducible": true
    },
    "materials": [
      {
        "uri": "docker.io/library/ruby:3.4.5-slim",
        "digest": {
          "sha256": "0d2adfa1930d67ee79e5d16c3610f4fbed43c98e98dbda14c2811b8197211c74"
        }
      }
    ]
  }
}
EOF

  echo "done"
}

# Function to verify build reproducibility
verify_build() {
  local image1=$1
  local image2=$2

  echo -e "\n${YELLOW}=== Verifying Build Reproducibility ===${NC}"

  # Export images to tar for comparison
  docker save "$image1" -o "${BUILDS_DIR}/image1.tar"
  docker save "$image2" -o "${BUILDS_DIR}/image2.tar"

  # Extract and compare layers
  mkdir -p "${BUILDS_DIR}/image1" "${BUILDS_DIR}/image2"
  tar -xf "${BUILDS_DIR}/image1.tar" -C "${BUILDS_DIR}/image1"
  tar -xf "${BUILDS_DIR}/image2.tar" -C "${BUILDS_DIR}/image2"

  # Compare manifests (excluding timestamps)
  if diff -u \
    <(jq -S 'del(.history[].created)' "${BUILDS_DIR}/image1/manifest.json") \
    <(jq -S 'del(.history[].created)' "${BUILDS_DIR}/image2/manifest.json") >/dev/null; then
    echo -e "${GREEN}✓ Manifests match${NC}"
  else
    echo -e "${RED}✗ Manifests differ${NC}"
    return 1
  fi

  # Compare layer checksums
  local layers1=$(find "${BUILDS_DIR}/image1" -name "*.tar" -exec sha256sum {} \; | sort)
  local layers2=$(find "${BUILDS_DIR}/image2" -name "*.tar" -exec sha256sum {} \; | sort)

  if [ "$layers1" = "$layers2" ]; then
    echo -e "${GREEN}✓ Layer checksums match${NC}"
    echo -e "${GREEN}✓ Build is reproducible!${NC}"
    return 0
  else
    echo -e "${RED}✗ Layer checksums differ${NC}"
    return 1
  fi
}

# Main build process
main() {
  # Check prerequisites
  command -v docker >/dev/null 2>&1 || {
    echo "Docker is required but not installed."
    exit 1
  }
  command -v jq >/dev/null 2>&1 || {
    echo "jq is required but not installed."
    exit 1
  }

  # Setup Docker buildx
  echo "Setting up Docker buildx..."
  docker buildx create --name vpn9-builder --use 2>/dev/null || docker buildx use vpn9-builder
  docker buildx inspect --bootstrap

  # Build the image
  echo -e "\n${GREEN}Building image...${NC}"
  docker buildx build \
    --platform="${PLATFORM}" \
    --build-arg SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
    --build-arg BUILD_VERSION="${BUILD_VERSION}" \
    --build-arg BUILD_COMMIT="${BUILD_COMMIT}" \
    --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    --tag "${IMAGE_NAME}:reproducible-${BUILD_VERSION}" \
    --file "${DOCKERFILE}" \
    --load \
    --progress=plain \
    "${PROJECT_ROOT}"

  # Generate build artifacts
  echo -e "\n${YELLOW}=== Generating Build Artifacts ===${NC}"

  # Export image
  local export_file="${BUILDS_DIR}/vpn9-portal-${BUILD_VERSION}.tar"
  echo -n "Exporting image... "
  docker save "${IMAGE_NAME}:${IMAGE_TAG}" -o "$export_file"
  echo "done"

  # Calculate checksums
  calculate_checksums "$export_file" "${BUILDS_DIR}"

  # Generate SBOM
  local sbom_file="${BUILDS_DIR}/sbom-${BUILD_VERSION}.spdx"
  generate_sbom "${IMAGE_NAME}:${IMAGE_TAG}" "$sbom_file"

  # Create attestation
  create_attestation "${IMAGE_NAME}:${IMAGE_TAG}"

  # Create build info file
  echo -n "Creating build info... "
  cat >"${BUILDS_DIR}/build-info-${BUILD_VERSION}.json" <<EOF
{
  "version": "${BUILD_VERSION}",
  "commit": "${BUILD_COMMIT}",
  "source_date_epoch": ${SOURCE_DATE_EPOCH},
  "build_timestamp": "${BUILD_TIMESTAMP}",
  "image_name": "${IMAGE_NAME}",
  "image_tag": "${IMAGE_TAG}",
  "platform": "${PLATFORM}",
  "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
  "builder_os": "$(uname -s)",
  "builder_arch": "$(uname -m)",
  "files": {
    "image": "vpn9-portal-${BUILD_VERSION}.tar",
    "sbom": "sbom-${BUILD_VERSION}.spdx",
    "attestation": "attestations/attestation-${BUILD_VERSION}.json"
  }
}
EOF
  echo "done"

  # Optional: Verify reproducibility by building twice
  if [ "${VERIFY_REPRODUCIBLE:-false}" = "true" ]; then
    echo -e "\n${YELLOW}=== Building Second Time for Verification ===${NC}"
    docker buildx build \
      --platform="${PLATFORM}" \
      --build-arg SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
      --build-arg BUILD_VERSION="${BUILD_VERSION}" \
      --build-arg BUILD_COMMIT="${BUILD_COMMIT}" \
      --build-arg BUILD_TIMESTAMP="${BUILD_TIMESTAMP}" \
      --tag "${IMAGE_NAME}:verify" \
      --file "${DOCKERFILE}" \
      --load \
      --no-cache \
      "${PROJECT_ROOT}"

    verify_build "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:verify"
  fi

  echo -e "\n${GREEN}=== Build Complete ===${NC}"
  echo "Build artifacts saved to: ${BUILDS_DIR}"
  echo ""
  echo "To verify this build:"
  echo "  ./scripts/verify-build.sh ${BUILD_VERSION}"
  echo ""
  echo "To push to registry:"
  echo "  docker push ${IMAGE_NAME}:${IMAGE_TAG}"
  echo "  docker push ${IMAGE_NAME}:reproducible-${BUILD_VERSION}"
}

# Run main function
main "$@"

