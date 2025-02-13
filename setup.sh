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

# Check PHP version compatibility
echo -e "\nChecking PHP version compatibility..."
case $version in
    "8.2"|"8.3")
        echo "PHP $version: Compatible with all Laravel versions"
        ;;
    "8.1")
        echo "⚠️  Warning: PHP 8.1"
        echo "   - Laravel 11+ requires PHP 8.2 or higher"
        echo "   - Laravel Breeze 2+ requires PHP 8.2 or higher"
        echo "   - Some packages may require PHP 8.2"
        ;;
    "7.4")
        echo "⚠️  Warning: PHP 7.4"
        echo "   - Laravel 9+ requires PHP 8.0 or higher"
        echo "   - Laravel 8.x will be used"
        echo "   - Many packages may have compatibility issues"
        ;;
    "7.3")
        echo "⚠️  Warning: PHP 7.3"
        echo "   - Laravel 8+ requires PHP 7.4 or higher"
        echo "   - Laravel 7.x will be used"
        echo "   - Many packages may have compatibility issues"
        ;;
    *)
        echo "⚠️  Warning: PHP version $version might have compatibility issues with Laravel"
        ;;
esac

echo -e "\nPress Enter to continue or Ctrl+C to abort"
read

# Function to check if a port is available
check_port() {
    local port=$1
    if command -v nc >/dev/null 2>&1; then
        nc -z localhost $port >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            return 1  # Port is in use
        fi
    else
        # Fallback to using lsof if nc is not available
        if command -v lsof >/dev/null 2>&1; then
            lsof -i :$port >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                return 1  # Port is in use
            fi
        fi
    fi
    return 0  # Port is available
}

# Function to suggest next available port
find_next_port() {
    local start_port=$1
    local max_port=$2
    local current_port=$start_port

    while [ $current_port -le $max_port ]; do
        if check_port $current_port; then
            echo $current_port
            return 0
        fi
        current_port=$((current_port + 1))
    done
    echo 0  # No available ports found
    return 1
}

# Function to get port with default option
get_port() {
    local port_name=$1
    local default_port=$2
    local min_port=$3
    local max_port=$4
    local current_port=""

    # Check if default port is available
    if ! check_port $default_port; then
        local next_port=$(find_next_port $min_port $max_port)
        if [ $next_port -eq 0 ]; then
            echo "Error: No available ports found in range $min_port-$max_port for $port_name" >&2
            exit 1
        fi
        echo "Warning: Default port $default_port for $port_name is in use." >&2
        echo "Next available port is: $next_port" >&2
        default_port=$next_port
    fi

    while true; do
        read -p "Use default ${port_name} port (${default_port})? [Y/n]: " use_default
        use_default=${use_default:-Y}  # Default to Y if user just hits enter
        use_default=$(echo $use_default | tr '[:lower:]' '[:upper:]')
        
        if [[ $use_default == "Y" ]]; then
            current_port=$default_port
            break
        elif [[ $use_default == "N" ]]; then
            while true; do
                read -p "Enter ${port_name} port (${min_port}-${max_port}): " current_port
                if [[ $current_port =~ ^[0-9]+$ ]] && 
                   [ $current_port -ge $min_port ] && 
                   [ $current_port -le $max_port ]; then
                    break
                fi
                echo "Please enter a valid port number between ${min_port} and ${max_port}"
            done
            break
        fi
        echo "Please enter Y or n"
    done
    echo $current_port
}

# Get ports with defaults
php_port=$(get_port "PHP" 9000 9000 9100)
echo "Selected PHP port: ${php_port}"

mysql_port=$(get_port "MySQL" 3306 3306 3399)
echo "Selected MySQL port: ${mysql_port}"

# Get MySQL Test port with dynamic default and range
test_default=$((mysql_port + 1))
mysql_test_port=$(get_port "MySQL Test" $test_default $((mysql_port + 1)) 3399)
# Verify the ports are different
if [ "$mysql_test_port" -eq "$mysql_port" ]; then
    echo "Error: Test database port must be different from primary database port"
    exit 1
fi
echo "Selected MySQL Test port: ${mysql_test_port}"

redis_port=$(get_port "Redis" 6379 6379 6400)
echo "Selected Redis port: ${redis_port}"

nginx_port=$(get_port "Nginx" 8080 8080 8100)
echo "Selected Nginx port: ${nginx_port}"

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

echo "Creating the selected project type"
case $project_type in
    1)
        echo "Creating new Laravel project..."
        if ! check_container; then
            echo "Error: Container ${project_name}-app is not ready after waiting. Please check docker logs for issues."
            exit 1
        fi

        # Get Laravel setup preferences
        echo -e "\nLaravel Project Setup Options:\n"

        # Authentication
        echo "Select authentication setup:"
        echo "1. No authentication (skip)"
        echo "2. Laravel Breeze (minimal)"
        echo "3. Laravel Jetstream"
        while true; do
            read -p "Choose authentication (1-3): " auth_choice
            if [[ $auth_choice =~ ^[1-3]$ ]]; then
                break
            fi
            echo "Please enter a number between 1 and 3"
        done

        # If Breeze selected, get stack preference
        if [ "$auth_choice" = "2" ]; then
            echo -e "\nSelect Breeze stack:"
            echo "1. Blade with Alpine.js"
            echo "2. Livewire (Blade + Alpine.js + Livewire)"
            echo "3. React with Inertia"
            echo "4. Vue with Inertia"
            echo "5. API only"
            while true; do
                read -p "Choose stack (1-5): " breeze_stack_choice
                if [[ $breeze_stack_choice =~ ^[1-5]$ ]]; then
                    break
                fi
                echo "Please enter a number between 1 and 5"
            done

            # Dark mode option for Breeze
            read -p "Would you like to include dark mode support? [y/N]: " dark_mode_choice
            dark_mode_choice=${dark_mode_choice:-N}
        fi

        # If Jetstream selected, get stack preference
        if [ "$auth_choice" = "3" ]; then
            echo -e "\nSelect Jetstream stack:"
            echo "1. Livewire + Blade"
            echo "2. Inertia + Vue.js"
            while true; do
                read -p "Choose stack (1-2): " jetstream_stack_choice
                if [[ $jetstream_stack_choice =~ ^[1-2]$ ]]; then
                    break
                fi
                echo "Please enter 1 or 2"
            done

            # Teams feature
            read -p "Would you like to include team support? [y/N]: " teams_choice
            teams_choice=${teams_choice:-N}
        fi

        # Testing preference
        echo -e "\nSelect testing framework:"
        echo "1. PHPUnit (default)"
        echo "2. Pest (recommended)"
        while true; do
            read -p "Choose testing framework (1-2): " test_choice
            if [[ $test_choice =~ ^[1-2]$ ]]; then
                break
            fi
            echo "Please enter 1 or 2"
        done

        # Build Laravel installation command based on choices
        laravel_cmd="composer create-project laravel/laravel temp"

        # Add authentication options
        case $auth_choice in
            2)  # Breeze
                laravel_cmd="$laravel_cmd && cd temp && composer require laravel/breeze --dev"
                
                # Determine Breeze stack argument
                case $breeze_stack_choice in
                    1) stack="blade" ;;
                    2) stack="livewire" ;;
                    3) stack="react" ;;
                    4) stack="vue" ;;
                    5) stack="api" ;;
                esac

                # Add Breeze installation command
                if [ "$(echo "$dark_mode_choice" | tr '[:lower:]' '[:upper:]')" = "Y" ]; then
                    laravel_cmd="$laravel_cmd && php artisan breeze:install $stack --dark"
                else
                    laravel_cmd="$laravel_cmd && php artisan breeze:install $stack"
                fi

                # Add npm commands if not API stack
                if [ "$breeze_stack_choice" != "5" ]; then
                    laravel_cmd="$laravel_cmd && npm install && npm run build"
                fi
                ;;

            3)  # Jetstream
                laravel_cmd="$laravel_cmd && cd temp && composer require laravel/jetstream"
                
                # Add Jetstream installation command
                if [ "$jetstream_stack_choice" = "1" ]; then
                    if [ "$(echo "$teams_choice" | tr '[:lower:]' '[:upper:]')" = "Y" ]; then
                        laravel_cmd="$laravel_cmd && php artisan jetstream:install livewire --teams"
                    else
                        laravel_cmd="$laravel_cmd && php artisan jetstream:install livewire"
                    fi
                else
                    if [ "$(echo "$teams_choice" | tr '[:lower:]' '[:upper:]')" = "Y" ]; then
                        laravel_cmd="$laravel_cmd && php artisan jetstream:install inertia --teams"
                    else
                        laravel_cmd="$laravel_cmd && php artisan jetstream:install inertia"
                    fi
                fi

                laravel_cmd="$laravel_cmd && npm install && npm run build"
                ;;
        esac

        # Add Pest if selected
        if [ "$test_choice" = "2" ]; then
            laravel_cmd="$laravel_cmd && composer require pestphp/pest --dev --with-all-dependencies && php artisan pest:install"
        fi

        # Add final move commands
        laravel_cmd="$laravel_cmd && mv * .. && mv .* .. 2>/dev/null || true && cd .. && rm -rf temp"

        # Create Laravel project with all selected options
        echo "Creating new Laravel project..."
        if docker compose exec app bash -c "$laravel_cmd"; then
            # Add custom entries to .gitignore
            echo -e "\n# Custom entries\ndocker/\n.env.setup" >> .gitignore
            echo "Added custom entries to .gitignore"

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
