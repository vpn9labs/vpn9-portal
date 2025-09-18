#!/bin/bash

# PostgreSQL Restore Script for VPN9 Portal
# This script restores PostgreSQL backups after upgrading to a new version

set -e  # Exit on error

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/$(whoami)/pg_backups}"
DB_CONTAINER="vpn9-portal-db"
DB_USER="${DB_USER:-vpn9}"
DB_NAME="${DB_NAME:-vpn9_production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

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

# Check PostgreSQL version
log_info "Current PostgreSQL version:"
docker exec "$DB_CONTAINER" psql -U "$DB_USER" -c 'SELECT version();' 2>/dev/null | grep PostgreSQL

# List available backups
log_info "Available backups in $BACKUP_DIR:"
echo ""

if [ -d "$BACKUP_DIR" ]; then
    # List compressed archives
    if ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1 > /dev/null; then
        echo "Compressed archives:"
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " NR ") " $9 " (" $5 ")"}'
        echo ""
    fi
    
    # List SQL files
    if ls "$BACKUP_DIR"/*.sql 2>/dev/null | head -1 > /dev/null; then
        echo "SQL backups:"
        ls -lh "$BACKUP_DIR"/*.sql 2>/dev/null | awk '{print "  " NR ") " $9 " (" $5 ")"}'
        echo ""
    fi
    
    # List dump files
    if ls "$BACKUP_DIR"/*.dump 2>/dev/null | head -1 > /dev/null; then
        echo "Custom format dumps:"
        ls -lh "$BACKUP_DIR"/*.dump 2>/dev/null | awk '{print "  " NR ") " $9 " (" $5 ")"}'
        echo ""
    fi
else
    log_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Get backup file to restore
echo ""
read -p "Enter the full path to the backup file to restore: " backup_file

if [ ! -f "$backup_file" ]; then
    log_error "File not found: $backup_file"
    exit 1
fi

# Extract if compressed
if [[ "$backup_file" == *.tar.gz ]]; then
    log_info "Extracting compressed backup..."
    temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    log_info "Extracted to: $temp_dir"
    
    echo "Extracted files:"
    ls -lh "$temp_dir"
    
    echo ""
    echo "Select file to restore:"
    select extracted_file in "$temp_dir"/*; do
        if [ -n "$extracted_file" ]; then
            backup_file="$extracted_file"
            break
        fi
    done
fi

# Determine backup type and restore method
log_info "Analyzing backup file..."

if [[ "$backup_file" == *full_backup*.sql ]]; then
    log_info "Detected: Full cluster backup"
    restore_type="full"
elif [[ "$backup_file" == *globals*.sql ]]; then
    log_info "Detected: Globals backup (users and roles)"
    restore_type="globals"
elif [[ "$backup_file" == *.dump ]]; then
    log_info "Detected: Custom format database dump"
    restore_type="custom"
elif [[ "$backup_file" == *.sql ]]; then
    log_info "Detected: SQL database dump"
    restore_type="sql"
else
    log_error "Unknown backup format"
    exit 1
fi

# Confirmation
echo ""
log_warn "⚠️  WARNING: This will restore data to the PostgreSQL database."
log_warn "⚠️  Current data may be overwritten!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    log_info "Restore cancelled"
    exit 0
fi

# Stop application if requested
echo ""
read -p "Stop the application during restore? (recommended) (y/n): " stop_app
if [[ $stop_app =~ ^[Yy]$ ]]; then
    log_info "Stopping application..."
    kamal app stop
fi

# Perform restore based on type
case $restore_type in
    full)
        log_info "Restoring full cluster backup..."
        cat "$backup_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" postgres
        ;;
        
    globals)
        log_info "Restoring users and roles..."
        cat "$backup_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" postgres
        ;;
        
    custom)
        log_info "Restoring from custom format dump..."
        
        # Check if database exists
        db_exists=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -w "$DB_NAME" | wc -l)
        
        if [ "$db_exists" -eq 0 ]; then
            log_info "Creating database $DB_NAME..."
            docker exec "$DB_CONTAINER" psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"
        else
            log_warn "Database $DB_NAME already exists"
            read -p "Drop and recreate database? (y/n): " drop_db
            if [[ $drop_db =~ ^[Yy]$ ]]; then
                docker exec "$DB_CONTAINER" psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS $DB_NAME;"
                docker exec "$DB_CONTAINER" psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"
            fi
        fi
        
        cat "$backup_file" | docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$DB_NAME" -v
        ;;
        
    sql)
        log_info "Restoring from SQL dump..."
        
        # Check if this is a database-specific dump or needs target database
        if grep -q "CREATE DATABASE" "$backup_file"; then
            # Full database dump with CREATE DATABASE statement
            cat "$backup_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" postgres
        else
            # Database content only - ensure database exists
            db_exists=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -w "$DB_NAME" | wc -l)
            
            if [ "$db_exists" -eq 0 ]; then
                log_info "Creating database $DB_NAME..."
                docker exec "$DB_CONTAINER" psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"
            fi
            
            cat "$backup_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"
        fi
        ;;
esac

# Post-restore tasks
log_info "Running post-restore tasks..."

# Update statistics
log_info "Updating database statistics..."
docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c 'ANALYZE;'

# Verify restoration
log_info "Verifying restoration..."

# Check tables
table_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c '\dt' | grep -c "table")
log_info "Tables found: $table_count"

# Check some row counts
log_info "Sample row counts:"
for table in users tokens servers locations; do
    count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
    echo "  - $table: $count rows"
done

# Run Rails migrations to ensure schema is current
if [[ $stop_app =~ ^[Yy]$ ]]; then
    log_info "Running Rails database migrations..."
    kamal app boot
    kamal app exec "bin/rails db:migrate"
    
    log_info "Verifying application connectivity..."
    kamal app exec "bin/rails runner 'puts \"Users: #{User.count}\"'"
fi

# Clean up temporary directory if created
if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
    log_info "Cleaning up temporary files..."
    rm -rf "$temp_dir"
fi

# Summary
echo ""
log_info "=== Restore Complete ==="
log_info "Database: $DB_NAME"
log_info "Restored from: $(basename $backup_file)"
echo ""
log_info "Recommended next steps:"
echo "  1. Verify application functionality"
echo "  2. Check application logs: kamal app logs -f"
echo "  3. Monitor database performance"
echo "  4. Run test suite if available"
echo ""

if [[ ! $stop_app =~ ^[Yy]$ ]]; then
    log_warn "Note: Application was not restarted. You may need to restart it manually:"
    echo "  kamal app boot"
fi
