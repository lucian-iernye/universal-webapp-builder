# Laravel Docker Development Setup

This repository contains a Docker setup for Laravel development with configurable PHP versions. The setup works across Windows, macOS, and Linux systems.

## Initial Setup

1. Run the setup script to choose your PHP version:

**On Windows (PowerShell):**
```powershell
.\setup.ps1

powershell -ExecutionPolicy Bypass -File setup.ps1
```

**On macOS/Linux:**
```bash
# Make the script executable
chmod +x setup.sh
# Run the script
./setup.sh
```

2. Build and start the containers:
```bash
docker compose up -d
```

3. Create a new Laravel project:
```bash
docker compose exec app composer create-project laravel/laravel .
```

4. Fix permissions:
```bash
docker compose exec app chown -R dev:dev .
```

5. Copy Laravel environment file:
```bash
cp .env.example .env
```

6. Generate application key:
```bash
docker compose exec app php artisan key:generate
```

## Available Services

- **Web Server**: http://localhost:8080
- **MySQL Database**: 
  - Main DB: localhost:3308
  - Test DB: localhost:3307

## Database Connections

### Main Database
- Host: mysql
- Port: 3306
- Database: laravel
- Username: laravel
- Password: secret

### Test Database
- Host: mysql-test
- Port: 3306
- Database: laravel_test
- Username: laravel
- Password: secret

## Running Commands

To run artisan commands:
```bash
docker compose exec app php artisan [command]
```

To run composer commands:
```bash
docker compose exec app composer [command]
```

## Running Tests

```bash
docker compose exec app php artisan test
```

## Supported PHP Versions

The setup script allows you to choose from the following PHP versions:
- PHP 7.3
- PHP 7.4
- PHP 8.1
- PHP 8.2
- PHP 8.3

You can change the PHP version at any time by running the setup script again and rebuilding the containers:
```bash
# Run setup script (see step 1 for your OS)
# Then rebuild containers
docker compose up -d --build