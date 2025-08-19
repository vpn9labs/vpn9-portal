# VPN9 Portal Reproducible Build Makefile
# This Makefile provides convenient targets for reproducible builds

.PHONY: help build verify push clean publish release

# Default target
help:
	@echo "VPN9 Portal Reproducible Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  make build          - Build reproducible Docker image"
	@echo "  make verify         - Verify build reproducibility"
	@echo "  make push           - Push image to Docker Hub"
	@echo "  make publish        - Build, verify, and push"
	@echo "  make release        - Create a new release with artifacts"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "Environment variables:"
	@echo "  BUILD_VERSION      - Version to build (default: git tag or commit)"
	@echo "  PLATFORM           - Target platform (default: linux/amd64)"
	@echo "  VERIFY_REPRODUCIBLE - Verify build is reproducible (default: false)"
	@echo ""
	@echo "Examples:"
	@echo "  make build BUILD_VERSION=v1.0.0"
	@echo "  make verify BUILD_VERSION=v1.0.0"
	@echo "  make publish BUILD_VERSION=v1.0.0 VERIFY_REPRODUCIBLE=true"

# Configuration
SHELL := /bin/bash
BUILD_VERSION ?= $(shell git describe --tags --always)
BUILD_COMMIT ?= $(shell git rev-parse HEAD)
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct)
IMAGE_NAME ?= vpn9/vpn9-portal
PLATFORM ?= linux/amd64
VERIFY_REPRODUCIBLE ?= false

# Directories
SCRIPTS_DIR := scripts
BUILDS_DIR := builds
ATTESTATION_DIR := $(BUILDS_DIR)/attestations

# Ensure scripts are executable
$(SCRIPTS_DIR)/reproducible-build.sh: $(SCRIPTS_DIR)/reproducible-build.sh
	@chmod +x $@

$(SCRIPTS_DIR)/verify-build.sh: $(SCRIPTS_DIR)/verify-build.sh
	@chmod +x $@

# Build reproducible image
build: $(SCRIPTS_DIR)/reproducible-build.sh
	@echo "Building reproducible image version $(BUILD_VERSION)..."
	@BUILD_VERSION=$(BUILD_VERSION) \
	 BUILD_COMMIT=$(BUILD_COMMIT) \
	 SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
	 IMAGE_NAME=$(IMAGE_NAME) \
	 PLATFORM=$(PLATFORM) \
	 VERIFY_REPRODUCIBLE=$(VERIFY_REPRODUCIBLE) \
	 $(SCRIPTS_DIR)/reproducible-build.sh

# Verify build reproducibility
verify: $(SCRIPTS_DIR)/verify-build.sh
	@echo "Verifying build $(BUILD_VERSION)..."
	@$(SCRIPTS_DIR)/verify-build.sh $(BUILD_VERSION) --rebuild

# Push image to registry
push:
	@echo "Pushing image $(IMAGE_NAME):$(BUILD_VERSION) to registry..."
	@docker push $(IMAGE_NAME):$(BUILD_VERSION)
	@docker push $(IMAGE_NAME):reproducible-$(BUILD_VERSION)
	@echo "Images pushed successfully"

# Build, verify, and push
publish: build
	@if [ "$(VERIFY_REPRODUCIBLE)" = "true" ]; then \
		$(MAKE) verify BUILD_VERSION=$(BUILD_VERSION); \
	fi
	@$(MAKE) push BUILD_VERSION=$(BUILD_VERSION)

# Create release artifacts
release: build
	@echo "Creating release artifacts for $(BUILD_VERSION)..."
	@mkdir -p $(BUILDS_DIR)/release-$(BUILD_VERSION)
	@cp $(BUILDS_DIR)/vpn9-portal-$(BUILD_VERSION).tar* $(BUILDS_DIR)/release-$(BUILD_VERSION)/
	@cp $(BUILDS_DIR)/sbom-$(BUILD_VERSION).spdx $(BUILDS_DIR)/release-$(BUILD_VERSION)/
	@cp $(ATTESTATION_DIR)/attestation-$(BUILD_VERSION).json $(BUILDS_DIR)/release-$(BUILD_VERSION)/
	@cp $(BUILDS_DIR)/build-info-$(BUILD_VERSION).json $(BUILDS_DIR)/release-$(BUILD_VERSION)/
	@cd $(BUILDS_DIR)/release-$(BUILD_VERSION) && \
	 tar czf ../vpn9-portal-$(BUILD_VERSION)-release.tar.gz *
	@echo "Release artifacts created: $(BUILDS_DIR)/vpn9-portal-$(BUILD_VERSION)-release.tar.gz"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILDS_DIR)/*
	@docker buildx rm vpn9-builder 2>/dev/null || true
	@echo "Build artifacts cleaned"

# Development targets
.PHONY: dev-build dev-test

# Build for development (not reproducible)
dev-build:
	@echo "Building development image..."
	@docker build -t $(IMAGE_NAME):dev .

# Test reproducibility locally
dev-test:
	@echo "Testing reproducibility..."
	@SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
	 BUILD_VERSION=test-$(shell date +%s) \
	 VERIFY_REPRODUCIBLE=true \
	 $(MAKE) build