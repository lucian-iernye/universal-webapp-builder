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
        Write-Host ("PHP {0}: Compatible with all Laravel versions" -f $selectedVersion) -ForegroundColor Green
    }
    "8.1" {
        Write-Host "Warning: PHP 8.1" -ForegroundColor Yellow
        Write-Host "   - Laravel 11+ requires PHP 8.2 or higher"
        Write-Host "   - Laravel Breeze 2+ requires PHP 8.2 or higher"
        Write-Host "   - Some packages may require PHP 8.2"
    }
    "7.4" {
        Write-Host "Warning: PHP 7.4" -ForegroundColor Yellow
        Write-Host "   - Laravel 9+ requires PHP 8.0 or higher"
        Write-Host "   - Laravel 8.x will be used"
        Write-Host "   - Many packages may have compatibility issues"
    }
    "7.3" {
        Write-Host "Warning: PHP 7.3" -ForegroundColor Yellow
        Write-Host "   - Laravel 8+ requires PHP 7.4 or higher"
        Write-Host "   - Laravel 7.x will be used"
        Write-Host "   - Many packages may have compatibility issues"
    }
    default {
        Write-Host ("Warning: PHP version {0} might have compatibility issues with Laravel" -f $selectedVersion) -ForegroundColor Yellow
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
            Write-Host ("Error: No available ports found in range {0}-{1} for {2}" -f $minPort,$maxPort,$portName) -ForegroundColor Red
            exit 1
        }
        Write-Host ("Warning: Default port {0} for {1} is in use." -f $defaultPort,$portName) -ForegroundColor Yellow
        Write-Host ("Next available port is: {0}" -f $nextPort) -ForegroundColor Yellow
        $defaultPort = $nextPort
    }

    do {
        $useDefault = Read-Host ("Use default {0} port ({1})? [Y/n]" -f $portName,$defaultPort)
        if ([string]::IsNullOrWhiteSpace($useDefault)) { $useDefault = 'Y' }

        if ($useDefault.ToUpper() -eq 'Y') {
            return $defaultPort
        }
        elseif ($useDefault.ToUpper() -eq 'N') {
            do {
                $port = Read-Host ("Enter {0} port ({1}-{2})" -f $portName,$minPort,$maxPort)
                $port = $port -as [int]
                if ($port -and $port -ge $minPort -and $port -le $maxPort) {
                    return $port
                }
                Write-Host ("Please enter a valid port number between {0} and {1}" -f $minPort,$maxPort)
            } while ($true)
        }
        Write-Host "Please enter Y or n"
    } while ($true)
}

# Get ports with defaults
$phpPort = Get-Port -portName "PHP" -defaultPort 9000 -minPort 9000 -maxPort 9100
Write-Host ("Selected PHP port: {0}" -f $phpPort)

$mysqlPort = Get-Port -portName "MySQL" -defaultPort 3306 -minPort 3306 -maxPort 3399
Write-Host ("Selected MySQL port: {0}" -f $mysqlPort)

# Get MySQL Test port with dynamic default and range
$testDefault = $mysqlPort + 1
do {
    $mysqlTestPort = Get-Port -portName "MySQL Test" -defaultPort $testDefault -minPort ($mysqlPort + 1) -maxPort 3399
    if ($mysqlTestPort -ne $mysqlPort) {
        break
    }
    Write-Host "Test database port must be different from primary database port"
} while ($true)
Write-Host ("Selected MySQL Test port: {0}" -f $mysqlTestPort)

$redisPort = Get-Port -portName "Redis" -defaultPort 6379 -minPort 6379 -maxPort 6400
Write-Host ("Selected Redis port: {0}" -f $redisPort)

$nginxPort = Get-Port -portName "Nginx" -defaultPort 8080 -minPort 8080 -maxPort 8100
Write-Host ("Selected Nginx port: {0}" -f $nginxPort)

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

# Set working directory and fix permissions
WORKDIR /var/www
RUN chown -R dev:dev /var/www && \
    chmod -R 755 /var/www && \
    git config --system --add safe.directory /var/www

USER dev
"@

$dockerfileContent | Out-File -FilePath "docker/php/Dockerfile" -Encoding UTF8 -Force

Write-Host ("`nDockerfile has been created with PHP {0}" -f $selectedVersion)

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

# Ensure directory exists
New-Item -ItemType Directory -Force -Path "docker/nginx" | Out-Null

# Convert to Unix line endings and UTF-8 without BOM
$defaultConfig = $defaultConfig -replace "`r`n", "`n"
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) "docker/nginx/default.conf"),
    $defaultConfig,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Created Nginx configuration with Unix line endings"

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

Write-Host (".env.setup file has been created with project name {0} and PHP version {1}" -f $projectName,$selectedVersion)

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

Write-Host ("`nDocker containers are starting up with PHP {0}" -f $selectedVersion)
Write-Host ("Project name: {0}" -f $projectName)

# Function to check if container is ready
function Check-Container {
    $maxAttempts = 30
    $attempt = 1
    while ($attempt -le $maxAttempts) {
        $containerStatus = docker compose ps --format json app | Select-String '"State":"running"'
        if ($containerStatus) {
            return $true
        }
        Write-Host ("Attempt {0}/{1}: Container not ready yet..." -f $attempt,$maxAttempts)
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

        # Add cleanup and file movement as separate steps
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
                    $laravelCmd += " && npm install"
                }
            }
            3 {  # Jetstream
                $laravelCmd += " && cd temp && composer require laravel/jetstream"
                
                if ($jetstreamStackChoice -eq 1) {
                    $laravelCmd += " && php artisan jetstream:install livewire --teams"
                } else {
                    $laravelCmd += " && php artisan jetstream:install inertia --teams"
                }

                $laravelCmd += " && npm install"
            }
        }

        # Add Pest if selected
        if ($testChoice -eq 2) {
            $laravelCmd += " && cd temp && composer require pestphp/pest --dev --with-all-dependencies && php artisan pest:install"
        }

        # Create Laravel project with all selected options
        Write-Host "Creating new Laravel project..." -ForegroundColor Cyan
        docker compose exec app bash -c $laravelCmd
        
        # Move files from temp directory to root
        Write-Host "Moving Laravel files from temp directory to root..." -ForegroundColor Cyan
        $moveCmd = @"
cd /var/www/html && 
echo 'Moving Laravel files to project root...' &&
find temp -mindepth 1 -maxdepth 1 -not -path '*/\.*' -exec mv -f {} . \; &&
find temp -mindepth 1 -maxdepth 1 -path '*/\.*' -exec mv -f {} . \; &&
rm -rf temp &&
echo 'Files moved successfully!'
"@
        docker compose exec app bash -c $moveCmd
        
        # Add custom entries to .gitignore
        "`n# Custom entries`ndocker/`n.env.setup" | Add-Content -Path .gitignore
        Write-Host "Added custom entries to .gitignore" -ForegroundColor Green
        
        # Update .env file from the container
        Write-Host "Updating environment configuration..." -ForegroundColor Cyan
        
        # Create .env file backup if it exists
        if (Test-Path -Path .env) {
            Copy-Item -Path .env -Destination .env.backup -Force
        }
        
        # Run .env update command
        $envUpdateCmd = @"
cd /var/www/html &&
sed -i 's/APP_NAME=.*/APP_NAME=$projectName/g' .env &&
sed -i 's#APP_URL=.*#APP_URL=http://localhost:$nginxPort#g' .env &&
sed -i 's/DB_HOST=.*/DB_HOST=mysql/g' .env &&
sed -i 's/DB_PORT=.*/DB_PORT=3306/g' .env &&
sed -i 's/DB_DATABASE=.*/DB_DATABASE=${projectName}_db/g' .env &&
sed -i 's/DB_USERNAME=.*/DB_USERNAME=${projectName}_user/g' .env &&
sed -i 's/DB_PASSWORD=.*/DB_PASSWORD=secret/g' .env &&
sed -i 's/REDIS_HOST=.*/REDIS_HOST=redis/g' .env &&
sed -i 's/REDIS_PASSWORD=.*/REDIS_PASSWORD=null/g' .env &&
sed -i 's/REDIS_PORT=.*/REDIS_PORT=$redisPort/g' .env &&
cat .env > .env.example
"@
        docker compose exec app bash -c $envUpdateCmd
        
        # Copy the updated .env from the container to the host
        docker compose exec app cat /var/www/html/.env | Out-File -FilePath .env -Encoding utf8
        
        # Install Pest if selected and wasn't done in Laravel setup
        if ($testChoice -eq 2 -and -not (Test-Path -Path "vendor/pestphp")) {
            Write-Host "Installing Pest testing framework..." -ForegroundColor Cyan
            docker compose exec app composer require pestphp/pest --dev --with-all-dependencies
            docker compose exec app php artisan pest:install
        }

        Write-Host "`nLaravel project created successfully!"
        Write-Host "Environment configured with:"
        Write-Host ("- App URL: http://localhost:{0}" -f $nginxPort)
        Write-Host ("- Database: {0}_db" -f $projectName)
        Write-Host ("- DB User: {0}_user" -f $projectName)
        Write-Host ("- Redis Port: {0}" -f $redisPort)
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
