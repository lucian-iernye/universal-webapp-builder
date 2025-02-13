#!/bin/bash

setup_laravel() {
    local project_name=$1
    local php_version=$2
    local nginx_port=$3
    local mysql_port=$4
    local redis_port=$5

    echo "Setting up Laravel project..."

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
        return 0
    else
        echo "\nError: Failed to create Laravel project. Please check the following:"
        echo "1. Container logs: docker compose logs app"
        echo "2. Container status: docker compose ps"
        echo "3. Try running the command manually: docker compose exec app bash -c 'composer create-project laravel/laravel temp && mv temp/* . && mv temp/.* . && rm -rf temp'"
        return 1
    fi
}
