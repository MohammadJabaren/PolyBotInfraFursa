#!/bin/bash
set -e

REPO_DIR=$1
NGINX_CONF_SRC="$REPO_DIR/nginx-config/default.conf"
NGINX_CONF_DST="/etc/nginx/conf.d"

# Install the prerequisites:
#sudo apt update
#sudo apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring -y
#curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
 #| sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
# Set up the apt repository for stable nginx packages
#echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
#http://nginx.org/packages/ubuntu `lsb_release -cs` nginx" \
#    | sudo tee /etc/apt/sources.list.d/nginx.list

# Set up repository pinning to prefer our packages over distribution-provided ones:
#echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
#    | sudo tee /etc/apt/preferences.d/99nginx
#sudo apt update
#sudo apt install nginx


echo "🔧 Deploying Nginx configuration from $NGINX_CONF_SRC"

# Copy the config to sites-available
sudo cp "$NGINX_CONF_SRC" "$NGINX_CONF_DST"

# Test Nginx config
echo "✅ Testing Nginx config..."
sudo nginx -t

# Reload Nginx
echo "🔄 Reloading Nginx..."
sudo systemctl reload nginx


# ✅ Check if Nginx is running
echo "🩺 Checking if Nginx is running..."
if systemctl is-active --quiet nginx; then
  echo "✅ Nginx is running."
else
  echo "❌ Nginx is NOT running!" >&2
  exit 1
fi


echo "🚀 Nginx configuration deployed successfully!"
