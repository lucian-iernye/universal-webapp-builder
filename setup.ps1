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

# Get PHP port (9000-9100)
do {
    $phpPort = Read-Host "Enter PHP port (9000-9100)"
    $phpPort = $phpPort -as [int]
} while (-not $phpPort -or $phpPort -lt 9000 -or $phpPort -gt 9100)

# Get MySQL port (3006-3100)
do {
    $mysqlPort = Read-Host "Enter MySQL primary database port (3006-3100)"
    $mysqlPort = $mysqlPort -as [int]
} while (-not $mysqlPort -or $mysqlPort -lt 3006 -or $mysqlPort -gt 3100)

# Get MySQL Test port (3006-3100)
do {
    $mysqlTestPort = Read-Host "Enter MySQL test database port (3006-3100)"
    $mysqlTestPort = $mysqlTestPort -as [int]
    if ($mysqlTestPort -eq $mysqlPort) {
        Write-Host "Test database port must be different from primary database port"
        $mysqlTestPort = $null
    }
} while (-not $mysqlTestPort -or $mysqlTestPort -lt 3006 -or $mysqlTestPort -gt 3100 -or $mysqlTestPort -eq $mysqlPort)

# Get Nginx port (8080-8100)
do {
    $nginxPort = Read-Host "Enter Nginx port (8080-8100)"
    $nginxPort = $nginxPort -as [int]
} while (-not $nginxPort -or $nginxPort -lt 8080 -or $nginxPort -gt 8100)

# Get Redis port (6370-6400)
do {
    $redisPort = Read-Host "Enter Redis port (6370-6400)"
    $redisPort = $redisPort -as [int]
} while (-not $redisPort -or $redisPort -lt 6370 -or $redisPort -gt 6400)

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
    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
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
DB_PORT=$mysqlPort
DB_DATABASE=${projectName}_db
DB_USERNAME=${projectName}_user
DB_PASSWORD=secret
DB_ROOT_PASSWORD=secret

# Test Database
DB_TEST_HOST=mysql-test
DB_TEST_PORT=$mysqlTestPort
DB_TEST_DATABASE=${projectName}_test_db
DB_TEST_USERNAME=${projectName}_test_user
DB_TEST_PASSWORD=secret
DB_TEST_ROOT_PASSWORD=secret

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=$redisPort

# Ports
NGINX_PORT=$nginxPort
PHP_PORT=$phpPort
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

# Function to check if container is ready
function Check-Container {
    $maxAttempts = 30
    $attempt = 1
    while ($attempt -le $maxAttempts) {
        $containerStatus = docker compose ps --format json app | Select-String '"State":"running"'
        if ($containerStatus) {
            return $true
        }
        Write-Host "Attempt $attempt/$maxAttempts: Container not ready yet..."
        Start-Sleep -Seconds 2
        $attempt++
    }
    return $false
}

# Wait for containers to be healthy
Write-Host "Waiting for containers to be ready..."

# Select project type
Write-Host "`nSelect project type:"
Write-Host "1. Laravel"
Write-Host "2. Nuxt"
Write-Host "3. Vue"

do {
    $projectType = Read-Host "Select project type (1-3)"
    $projectType = $projectType -as [int]
} while (-not $projectType -or $projectType -lt 1 -or $projectType -gt 3)

# Create the selected project type
switch ($projectType) {
    1 {
        Write-Host "Creating new Laravel project..."
        if (-not (Check-Container)) {
            Write-Host "Error: Container app is not ready after waiting. Please check docker logs for issues."
            exit 1
        }
        docker compose exec app bash -c "composer create-project laravel/laravel temp && mv temp/* . && mv temp/.* . 2>/dev/null || true && rm -rf temp"
        
        # Update Laravel .env with values from .env.setup
        ((Get-Content -Path .env) -replace 'APP_NAME=.*', "APP_NAME=$projectName") | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'APP_URL=.*', "APP_URL=http://localhost:$nginxPort") | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'DB_HOST=.*', 'DB_HOST=mysql') | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'DB_PORT=.*', 'DB_PORT=3306') | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'DB_DATABASE=.*', "DB_DATABASE=${projectName}_db") | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'DB_USERNAME=.*', "DB_USERNAME=${projectName}_user") | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'DB_PASSWORD=.*', 'DB_PASSWORD=secret') | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'REDIS_HOST=.*', 'REDIS_HOST=redis') | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'REDIS_PASSWORD=.*', 'REDIS_PASSWORD=null') | Set-Content -Path .env
        ((Get-Content -Path .env) -replace 'REDIS_PORT=.*', "REDIS_PORT=$redisPort") | Set-Content -Path .env

        Write-Host "`nLaravel project created successfully!"
        Write-Host "Environment configured with:"
        Write-Host "- App URL: http://localhost:$nginxPort"
        Write-Host "- Database: ${projectName}_db"
        Write-Host "- DB User: ${projectName}_user"
        Write-Host "- Redis Port: $redisPort"
    }
    2 {
        Write-Host "Creating new Nuxt project..."
        docker compose exec app bash -c "npm create nuxt@latest . << EOF`n`n`n`n`n`nEOF"
        Write-Host "`nNuxt project created successfully!"
        Write-Host "Next steps:"
        Write-Host "1. Install dependencies: docker compose exec app npm install"
        Write-Host "2. Start development server: docker compose exec app npm run dev"
    }
    3 {
        Write-Host "Creating new Vue project..."
        docker compose exec app bash -c "npm create vue@latest . << EOF`n`n`n`n`n`n`nEOF"
        Write-Host "`nVue project created successfully!"
        Write-Host "Next steps:"
        Write-Host "1. Install dependencies: docker compose exec app npm install"
        Write-Host "2. Start development server: docker compose exec app npm run dev"
    }
}

Write-Host "`nNote: The .env.setup file contains your Docker configuration"
