#!/bin/bash

setup_nuxt() {
    local project_name=$1
    local nginx_port=$2

    echo "Creating new Nuxt project..."
    if docker compose exec app bash -c "npm create nuxt@latest . << EOF
\n
\n
\n
\n
\n
EOF"; then
        echo "\nNuxt project created successfully!"
        echo "Environment configured with:"
        echo "- App URL: http://localhost:${nginx_port}"
        return 0
    else
        echo "\nError: Failed to create Nuxt project. Please check the following:"
        echo "1. Container logs: docker compose logs app"
        echo "2. Container status: docker compose ps"
        return 1
    fi
}
