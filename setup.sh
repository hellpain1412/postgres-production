#!/bin/bash

# PostgreSQL Production Setup Script for Fedora
# Run as root or with sudo

set -e

echo "=== PostgreSQL Production Setup trên Fedora ==="
echo ""

# 1. Cài đặt Docker và Docker Compose
echo "Step 1: Cài đặt Docker..."
if ! command -v docker &> /dev/null; then
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo "Docker đã được cài đặt!"
else
    echo "Docker đã được cài đặt trước đó."
fi

# 2. Tạo cấu trúc thư mục
echo ""
echo "Step 2: Tạo cấu trúc thư mục..."
PROJECT_DIR="/opt/postgresql-production"
sudo mkdir -p $PROJECT_DIR/{backups/wal,init-scripts,logs}
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
    
    sudo cat > .env << EOF
POSTGRES_USER=$pg_user
POSTGRES_PASSWORD=$pg_pass
POSTGRES_DB=$pg_db
PGADMIN_EMAIL=admin@localhost.local
PGADMIN_PASSWORD=admin123
TZ=Asia/Ho_Chi_Minh
EOF
    sudo chmod 600 .env
    echo ".env đã được tạo!"
else
    echo "File .env đã tồn tại."
fi

# 4. Set quyền
echo ""
echo "Step 4: Thiết lập quyền..."
sudo chown -R 999:999 $PROJECT_DIR/backups
sudo chmod 755 $PROJECT_DIR/backups

# 5. Cấu hình firewall
echo ""
echo "Step 5: Cấu hình firewall..."
read -p "Bạn có muốn mở port PostgreSQL (5432) qua firewall? [y/N]: " open_firewall
if [[ $open_firewall == "y" || $open_firewall == "Y" ]]; then
    sudo firewall-cmd --permanent --add-port=5432/tcp
    sudo firewall-cmd --reload
    echo "Port 5432 đã được mở."
else
    echo "Bỏ qua cấu hình firewall."
fi

# 6. Tạo systemd service
echo ""
echo "Step 6: Tạo systemd service..."
sudo cat > /etc/systemd/system/postgresql-docker.service << 'EOF'
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

sudo systemctl daemon-reload
sudo systemctl enable postgresql-docker.service
echo "Systemd service đã được tạo và enable!"

# 7. Tạo backup script
echo ""
echo "Step 7: Tạo backup script..."
sudo cat > $PROJECT_DIR/backup.sh << 'EOF'
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

sudo chmod +x $PROJECT_DIR/backup.sh

# 8. Cấu hình cron cho backup
echo ""
echo "Step 8: Cấu hình backup tự động..."
read -p "Bạn có muốn thiết lập backup tự động hàng ngày? [y/N]: " setup_cron
if [[ $setup_cron == "y" || $setup_cron == "Y" ]]; then
    (sudo crontab -l 2>/dev/null; echo "0 2 * * * $PROJECT_DIR/backup.sh >> $PROJECT_DIR/logs/backup.log 2>&1") | sudo crontab -
    echo "Đã thiết lập backup tự động lúc 2:00 sáng hàng ngày."
fi

# 9. SELinux configuration (nếu enabled)
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo ""
    echo "Step 9: Cấu hình SELinux..."
    sudo semanage fcontext -a -t container_file_t "$PROJECT_DIR(/.*)?" 2>/dev/null || true
    sudo restorecon -Rv $PROJECT_DIR
fi

echo ""
echo "=== Setup hoàn tất! ==="
echo ""
echo "Các bước tiếp theo:"
echo "1. Copy file docker-compose.yml, postgresql.conf vào $PROJECT_DIR"
echo "2. Chỉnh sửa file .env tại $PROJECT_DIR/.env"
echo "3. Chạy: cd $PROJECT_DIR && sudo docker compose up -d"
echo "4. Kiểm tra logs: sudo docker compose logs -f postgres"
echo ""
echo "Quản lý service:"
echo "- Start:  sudo systemctl start postgresql-docker"
echo "- Stop:   sudo systemctl stop postgresql-docker"
echo "- Status: sudo systemctl status postgresql-docker"
echo ""
echo "Backup thủ công: sudo $PROJECT_DIR/backup.sh"
echo ""