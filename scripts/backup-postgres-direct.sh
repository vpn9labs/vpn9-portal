#!/bin/bash

# Direct PostgreSQL Backup Script for VPN9 Portal
# This script creates backups directly using docker exec without Kamal

set -e  # Exit on error

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/$(whoami)/pg_backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
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

# Find the database container
log_info "Looking for database container..."
DB_CONTAINER=$(docker ps --filter "label=service=vpn9-portal-db" --format "{{.Names}}" | head -1)

if [ -z "$DB_CONTAINER" ]; then
    # Try alternative methods to find the container
    DB_CONTAINER=$(docker ps --format "table {{.Names}}\t{{.Image}}" | grep postgres | grep vpn9 | awk '{print $1}' | head -1)
fi

if [ -z "$DB_CONTAINER" ]; then
    log_error "Could not find PostgreSQL container. Please check if it's running:"
    docker ps
    exit 1
fi

log_info "Found database container: $DB_CONTAINER"

# Check PostgreSQL version
log_info "PostgreSQL version:"
docker exec "$DB_CONTAINER" psql --version

# Quick backup - full database dump
log_info "Starting full database backup..."
docker exec "$DB_CONTAINER" pg_dumpall -U "$DB_USER" > "$BACKUP_DIR/full_backup_$TIMESTAMP.sql"

if [ $? -eq 0 ]; then
    log_info "✅ Backup successful!"
    
    # Show backup details
    BACKUP_SIZE=$(ls -lh "$BACKUP_DIR/full_backup_$TIMESTAMP.sql" | awk '{print $5}')
    log_info "Backup file: $BACKUP_DIR/full_backup_$TIMESTAMP.sql"
    log_info "Backup size: $BACKUP_SIZE"
    
    # Verify backup content
    LINE_COUNT=$(wc -l < "$BACKUP_DIR/full_backup_$TIMESTAMP.sql")
    log_info "Backup contains $LINE_COUNT lines"
    
    # Optional: Compress the backup
    echo ""
    read -p "Compress the backup? (y/n): " compress
    if [[ $compress =~ ^[Yy]$ ]]; then
        log_info "Compressing backup..."
        gzip -c "$BACKUP_DIR/full_backup_$TIMESTAMP.sql" > "$BACKUP_DIR/full_backup_$TIMESTAMP.sql.gz"
        COMPRESSED_SIZE=$(ls -lh "$BACKUP_DIR/full_backup_$TIMESTAMP.sql.gz" | awk '{print $5}')
        log_info "Compressed backup: $BACKUP_DIR/full_backup_$TIMESTAMP.sql.gz ($COMPRESSED_SIZE)"
        
        read -p "Remove uncompressed backup? (y/n): " remove_uncompressed
        if [[ $remove_uncompressed =~ ^[Yy]$ ]]; then
            rm "$BACKUP_DIR/full_backup_$TIMESTAMP.sql"
            log_info "Uncompressed backup removed"
        fi
    fi
else
    log_error "Backup failed!"
    exit 1
fi

echo ""
log_info "=== Backup Complete ==="
log_info "Timestamp: $TIMESTAMP"
log_info "Location: $BACKUP_DIR"
echo ""
log_info "To restore this backup later, use:"
echo "  cat $BACKUP_DIR/full_backup_$TIMESTAMP.sql | docker exec -i $DB_CONTAINER psql -U $DB_USER postgres"
echo ""
log_info "Or use the restore script:"
echo "  ./scripts/restore-postgres.sh"
