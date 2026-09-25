#!/bin/bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y nginx
echo "Hello World from $(hostname -f)" > /var/www/html/index.html