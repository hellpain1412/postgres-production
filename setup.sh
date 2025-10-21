#!/bin/bash

# PostgreSQL Production Setup Script for Fedora
# Run as root or with

set -e

echo "=== PostgreSQL Production Setup trên Fedora ==="
echo ""

# 1. Cài đặt Docker và Docker Compose
# echo "Step 1: Cài đặt Docker..."
# if ! command -v docker &> /dev/null; then
#      dnf -y install dnf-plugins-core
#      dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
#      dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
#      systemctl start docker
#      systemctl enable docker
#      usermod -aG docker $USER
#     echo "Docker đã được cài đặt!"
# else
#     echo "Docker đã được cài đặt trước đó."
# fi

# 2. Tạo cấu trúc thư mục
echo ""
echo "Step 2: Tạo cấu trúc thư mục..."
PROJECT_DIR=$(pwd)
mkdir -p $PROJECT_DIR/{backups/wal,init-scripts,logs}
cd $PROJECT_DIR

# 3. Tạo file .env (nếu chưa có)
if [ ! -f .env ]; then
    echo ""
    echo "Step 3: Tạo file .env..."
    read -p "Nhập PostgreSQL username [postgres]: " pg_user
    pg_user=${pg_user:-postgres}
    
    read -sp "Nhập PostgreSQL password: " pg_pass
    pg_pass=${pg_pass:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-32)}
    echo ""
    
    read -p "Nhập tên database [production_db]: " pg_db
    pg_db=${pg_db:-production_db}
    
     cat > .env << EOF
POSTGRES_USER=$pg_user
POSTGRES_PASSWORD=$pg_pass
POSTGRES_DB=$pg_db
PGADMIN_EMAIL=tienpham.hust@gmail.com
PGADMIN_PASSWORD=admin123
TZ=Asia/Ho_Chi_Minh
EOF
    chmod 600 .env
    echo ".env đã được tạo!"
else
    echo "File .env đã tồn tại."
fi

# 4. Set quyền
echo ""
echo "Step 4: Thiết lập quyền..."
chown -R 999:999 $PROJECT_DIR/backups
chmod 755 $PROJECT_DIR/backups

# 5. Cấu hình firewall
echo ""
echo "Step 5: Cấu hình firewall..."
read -p "Bạn có muốn mở port PostgreSQL (5432) qua firewall? [y/N]: " open_firewall
if [[ $open_firewall == "y" || $open_firewall == "Y" ]]; then
    firewall-cmd --permanent --add-port=5432/tcp
    firewall-cmd --reload
    echo "Port 5432 đã được mở."
else
    echo "Bỏ qua cấu hình firewall."
fi

# 6. Tạo systemd service
echo ""
echo "Step 6: Tạo systemd service..."
 cat > /etc/systemd/system/postgresql-docker.service << 'EOF'
[Unit]
Description=PostgreSQL Docker Container
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/postgresql-production
ExecStart=/usr/bin/docker compose up -d postgres
ExecStop=/usr/bin/docker compose down
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable postgresql-docker.service
echo "Systemd service đã được tạo và enable!"

# 7. Tạo backup script
echo ""
echo "Step 7: Tạo backup script..."
 cat > $PROJECT_DIR/backup.sh << 'EOF'
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
EOF

chmod +x $PROJECT_DIR/backup.sh

# 8. Cấu hình cron cho backup
echo ""
echo "Step 8: Cấu hình backup tự động..."
read -p "Bạn có muốn thiết lập backup tự động hàng ngày? [y/N]: " setup_cron
if [[ $setup_cron == "y" || $setup_cron == "Y" ]]; then
    ( crontab -l 2>/dev/null; echo "0 2 * * * $PROJECT_DIR/backup.sh >> $PROJECT_DIR/logs/backup.log 2>&1") |  crontab -
    echo "Đã thiết lập backup tự động lúc 2:00 sáng hàng ngày."
fi

# 9. SELinux configuration (nếu enabled)
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo ""
    echo "Step 9: Cấu hình SELinux..."
    semanage fcontext -a -t container_file_t "$PROJECT_DIR(/.*)?" 2>/dev/null || true
    restorecon -Rv $PROJECT_DIR
fi

echo ""
echo "=== Setup hoàn tất! ==="
echo ""
echo "Các bước tiếp theo:"
echo "1. Copy file docker-compose.yml, postgresql.conf vào $PROJECT_DIR"
echo "2. Chỉnh sửa file .env tại $PROJECT_DIR/.env"
echo "3. Chạy: cd $PROJECT_DIR &&  docker compose up -d"
echo "4. Kiểm tra logs:  docker compose logs -f postgres"
echo ""
echo "Quản lý service:"
echo "- Start:   systemctl start postgresql-docker"
echo "- Stop:    systemctl stop postgresql-docker"
echo "- Status:  systemctl status postgresql-docker"
echo ""
echo "Backup thủ công:  $PROJECT_DIR/backup.sh"
echo ""