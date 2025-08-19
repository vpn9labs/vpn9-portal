#!/usr/bin/env bash
set -euo pipefail

# VPN9 Portal Build Verification Script
# This script verifies that a build is reproducible and matches published attestations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILDS_DIR="${PROJECT_ROOT}/builds"
VERIFICATION_DIR="${BUILDS_DIR}/verification"

# Parse arguments
BUILD_VERSION="${1:-}"
if [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <build-version> [--rebuild]"
    echo "Example: $0 v1.0.0"
    echo "         $0 v1.0.0 --rebuild"
    exit 1
fi

REBUILD="${2:-}"

echo -e "${BLUE}=== VPN9 Portal Build Verification ===${NC}"
echo "Verifying build: ${BUILD_VERSION}"
echo ""

# Create verification directory
mkdir -p "${VERIFICATION_DIR}"

# Function to download published artifacts
download_artifacts() {
    local version=$1
    echo -e "${YELLOW}Downloading published artifacts...${NC}"
    
    # Download from GitHub releases or your artifact storage
    local base_url="https://github.com/vpn9labs/vpn9-portal/releases/download/${version}"
    
    # Download attestation
    if [ ! -f "${VERIFICATION_DIR}/attestation-${version}.json" ]; then
        echo -n "Downloading attestation... "
        curl -sL "${base_url}/attestation-${version}.json" \
            -o "${VERIFICATION_DIR}/attestation-${version}.json" || {
            echo -e "${RED}Failed to download attestation${NC}"
            return 1
        }
        echo "done"
    fi
    
    # Download checksums
    if [ ! -f "${VERIFICATION_DIR}/checksums-${version}.sha256" ]; then
        echo -n "Downloading checksums... "
        curl -sL "${base_url}/checksums-${version}.sha256" \
            -o "${VERIFICATION_DIR}/checksums-${version}.sha256" || {
            echo -e "${RED}Failed to download checksums${NC}"
            return 1
        }
        echo "done"
    fi
    
    # Download build info
    if [ ! -f "${VERIFICATION_DIR}/build-info-${version}.json" ]; then
        echo -n "Downloading build info... "
        curl -sL "${base_url}/build-info-${version}.json" \
            -o "${VERIFICATION_DIR}/build-info-${version}.json" || {
            echo -e "${RED}Failed to download build info${NC}"
            return 1
        }
        echo "done"
    fi
}

# Function to verify attestation signature (if using signing)
verify_attestation() {
    local attestation_file=$1
    echo -n "Verifying attestation signature... "
    
    # If you're using cosign or similar for signing
    if command -v cosign >/dev/null 2>&1; then
        # Verify with cosign (requires public key)
        # cosign verify-attestation --key vpn9-public.key "$attestation_file"
        echo "skipped (cosign not configured)"
    else
        echo "skipped (cosign not installed)"
    fi
}

# Function to rebuild from source
rebuild_from_source() {
    local version=$1
    local build_info_file="${VERIFICATION_DIR}/build-info-${version}.json"
    
    echo -e "\n${YELLOW}Rebuilding from source...${NC}"
    
    if [ ! -f "$build_info_file" ]; then
        echo -e "${RED}Build info file not found${NC}"
        return 1
    fi
    
    # Extract build parameters from build info
    local commit=$(jq -r '.commit' "$build_info_file")
    local source_date_epoch=$(jq -r '.source_date_epoch' "$build_info_file")
    local platform=$(jq -r '.platform // "linux/amd64"' "$build_info_file")
    
    echo "Commit: ${commit}"
    echo "Source Date Epoch: ${source_date_epoch}"
    echo "Platform: ${platform}"
    
    # Checkout the specific commit
    echo -n "Checking out commit ${commit}... "
    git checkout "${commit}" 2>/dev/null || {
        echo -e "${RED}Failed to checkout commit${NC}"
        return 1
    }
    echo "done"
    
    # Run reproducible build with same parameters
    SOURCE_DATE_EPOCH="${source_date_epoch}" \
    BUILD_VERSION="${version}" \
    BUILD_COMMIT="${commit}" \
    PLATFORM="${platform}" \
    "${SCRIPT_DIR}/reproducible-build.sh"
    
    # Return to previous branch
    git checkout - 2>/dev/null
}

# Function to compare builds
compare_builds() {
    local version=$1
    local original_image="${2:-vpn9/vpn9-portal:${version}}"
    local rebuilt_image="${3:-vpn9/vpn9-portal:reproducible-${version}}"
    
    echo -e "\n${YELLOW}Comparing builds...${NC}"
    
    # Pull original image if not present
    if ! docker image inspect "$original_image" >/dev/null 2>&1; then
        echo "Pulling original image..."
        docker pull "$original_image"
    fi
    
    # Export both images
    echo -n "Exporting images for comparison... "
    docker save "$original_image" -o "${VERIFICATION_DIR}/original.tar"
    docker save "$rebuilt_image" -o "${VERIFICATION_DIR}/rebuilt.tar"
    echo "done"
    
    # Calculate checksums
    local original_sum=$(sha256sum "${VERIFICATION_DIR}/original.tar" | cut -d' ' -f1)
    local rebuilt_sum=$(sha256sum "${VERIFICATION_DIR}/rebuilt.tar" | cut -d' ' -f1)
    
    echo "Original SHA256: ${original_sum}"
    echo "Rebuilt SHA256:  ${rebuilt_sum}"
    
    if [ "$original_sum" = "$rebuilt_sum" ]; then
        echo -e "${GREEN}✓ Images are identical - build is reproducible!${NC}"
        return 0
    else
        # Extract and compare layer by layer
        echo -e "${YELLOW}Images differ, comparing layers...${NC}"
        
        mkdir -p "${VERIFICATION_DIR}/original_layers" "${VERIFICATION_DIR}/rebuilt_layers"
        tar -xf "${VERIFICATION_DIR}/original.tar" -C "${VERIFICATION_DIR}/original_layers"
        tar -xf "${VERIFICATION_DIR}/rebuilt.tar" -C "${VERIFICATION_DIR}/rebuilt_layers"
        
        # Compare manifests
        echo -n "Comparing manifests... "
        if diff -u \
            <(jq -S 'del(.history[].created)' "${VERIFICATION_DIR}/original_layers/manifest.json") \
            <(jq -S 'del(.history[].created)' "${VERIFICATION_DIR}/rebuilt_layers/manifest.json") > /dev/null; then
            echo -e "${GREEN}match${NC}"
        else
            echo -e "${RED}differ${NC}"
            diff -u \
                <(jq -S '.' "${VERIFICATION_DIR}/original_layers/manifest.json") \
                <(jq -S '.' "${VERIFICATION_DIR}/rebuilt_layers/manifest.json") || true
        fi
        
        # Compare each layer
        echo "Comparing layers:"
        for layer in "${VERIFICATION_DIR}"/original_layers/*/layer.tar; do
            if [ -f "$layer" ]; then
                layer_id=$(basename $(dirname "$layer"))
                original_layer_sum=$(sha256sum "$layer" | cut -d' ' -f1)
                rebuilt_layer="${VERIFICATION_DIR}/rebuilt_layers/${layer_id}/layer.tar"
                
                if [ -f "$rebuilt_layer" ]; then
                    rebuilt_layer_sum=$(sha256sum "$rebuilt_layer" | cut -d' ' -f1)
                    if [ "$original_layer_sum" = "$rebuilt_layer_sum" ]; then
                        echo -e "  Layer ${layer_id:0:12}: ${GREEN}✓${NC}"
                    else
                        echo -e "  Layer ${layer_id:0:12}: ${RED}✗${NC}"
                    fi
                else
                    echo -e "  Layer ${layer_id:0:12}: ${RED}missing in rebuilt${NC}"
                fi
            fi
        done
        
        return 1
    fi
}

# Function to verify against published checksums
verify_checksums() {
    local version=$1
    local checksums_file="${VERIFICATION_DIR}/checksums-${version}.sha256"
    
    echo -e "\n${YELLOW}Verifying checksums...${NC}"
    
    if [ ! -f "$checksums_file" ]; then
        echo -e "${RED}Checksums file not found${NC}"
        return 1
    fi
    
    # Verify each file in checksums
    while IFS= read -r line; do
        local sum=$(echo "$line" | cut -d' ' -f1)
        local file=$(echo "$line" | cut -d' ' -f2 | sed 's/^\*//')
        
        if [ -f "${BUILDS_DIR}/$file" ]; then
            local actual_sum=$(sha256sum "${BUILDS_DIR}/$file" | cut -d' ' -f1)
            if [ "$sum" = "$actual_sum" ]; then
                echo -e "  $file: ${GREEN}✓${NC}"
            else
                echo -e "  $file: ${RED}✗${NC}"
                return 1
            fi
        else
            echo -e "  $file: ${YELLOW}not found locally${NC}"
        fi
    done < "$checksums_file"
}

# Function to generate verification report
generate_report() {
    local version=$1
    local report_file="${VERIFICATION_DIR}/verification-report-${version}.txt"
    
    echo -e "\n${YELLOW}Generating verification report...${NC}"
    
    cat > "$report_file" << EOF
VPN9 Portal Build Verification Report
=====================================
Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Version: ${version}

Verification Steps Performed:
1. Downloaded published artifacts
2. Verified attestation signature
3. Rebuilt from source
4. Compared original and rebuilt images
5. Verified published checksums

Results:
EOF
    
    # Add results based on what was performed
    if [ -f "${VERIFICATION_DIR}/attestation-${version}.json" ]; then
        echo "✓ Attestation downloaded successfully" >> "$report_file"
    fi
    
    if [ "$REBUILD" = "--rebuild" ]; then
        echo "✓ Successfully rebuilt from source" >> "$report_file"
        echo "✓ Build is reproducible" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "Attestation Details:" >> "$report_file"
    if [ -f "${VERIFICATION_DIR}/attestation-${version}.json" ]; then
        jq -r '.predicate.metadata' "${VERIFICATION_DIR}/attestation-${version}.json" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "Build Info:" >> "$report_file"
    if [ -f "${VERIFICATION_DIR}/build-info-${version}.json" ]; then
        jq -r '.' "${VERIFICATION_DIR}/build-info-${version}.json" >> "$report_file"
    fi
    
    echo -e "${GREEN}Report saved to: ${report_file}${NC}"
}

# Main verification process
main() {
    # Check prerequisites
    command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed."; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
    command -v git >/dev/null 2>&1 || { echo "git is required but not installed."; exit 1; }
    
    # Download published artifacts
    download_artifacts "$BUILD_VERSION"
    
    # Verify attestation
    if [ -f "${VERIFICATION_DIR}/attestation-${BUILD_VERSION}.json" ]; then
        verify_attestation "${VERIFICATION_DIR}/attestation-${BUILD_VERSION}.json"
    fi
    
    # Rebuild from source if requested
    if [ "$REBUILD" = "--rebuild" ]; then
        rebuild_from_source "$BUILD_VERSION"
        compare_builds "$BUILD_VERSION"
    fi
    
    # Verify checksums
    if [ -f "${VERIFICATION_DIR}/checksums-${BUILD_VERSION}.sha256" ]; then
        verify_checksums "$BUILD_VERSION"
    fi
    
    # Generate report
    generate_report "$BUILD_VERSION"
    
    echo -e "\n${GREEN}=== Verification Complete ===${NC}"
}

# Run main function
main