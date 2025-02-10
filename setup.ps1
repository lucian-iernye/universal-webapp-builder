$phpVersions = @(
    "7.3",
    "7.4",
    "8.1",
    "8.2",
    "8.3"
)

# Get project name
Write-Host "`nEnter your project name (lowercase, no spaces):"
do {
    $projectName = Read-Host
    if ($projectName -match '^[a-z0-9-]+$') {
        break
    }
    Write-Host "Project name must be lowercase, and can only contain letters, numbers, and hyphens"
} while ($true)

# Get PHP version
Write-Host "`nAvailable PHP versions:"
for ($i = 0; $i -lt $phpVersions.Count; $i++) {
    Write-Host "$($i + 1). PHP $($phpVersions[$i])"
}

do {
    $selection = Read-Host "`nSelect PHP version (1-$($phpVersions.Count))"
    $selection = $selection -as [int]
} while ($selection -lt 1 -or $selection -gt $phpVersions.Count)

$selectedVersion = $phpVersions[$selection - 1]

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "docker/php" | Out-Null
New-Item -ItemType Directory -Force -Path "docker/nginx" | Out-Null

# Create Dockerfile
$dockerfileContent = @"
FROM php:$selectedVersion-fpm

ARG PROJECT_NAME
ENV PROJECT_NAME=`${PROJECT_NAME}

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
"@

$dockerfileContent | Out-File -FilePath "docker/php/Dockerfile" -Encoding UTF8 -Force

Write-Host "`nDockerfile has been created with PHP $selectedVersion"

# Create nginx configuration
$defaultConfig = @"
server {
    listen 80;
    index index.php index.html;
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;
    root /var/www/public;

    location ~ \.php$ {
        try_files `$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME `$document_root`$fastcgi_script_name;
        fastcgi_param PATH_INFO `$fastcgi_path_info;
    }

    location / {
        try_files `$uri `$uri/ /index.php?`$query_string;
        gzip_static on;
    }

    # Add cache headers for static assets
    location / {
        try_files `$uri `$uri/ /index.php?`$query_string;
        gzip_static on;
    }
}
"@

$defaultConfig | Out-File -FilePath "docker/nginx/default.conf" -Encoding UTF8 -Force

# Create .env.setup file
$envContent = @"
# Docker Settings
COMPOSE_PROJECT_NAME=$projectName
PHP_VERSION=$selectedVersion

# Main Database
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3308
DB_DATABASE=${projectName}_db
DB_USERNAME=${projectName}_user
DB_PASSWORD=secret
DB_ROOT_PASSWORD=secret

# Test Database
DB_TEST_HOST=mysql-test
DB_TEST_PORT=3307
DB_TEST_DATABASE=${projectName}_test_db
DB_TEST_USERNAME=${projectName}_test_user
DB_TEST_PASSWORD=secret
DB_TEST_ROOT_PASSWORD=secret

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Ports
NGINX_PORT=8080
PHP_PORT=9000
"@

$envContent | Out-File -FilePath ".env.setup" -Encoding UTF8 -Force

Write-Host ".env.setup file has been created with project name $projectName and PHP version $selectedVersion"

# Create temporary .env for Docker Compose
Copy-Item .env.setup .env

Write-Host "`nStarting Docker containers..."
# Check if any containers exist for this project
$projectContainers = docker ps -a --filter "name=$projectName" --format "{{.Names}}"
if ($projectContainers) {
    Write-Host "Stopping existing containers..."
    docker compose down
}

docker compose up -d --build

Write-Host "`nDocker containers are starting up with PHP $selectedVersion"
Write-Host "Project name: $projectName"
Write-Host "`nNext steps:"
Write-Host "1. Create a new Laravel project:"
Write-Host "   docker compose exec app composer create-project laravel/laravel ."
Write-Host "2. Update the Laravel .env file with values from .env.setup"
Write-Host "3. Remove the temporary .env file"
Write-Host "   Note: The .env.setup file contains your Docker configuration"
