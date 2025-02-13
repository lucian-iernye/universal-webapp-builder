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

# Get PHP port (9000-9100)
while true; do
    read -p "Enter PHP port (9000-9100): " php_port
    if [[ $php_port =~ ^[0-9]+$ ]] && [ $php_port -ge 9000 ] && [ $php_port -le 9100 ]; then
        break
    fi
    echo "Please enter a valid port number between 9000 and 9100"
done

# Get MySQL port (3006-3100)
while true; do
    read -p "Enter MySQL primary database port (3006-3100): " mysql_port
    if [[ $mysql_port =~ ^[0-9]+$ ]] && [ $mysql_port -ge 3006 ] && [ $mysql_port -le 3100 ]; then
        break
    fi
    echo "Please enter a valid port number between 3006 and 3100"
done

# Get MySQL Test port (3006-3100)
while true; do
    read -p "Enter MySQL test database port (3006-3100): " mysql_test_port
    if [[ $mysql_test_port =~ ^[0-9]+$ ]] && 
       [ $mysql_test_port -ge 3006 ] && 
       [ $mysql_test_port -le 3100 ] && 
       [ $mysql_test_port -ne $mysql_port ]; then
        break
    fi
    if [ $mysql_test_port -eq $mysql_port ]; then
        echo "Test database port must be different from primary database port"
    else
        echo "Please enter a valid port number between 3006 and 3100"
    fi
done

# Get Nginx port (8080-8100)
while true; do
    read -p "Enter Nginx port (8080-8100): " nginx_port
    if [[ $nginx_port =~ ^[0-9]+$ ]] && [ $nginx_port -ge 8080 ] && [ $nginx_port -le 8100 ]; then
        break
    fi
    echo "Please enter a valid port number between 8080 and 8100"
done

# Get Redis port (6370-6400)
while true; do
    read -p "Enter Redis port (6370-6400): " redis_port
    if [[ $redis_port =~ ^[0-9]+$ ]] && [ $redis_port -ge 6370 ] && [ $redis_port -le 6400 ]; then
        break
    fi
    echo "Please enter a valid port number between 6370 and 6400"
done

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
RUN composer global require laravel/installer

# Install Node.js LTS
RUN curl -sL https://deb.nodesource.com/setup_lts.x | bash -
RUN apt-get install -y nodejs

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
        fastcgi_pass app:9000;
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
DB_PORT=$mysql_port
DB_DATABASE=${project_name}_db
DB_USERNAME=${project_name}_user
DB_PASSWORD=secret
DB_ROOT_PASSWORD=secret

# Test Database
DB_TEST_HOST=mysql-test
DB_TEST_PORT=$mysql_test_port
DB_TEST_DATABASE=${project_name}_test_db
DB_TEST_USERNAME=${project_name}_test_user
DB_TEST_PASSWORD=secret
DB_TEST_ROOT_PASSWORD=secret

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=$redis_port

# Ports
NGINX_PORT=$nginx_port
PHP_PORT=$php_port
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

# Wait for containers to be healthy
echo "Waiting for containers to be ready..."

# Function to check if container is ready
check_container() {
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        container_status=$(docker compose ps --format json app | grep '"State":"running"' || true)
        if [ ! -z "$container_status" ]; then
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: Container not ready yet..."
        sleep 2
        attempt=$((attempt + 1))
    done
    return 1
}

Select project type
echo -e "\nSelect project type:"
echo "1. Laravel"
echo "2. Nuxt"
echo "3. Vue"

while true; do
    read -p "Select project type (1-3): " project_type
    if [[ $project_type =~ ^[1-3]$ ]]; then
        break
    fi
    echo "Please enter a number between 1 and 3"
done

Create the selected project type
case $project_type in
    1)
        echo "Creating new Laravel project..."
        if ! check_container; then
            echo "Error: Container ${project_name}-app is not ready after waiting. Please check docker logs for issues."
            exit 1
        fi

        # Try to create Laravel project in a temp directory and move it up
        if docker compose exec app bash -c "composer create-project laravel/laravel temp && mv temp/* . && mv temp/.* . 2>/dev/null || true && rm -rf temp"; then
            # Update Laravel .env with values from .env.setup
            sed -i '' "s#APP_NAME=.*#APP_NAME=${project_name}#" .env
            sed -i '' "s#APP_URL=.*#APP_URL=http://localhost:${nginx_port}#" .env
            sed -i '' "s#DB_HOST=.*#DB_HOST=mysql#" .env
            sed -i '' "s#DB_PORT=.*#DB_PORT=3306#" .env
            sed -i '' "s#DB_DATABASE=.*#DB_DATABASE=${project_name}_db#" .env
            sed -i '' "s#DB_USERNAME=.*#DB_USERNAME=${project_name}_user#" .env
            sed -i '' "s#DB_PASSWORD=.*#DB_PASSWORD=secret#" .env
            sed -i '' "s#REDIS_HOST=.*#REDIS_HOST=redis#" .env
            sed -i '' "s#REDIS_PASSWORD=.*#REDIS_PASSWORD=null#" .env
            sed -i '' "s#REDIS_PORT=.*#REDIS_PORT=${redis_port}#" .env

            echo "\nLaravel project created successfully!"
            echo "Environment configured with:"
            echo "- App URL: http://localhost:${nginx_port}"
            echo "- Database: ${project_name}_db"
            echo "- DB User: ${project_name}_user"
            echo "- Redis Port: ${redis_port}"
        else
            echo "\nError: Failed to create Laravel project. Please check the following:"
            echo "1. Container logs: docker compose logs app"
            echo "2. Container status: docker compose ps"
            echo "3. Try running the command manually: docker compose exec app bash -c 'composer create-project laravel/laravel temp && mv temp/* . && mv temp/.* . && rm -rf temp'"
            exit 1
        fi
        ;;
    2)
        echo "Creating new Nuxt project..."
        docker compose exec app bash -c "npm create nuxt@latest . << EOF
\n
\n
\n
\n
\n
EOF"
        echo "\nNuxt project created successfully!"
        echo "Next steps:"
        echo "1. Install dependencies: docker compose exec app npm install"
        echo "2. Start development server: docker compose exec app npm run dev"
        ;;
    3)
        echo "Creating new Vue project..."
        docker compose exec app bash -c "npm create vue@latest . << EOF
\n
\n
\n
\n
\n
\n
EOF"
        echo "\nVue project created successfully!"
        echo "Next steps:"
        echo "1. Install dependencies: docker compose exec app npm install"
        echo "2. Start development server: docker compose exec app npm run dev"
        ;;
esac

echo "\nNote: The .env.setup file contains your Docker configuration"
