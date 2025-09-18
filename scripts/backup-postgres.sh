#!/bin/bash

# PostgreSQL Backup Script for VPN9 Portal
# This script creates backups of the PostgreSQL database before upgrading

set -xe  # Exit on error

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/$(whoami)/pg_backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_CONTAINER="vpn9-portal-db"
# DB_CONTAINER="14b35ab3a0fa"
DB_USER="${DB_USER:-vpn9}"
DB_NAME="${DB_NAME:-vpn9_production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create backup directory
log_info "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Check if kamal is available
if ! command -v kamal &> /dev/null; then
    log_error "kamal command not found. Please ensure Kamal is installed."
    exit 1
fi

# Check if database container is running
log_info "Checking database container status..."
if ! kamal accessory details db &> /dev/null; then
    log_error "Database container is not running or accessible"
    exit 1
fi

# Get the actual container name
DB_CONTAINER=$(docker ps --filter "label=service=vpn9-portal-db" --format "{{.Names}}" | head -1)
if [ -z "$DB_CONTAINER" ]; then
    log_error "Could not find database container"
    exit 1
fi
log_info "Found database container: $DB_CONTAINER"

# Backup type selection
echo ""
echo "Select backup type:"
echo "1) Full cluster backup (all databases, users, roles)"
echo "2) Single database backup (vpn9_production only)"
echo "3) Both"
read -p "Enter choice [1-3]: " backup_choice

case $backup_choice in
    1|3)
        log_info "Creating full cluster backup..."
        docker exec "$DB_CONTAINER" \
            pg_dumpall -U "$DB_USER" > "$BACKUP_DIR/full_backup_$TIMESTAMP.sql"
        
        if [ $? -eq 0 ]; then
            log_info "Full backup saved to: $BACKUP_DIR/full_backup_$TIMESTAMP.sql"
            ls -lh "$BACKUP_DIR/full_backup_$TIMESTAMP.sql"
        else
            log_error "Full backup failed"
            exit 1
        fi
        ;;&  # Continue to next matching pattern
        
    2|3)
        log_info "Creating database-specific backup..."
        
        # Create custom format dump (for faster restore)
        log_info "Creating compressed dump..."
        docker exec "$DB_CONTAINER" \
            pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc -v > "$BACKUP_DIR/${DB_NAME}_$TIMESTAMP.dump" 2>/dev/null
        
        # Create plain SQL dump (for compatibility)
        log_info "Creating SQL dump..."
        docker exec "$DB_CONTAINER" \
            pg_dump -U "$DB_USER" -d "$DB_NAME" --no-owner --no-privileges > "$BACKUP_DIR/${DB_NAME}_$TIMESTAMP.sql"
        
        # Dump globals
        log_info "Backing up users and roles..."
        docker exec "$DB_CONTAINER" \
            pg_dumpall -U "$DB_USER" --globals-only > "$BACKUP_DIR/globals_$TIMESTAMP.sql"
        
        if [ $? -eq 0 ]; then
            log_info "Database backup saved to:"
            ls -lh "$BACKUP_DIR/${DB_NAME}_$TIMESTAMP."*
            ls -lh "$BACKUP_DIR/globals_$TIMESTAMP.sql"
        else
            log_error "Database backup failed"
            exit 1
        fi
        ;;
        
    *)
        log_error "Invalid choice"
        exit 1
        ;;
esac

# Verify backups
log_info "Verifying backup integrity..."

for file in "$BACKUP_DIR"/*_$TIMESTAMP.*; do
    if [ -f "$file" ]; then
        # Check if file is not empty
        if [ -s "$file" ]; then
            # Check first few lines for SQL content
            if head -5 "$file" | grep -q "PostgreSQL\|CREATE\|INSERT\|--"; then
                log_info "✓ $(basename $file) appears valid"
            else
                log_warn "⚠ $(basename $file) may have issues - please verify manually"
            fi
        else
            log_error "✗ $(basename $file) is empty!"
        fi
    fi
done

# Compression option
echo ""
read -p "Compress backups? (y/n): " compress_choice
if [[ $compress_choice =~ ^[Yy]$ ]]; then
    log_info "Compressing backups..."
    cd "$BACKUP_DIR"
    tar -czf "pg_backup_$TIMESTAMP.tar.gz" *_$TIMESTAMP.*
    log_info "Compressed archive created: $BACKUP_DIR/pg_backup_$TIMESTAMP.tar.gz"
    ls -lh "$BACKUP_DIR/pg_backup_$TIMESTAMP.tar.gz"
    
    read -p "Remove uncompressed files? (y/n): " remove_choice
    if [[ $remove_choice =~ ^[Yy]$ ]]; then
        rm -f *_$TIMESTAMP.sql *_$TIMESTAMP.dump
        log_info "Uncompressed files removed"
    fi
fi

# Summary
echo ""
log_info "=== Backup Complete ==="
log_info "Backup location: $BACKUP_DIR"
log_info "Timestamp: $TIMESTAMP"
echo ""
log_info "Next steps:"
echo "  1. Verify the backup files"
echo "  2. Copy backups to a safe location"
echo "  3. Update config/deploy.yml to use postgres:18-beta3"
echo "  4. Run the migration"
echo ""
log_warn "Remember to test the upgrade in a staging environment first!"
