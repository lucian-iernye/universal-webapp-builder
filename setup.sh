#!/bin/bash

# Source project-specific scripts
source "$(dirname "$0")/scripts/laravel.sh"
source "$(dirname "$0")/scripts/vue.sh"
source "$(dirname "$0")/scripts/nuxt.sh"

# Function to copy configuration files
copy_config_files() {
    local project_type=$1
    local dest_dir=$2
    
    # Copy configuration files
    cp -r "config/${project_type}/"* "$dest_dir/"
    
    echo "Configuration files copied successfully!"
}

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

# Function to get port with default option
get_port() {
    local port_name=$1
    local default_port=$2
    
    while true; do
        if ! check_port $default_port; then
            echo "Warning: Default port $default_port for $port_name is in use."
            read -p "Enter a different port number: " port
            if check_port $port; then
                default_port=$port
                break
            fi
        else
            break
        fi
    done
    
    echo $default_port
}

# Get project name
while true; do
    echo -e "\nEnter your project name (lowercase, no spaces):"
    read project_name
    if [[ $project_name =~ ^[a-z0-9-]+$ ]]; then
        break
    fi
    echo "Project name must be lowercase, and can only contain letters, numbers, and hyphens"
done

# Create project directory
mkdir -p "$project_name"
cd "$project_name"

# Select project type
echo -e "\nSelect project type:"
echo "1. Laravel"
echo "2. Vue"
echo "3. Nuxt"

while true; do
    read -p "Select project type (1-3): " project_type
    if [[ $project_type =~ ^[1-3]$ ]]; then
        break
    fi
    echo "Please enter a number between 1 and 3"
done

# Set up environment variables and copy configurations
case $project_type in
    1) # Laravel
        echo "Setting up Laravel project..."
        
        # Get PHP version for Laravel
        echo -e "\nAvailable PHP versions:"
        echo "1. PHP 8.1"
        echo "2. PHP 8.2"
        echo "3. PHP 8.3"
        
        while true; do
            read -p "Select PHP version (1-3): " php_selection
            if [[ $php_selection =~ ^[1-3]$ ]]; then
                break
            fi
            echo "Please enter a number between 1 and 3"
        done
        
        case $php_selection in
            1) php_version="8.1" ;;
            2) php_version="8.2" ;;
            3) php_version="8.3" ;;
        esac
        
        # Get ports
        nginx_port=$(get_port "Nginx" 80)
        mysql_port=$(get_port "MySQL" 3306)
        redis_port=$(get_port "Redis" 6379)
        
        # Create Docker environment file
        cat > .env << EOF
PROJECT_NAME=${project_name}
DB_PORT=${mysql_port}
REDIS_PORT=${redis_port}
NGINX_PORT=${nginx_port}
PHP_VERSION=${php_version}
EOF
        
        # Copy configurations
        copy_config_files "laravel" "."
        
        # Set PHP version in Dockerfile
        sed -i "" "s/PHP_VERSION=.*/PHP_VERSION=${php_version}/" Dockerfile
        
        # Start containers
        docker compose up -d
        
        # Set up Laravel
        setup_laravel "$project_name" "$php_version" "$nginx_port" "$mysql_port" "$redis_port"
        ;;
        
    2) # Vue
        # Get ports
        app_port=$(get_port "App" 8080)
        nginx_port=$(get_port "Nginx" 80)
        
        # Create Docker environment file
        cat > .env << EOF
PROJECT_NAME=${project_name}
PORT=${app_port}
NGINX_PORT=${nginx_port}
EOF
        
        # Copy configurations
        copy_config_files "vue" "."
        
        # Start containers
        docker compose up -d
        
        # Set up Vue
        setup_vue "$project_name" "$nginx_port"
        ;;
        
    3) # Nuxt
        # Get ports
        app_port=$(get_port "App" 3000)
        nginx_port=$(get_port "Nginx" 80)
        
        # Create Docker environment file
        cat > .env << EOF
PROJECT_NAME=${project_name}
PORT=${app_port}
NGINX_PORT=${nginx_port}
EOF
        
        # Copy configurations
        copy_config_files "nuxt" "."
        
        # Start containers
        docker compose up -d
        
        # Set up Nuxt
        setup_nuxt "$project_name" "$nginx_port"
        ;;
esac

echo "\nProject setup complete!"
echo "Your project is available at: http://localhost:${nginx_port}"
            # Copy Laravel configurations
            cp -r "../config/laravel/docker" .
            cp -r "../config/laravel/nginx/default.conf" nginx/
            cp "../config/laravel/docker-compose.yml" .
            
            # Start containers
            docker compose up -d
            
            echo "Installing Laravel..."
            docker compose exec app composer create-project laravel/laravel .
            
            # Move Laravel .env file to correct location
            mv .env.laravel .env
            ;;
            
        2) # Vue
            # Copy Vue configurations
            cp -r "../config/vue/docker" .
            cp -r "../config/vue/nginx/default.conf" nginx/
            cp "../config/vue/docker-compose.yml" .
            
            # Start containers
            docker compose up -d
            
            echo "Installing Vue..."
            docker compose exec app npm create vue@latest .
            
            # Move Vue .env file to correct location
            mv .env.local .env
            ;;
            
        3) # Nuxt
            # Copy Nuxt configurations
            cp -r "../config/nuxt/docker" .
            cp -r "../config/nuxt/nginx/default.conf" nginx/
            cp "../config/nuxt/docker-compose.yml" .
            
            # Start containers
            docker compose up -d
            
            echo "Installing Nuxt..."
            docker compose exec app npx nuxi init .
            ;;
    esac
    
    echo "\nProject setup complete! Your project is available at:"
    echo "http://localhost:${nginx_port}"
}

# Initialize the project
initialize_project $project_type "$project_name"


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

        


