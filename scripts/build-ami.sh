#!/bin/bash
set -e

# Install necessary packages
sudo yum update -y || true
sudo yum install -y nginx nodejs git || true

# Start and enable Nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Set up Node.js Payment API
sudo mkdir -p /opt/payment-api
cat <<EOF | sudo tee /opt/payment-api/server.js
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({
    status: 'Payment Processed',
    timestamp: new Date().toISOString()
  }));
});
server.listen(3000);
EOF

# Create systemd service for the API
cat <<EOF | sudo tee /etc/systemd/system/payment-api.service
[Unit]
Description=Payment API Server
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/payment-api/server.js
Restart=always
User=nobody
Group=nobody
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production
WorkingDirectory=/opt/payment-api

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl enable payment-api
sudo systemctl start payment-api

# Configure Nginx to proxy requests from port 80 to 3000
sudo tee /etc/nginx/conf.d/payment-api.conf > /dev/null <<EOF
server {
    listen 80;
    location / {
        proxy_pass http://localhost:3000;
    }
}
EOF

# Restart Nginx
sudo systemctl restart nginx

# Create AMI
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
AMI_ID=$(aws ec2 create-image --instance-id "$INSTANCE_ID" --name "payment-api-ami-$(date +%Y%m%d%H%M%S)" --no-reboot --query 'ImageId' --output text)

# Output AMI ID to file
echo "$AMI_ID" > ami-id.txt

echo "AMI created with ID: $AMI_ID"
