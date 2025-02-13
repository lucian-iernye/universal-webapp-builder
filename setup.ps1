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

# Check PHP version compatibility
Write-Host "`nChecking PHP version compatibility..." -ForegroundColor Cyan
switch ($selectedVersion) {
    { $_ -in @("8.2", "8.3") } {
        Write-Host "PHP $selectedVersion: Compatible with all Laravel versions" -ForegroundColor Green
    }
    "8.1" {
        Write-Host "⚠️  Warning: PHP 8.1" -ForegroundColor Yellow
        Write-Host "   - Laravel 11+ requires PHP 8.2 or higher"
        Write-Host "   - Laravel Breeze 2+ requires PHP 8.2 or higher"
        Write-Host "   - Some packages may require PHP 8.2"
    }
    "7.4" {
        Write-Host "⚠️  Warning: PHP 7.4" -ForegroundColor Yellow
        Write-Host "   - Laravel 9+ requires PHP 8.0 or higher"
        Write-Host "   - Laravel 8.x will be used"
        Write-Host "   - Many packages may have compatibility issues"
    }
    "7.3" {
        Write-Host "⚠️  Warning: PHP 7.3" -ForegroundColor Yellow
        Write-Host "   - Laravel 8+ requires PHP 7.4 or higher"
        Write-Host "   - Laravel 7.x will be used"
        Write-Host "   - Many packages may have compatibility issues"
    }
    default {
        Write-Host "⚠️  Warning: PHP version $selectedVersion might have compatibility issues with Laravel" -ForegroundColor Yellow
    }
}

Write-Host "`nPress Enter to continue or Ctrl+C to abort" -ForegroundColor Cyan
Read-Host

# Function to check if a port is available
function Test-PortAvailable {
    param(
        [int]$port
    )
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        $listener.Stop()
        return $true
    } catch {
        return $false
    }
}

# Function to find next available port
function Find-NextPort {
    param(
        [int]$startPort,
        [int]$maxPort
    )
    
    $currentPort = $startPort
    while ($currentPort -le $maxPort) {
        if (Test-PortAvailable -port $currentPort) {
            return $currentPort
        }
        $currentPort++
    }
    return 0  # No available ports found
}

# Function to get port with default option
function Get-Port {
    param(
        [string]$portName,
        [int]$defaultPort,
        [int]$minPort,
        [int]$maxPort
    )

    # Check if default port is available
    if (-not (Test-PortAvailable -port $defaultPort)) {
        $nextPort = Find-NextPort -startPort $minPort -maxPort $maxPort
        if ($nextPort -eq 0) {
            Write-Host "Error: No available ports found in range $minPort-$maxPort for $portName" -ForegroundColor Red
            exit 1
        }
        Write-Host "Warning: Default port $defaultPort for $portName is in use." -ForegroundColor Yellow
        Write-Host "Next available port is: $nextPort" -ForegroundColor Yellow
        $defaultPort = $nextPort
    }

    do {
        $useDefault = Read-Host "Use default $portName port ($defaultPort)? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($useDefault)) { $useDefault = 'Y' }

        if ($useDefault.ToUpper() -eq 'Y') {
            return $defaultPort
        }
        elseif ($useDefault.ToUpper() -eq 'N') {
            do {
                $port = Read-Host "Enter $portName port ($minPort-$maxPort)"
                $port = $port -as [int]
                if ($port -and $port -ge $minPort -and $port -le $maxPort) {
                    return $port
                }
                Write-Host "Please enter a valid port number between $minPort and $maxPort"
            } while ($true)
        }
        Write-Host "Please enter Y or n"
    } while ($true)
}

# Get ports with defaults
$phpPort = Get-Port -portName "PHP" -defaultPort 9000 -minPort 9000 -maxPort 9100
Write-Host "Selected PHP port: $phpPort"

$mysqlPort = Get-Port -portName "MySQL" -defaultPort 3306 -minPort 3306 -maxPort 3399
Write-Host "Selected MySQL port: $mysqlPort"

# Get MySQL Test port with dynamic default and range
$testDefault = $mysqlPort + 1
do {
    $mysqlTestPort = Get-Port -portName "MySQL Test" -defaultPort $testDefault -minPort ($mysqlPort + 1) -maxPort 3399
    if ($mysqlTestPort -ne $mysqlPort) {
        break
    }
    Write-Host "Test database port must be different from primary database port"
} while ($true)
Write-Host "Selected MySQL Test port: $mysqlTestPort"

$redisPort = Get-Port -portName "Redis" -defaultPort 6379 -minPort 6379 -maxPort 6400
Write-Host "Selected Redis port: $redisPort"

$nginxPort = Get-Port -portName "Nginx" -defaultPort 8080 -minPort 8080 -maxPort 8100
Write-Host "Selected Nginx port: $nginxPort"

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
            Write-Host "Error: Container app is not ready after waiting. Please check docker logs for issues." -ForegroundColor Red
            exit 1
        }

        # Get Laravel setup preferences
        Write-Host "`nLaravel Project Setup Options:`n" -ForegroundColor Cyan

        # Authentication
        Write-Host "Select authentication setup:" -ForegroundColor Yellow
        Write-Host "1. No authentication (skip)"
        Write-Host "2. Laravel Breeze (minimal)"
        Write-Host "3. Laravel Jetstream"
        do {
            $authChoice = Read-Host "Choose authentication (1-3)"
            $authChoice = $authChoice -as [int]
        } while (-not $authChoice -or $authChoice -lt 1 -or $authChoice -gt 3)

        # If Breeze selected, get stack preference
        if ($authChoice -eq 2) {
            Write-Host "`nSelect Breeze stack:" -ForegroundColor Yellow
            Write-Host "1. Blade with Alpine.js"
            Write-Host "2. Livewire (Blade + Alpine.js + Livewire)"
            Write-Host "3. React with Inertia"
            Write-Host "4. Vue with Inertia"
            Write-Host "5. API only"
            do {
                $breezeStackChoice = Read-Host "Choose stack (1-5)"
                $breezeStackChoice = $breezeStackChoice -as [int]
            } while (-not $breezeStackChoice -or $breezeStackChoice -lt 1 -or $breezeStackChoice -gt 5)

            # Dark mode option for Breeze
            $darkModeChoice = Read-Host "Would you like to include dark mode support? [y/N]"
            if ([string]::IsNullOrWhiteSpace($darkModeChoice)) { $darkModeChoice = 'N' }
        }

        # If Jetstream selected, get stack preference
        if ($authChoice -eq 3) {
            Write-Host "`nSelect Jetstream stack:" -ForegroundColor Yellow
            Write-Host "1. Livewire + Blade"
            Write-Host "2. Inertia + Vue.js"
            do {
                $jetstreamStackChoice = Read-Host "Choose stack (1-2)"
                $jetstreamStackChoice = $jetstreamStackChoice -as [int]
            } while (-not $jetstreamStackChoice -or $jetstreamStackChoice -lt 1 -or $jetstreamStackChoice -gt 2)

            # Teams feature
            $teamsChoice = Read-Host "Would you like to include team support? [y/N]"
            if ([string]::IsNullOrWhiteSpace($teamsChoice)) { $teamsChoice = 'N' }
        }

        # Testing preference
        Write-Host "`nSelect testing framework:" -ForegroundColor Yellow
        Write-Host "1. PHPUnit (default)"
        Write-Host "2. Pest (recommended)"
        do {
            $testChoice = Read-Host "Choose testing framework (1-2)"
            $testChoice = $testChoice -as [int]
        } while (-not $testChoice -or $testChoice -lt 1 -or $testChoice -gt 2)

        # Build Laravel installation command
        $laravelCmd = "composer create-project laravel/laravel temp"

        # Add authentication options
        switch ($authChoice) {
            2 {  # Breeze
                $laravelCmd += " && cd temp && composer require laravel/breeze --dev"
                
                # Determine Breeze stack argument
                $stackArg = switch ($breezeStackChoice) {
                    1 { "blade" }
                    2 { "livewire" }
                    3 { "react" }
                    4 { "vue" }
                    5 { "api" }
                }

                # Add Breeze installation command
                if ($darkModeChoice.ToUpper() -eq 'Y') {
                    $laravelCmd += " && php artisan breeze:install $stackArg --dark"
                } else {
                    $laravelCmd += " && php artisan breeze:install $stackArg"
                }

                # Add npm commands if not API stack
                if ($breezeStackChoice -ne 5) {
                    $laravelCmd += " && npm install && npm run build"
                }
            }
            3 {  # Jetstream
                $laravelCmd += " && cd temp && composer require laravel/jetstream"
                
                # Install Jetstream with selected stack
                if ($jetstreamStackChoice -eq 1) {
                    if ($teamsChoice.ToUpper() -eq 'Y') {
                        $laravelCmd += " && php artisan jetstream:install livewire --teams"
                    } else {
                        $laravelCmd += " && php artisan jetstream:install livewire"
                    }
                } else {
                    if ($teamsChoice.ToUpper() -eq 'Y') {
                        $laravelCmd += " && php artisan jetstream:install inertia --teams"
                    } else {
                        $laravelCmd += " && php artisan jetstream:install inertia"
                    }
                }

                $laravelCmd += " && npm install && npm run build"
            }
        }

        # Add Pest if selected
        if ($testChoice -eq 2) {
            $laravelCmd += " && composer require pestphp/pest --dev --with-all-dependencies && php artisan pest:install"
        }

        # Add final move commands
        $laravelCmd += " && mv * .. && mv .* .. 2>/dev/null || true && cd .. && rm -rf temp"

        # Create Laravel project with all selected options
        Write-Host "Creating new Laravel project..." -ForegroundColor Cyan
        docker compose exec app bash -c $laravelCmd

        # Add custom entries to .gitignore
        "`n# Custom entries`ndocker/`n.env.setup" | Add-Content -Path .gitignore
        Write-Host "Added custom entries to .gitignore" -ForegroundColor Green


        # Install Pest if selected
        if ($testChoice -eq 2) {
            Write-Host "Installing Pest testing framework..." -ForegroundColor Cyan
            docker compose exec app composer require pestphp/pest --dev --with-all-dependencies
            docker compose exec app php artisan pest:install
        }
        
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
