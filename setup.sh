#!/bin/bash

# Get project name
while true; do
    echo -e "\nEnter your project name (lowercase, no spaces):"
    read project_name
    if [[ $project_name =~ ^[a-z0-9-]+$ ]]; then
        break
    fi
    echo "Project name must be lowercase, and can only contain letters, numbers, and hyphens"
done

# Get PHP version
echo -e "\nAvailable PHP versions:"
echo "1. PHP 7.3"
echo "2. PHP 7.4"
echo "3. PHP 8.1"
echo "4. PHP 8.2"
echo "5. PHP 8.3"

while true; do
    read -p "Select PHP version (1-5): " selection
    if [[ $selection =~ ^[1-5]$ ]]; then
        break
    fi
    echo "Please enter a number between 1 and 5"
done

case $selection in
    1) version="7.3" ;;
    2) version="7.4" ;;
    3) version="8.1" ;;
    4) version="8.2" ;;
    5) version="8.3" ;;
esac

# Create docker/php directory if it doesn't exist
mkdir -p docker/php docker/nginx

# Create Dockerfile
cat > docker/php/Dockerfile << EOF
FROM php:${version}-fpm

ARG PROJECT_NAME
ENV PROJECT_NAME=\${PROJECT_NAME}

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip

# Clear cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create system user to run Composer and Artisan Commands
RUN useradd -G www-data,root -u 1000 -d /home/dev dev
RUN mkdir -p /home/dev/.composer && \
    chown -R dev:dev /home/dev

# Set working directory
WORKDIR /var/www

USER dev
EOF

echo "Dockerfile has been created with PHP $version"

# Create nginx configuration
cat > docker/nginx/default.conf << EOF
server {
    listen 80;
    index index.php index.html;
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;
    root /var/www/public;

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass \${COMPOSE_PROJECT_NAME}:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
        gzip_static on;
    }

    # Add cache headers for static assets
    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
EOF

# Create .env.setup file
cat > .env.setup << EOF
# Docker Settings
COMPOSE_PROJECT_NAME=$project_name
PHP_VERSION=$version

# Main Database
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3308
DB_DATABASE=${project_name}_db
DB_USERNAME=${project_name}_user
DB_PASSWORD=secret
DB_ROOT_PASSWORD=secret

# Test Database
DB_TEST_HOST=mysql-test
DB_TEST_PORT=3307
DB_TEST_DATABASE=${project_name}_test_db
DB_TEST_USERNAME=${project_name}_test_user
DB_TEST_PASSWORD=secret
DB_TEST_ROOT_PASSWORD=secret

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Ports
NGINX_PORT=8080
PHP_PORT=9000
EOF

echo ".env.setup file has been created with project name $project_name and PHP version $version"

# Create temporary .env for Docker Compose
cp .env.setup .env

echo -e "\nStarting Docker containers..."
# Check if any containers exist for this project
if [ "$(docker ps -a --filter "name=$project_name" --format '{{.Names}}')" ]; then
    echo "Stopping existing containers..."
    docker compose down
fi

docker compose up -d --build

echo -e "\nDocker containers are starting up with PHP $version"
echo "Project name: $project_name"
echo -e "\nNext steps:"
echo "1. Create a new Laravel project:"
echo "   docker compose exec app composer create-project laravel/laravel ."
echo "2. Update the Laravel .env file with values from .env.setup"
echo "3. Remove the temporary .env file"
echo "   Note: The .env.setup file contains your Docker configuration"
