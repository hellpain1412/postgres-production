#!/bin/bash
# PostgreSQL Backup Script

set -e

BACKUP_DIR="/opt/postgresql-production/backups"
CONTAINER_NAME="postgres_prod"
DATE=$(date +%Y%m%d_%H%M%S)

# Source environment variables
source /opt/postgresql-production/.env

# Full backup
docker exec $CONTAINER_NAME pg_dumpall -U $POSTGRES_USER | gzip > $BACKUP_DIR/backup_$DATE.sql.gz

# Remove backups older than 7 days
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +7 -delete

echo "Backup completed: backup_$DATE.sql.gz"
