#!/usr/bin/env node

const readline = require('readline').createInterface({
    input: process.stdin,
    output: process.stdout,
});
const fs = require('fs');
const { spawn, execSync } = require('child_process');
const portscanner = require('portscanner');

async function askQuestion(query) {
    return new Promise(resolve => readline.question(query, resolve));
}

async function getProjectName() {
    let projectName;
    while (true) {
        projectName = await askQuestion("\nEnter your project name (lowercase, no spaces): ");
        if (/^[a-z0-9-]+$/.test(projectName)) {
            break;
        }
        console.log("Project name must be lowercase, and can only contain letters, numbers, and hyphens");
    }
    return projectName;
}

async function getProjectType() {
    console.log("\nSelect project type:");
    console.log("1. Laravel");
    console.log("2. Vue");
    console.log("3. Nuxt");

    while (true) {
        const projectTypeChoice = await askQuestion("Select project type (1-3): ");
        if (projectTypeChoice === '1') return 'laravel';
        if (projectTypeChoice === '2') return 'vue';
        if (projectTypeChoice === '3') return 'nuxt';
        console.log("Please enter a number between 1 and 3");
    }
}

async function getPhpVersion() {
    console.log("\nAvailable PHP versions:");
    console.log("1. PHP 7.3");
    console.log("2. PHP 7.4");
    console.log("3. PHP 8.1");
    console.log("4. PHP 8.2");
    console.log("5. PHP 8.3");

    while (true) {
        const selection = await askQuestion("Select PHP version (1-5): ");
        switch (selection) {
            case '1': return '7.3';
            case '2': return '7.4';
            case '3': return '8.1';
            case '4': return '8.2';
            case '5': return '8.3';
            default:
                console.log("Please enter a number between 1 and 5");
        }
    }
}

function checkPort(port) {
    return new Promise(resolve => {
        portscanner.checkPortStatus(port, 'localhost', (error, status) => {
            resolve(status === 'open'); // Returns true if port is open (in use)
        });
    });
}

async function findNextPort(startPort, maxPort) {
    for (let port = startPort; port <= maxPort; port++) {
        if (!(await checkPort(port))) {
            return port;
        }
    }
    return 0; // No available ports found
}

async function getPort(portName, defaultPort, minPort, maxPort) {
    let currentPort = '';
    if (await checkPort(defaultPort)) {
        const nextPort = await findNextPort(minPort, maxPort);
        if (nextPort === 0) {
            console.error(`Error: No available ports found in range ${minPort}-${maxPort} for ${portName}`);
            process.exit(1);
        }
        console.warn(`Warning: Default port ${defaultPort} for ${portName} is in use.`);
        console.warn(`Next available port is: ${nextPort}`);
        defaultPort = nextPort;
    }

    while (true) {
        const useDefault = await askQuestion(`Use default ${portName} port (${defaultPort})? [Y/n]: `);
        const useDefaultUpper = useDefault.toUpperCase() || 'Y';

        if (useDefaultUpper === 'Y') {
            currentPort = defaultPort.toString();
            break;
        } else if (useDefaultUpper === 'N') {
            while (true) {
                currentPort = await askQuestion(`Enter ${portName} port (${minPort}-${maxPort}): `);
                if (/^[0-9]+$/.test(currentPort) && parseInt(currentPort) >= minPort && parseInt(currentPort) <= maxPort) {
                    break;
                }
                console.log(`Please enter a valid port number between ${minPort} and ${maxPort}`);
            }
            break;
        } else {
            console.log("Please enter Y or n");
        }
    }
    return currentPort;
}

async function createDockerFile(version, projectName) {
    const dockerfileContent = `FROM php:${version}-fpm

ARG PROJECT_NAME
ENV PROJECT_NAME=\${PROJECT_NAME}

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    git \\
    curl \\
    libpng-dev \\
    libonig-dev \\
    libxml2-dev \\
    zip \\
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
RUN mkdir -p /home/dev/.composer && \\
    chown -R dev:dev /home/dev

# Set working directory
WORKDIR /var/www

USER dev
`;
    fs.mkdirSync('docker/php', { recursive: true });
    fs.writeFileSync('docker/php/Dockerfile', dockerfileContent);
    console.log(`Dockerfile has been created with PHP ${version}`);
}

async function createNginxConfig() {
    const nginxConfigContent = `server {
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
`;
    fs.mkdirSync('docker/nginx', { recursive: true });
    fs.writeFileSync('docker/nginx/default.conf', nginxConfigContent);
}

async function createEnvSetupFile(projectName, version, phpPort, mysqlPort, mysqlTestPort, redisPort, nginxPort) {
    const envSetupContent = `# Docker Settings
COMPOSE_PROJECT_NAME=${projectName}
PHP_VERSION=${version || '8.2'} # Default to 8.2 if not set (for Vue/Nuxt)

# Main Database
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=${mysqlPort}
DB_DATABASE=${projectName}_db
DB_USERNAME=${projectName}_user
DB_PASSWORD=secret
DB_ROOT_PASSWORD=secret

# Test Database
DB_TEST_HOST=mysql-test
DB_TEST_PORT=${mysqlTestPort}
DB_TEST_DATABASE=${projectName}_test_db
DB_TEST_USERNAME=${projectName}_test_user
DB_TEST_PASSWORD=secret
DB_TEST_ROOT_PASSWORD=secret

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=${redisPort}

# Ports
NGINX_PORT=${nginxPort}
PHP_PORT=${phpPort}
`;

    await fs.writeFileSync('.env.setup', envSetupContent);
    await fs.copyFileSync('.env.setup', '.env');

    console.log(`.env.setup file has been created with project name ${projectName} and PHP version ${version || 'default'}`);

    // await dockerComposeUp(projectName);
}

async function dockerComposeUp(projectName) {
    console.log("\nStarting Docker containers...");
    try {
        execSync(`docker ps -a --filter "name=${projectName}" --format '{{.Names}}'`, { stdio: 'ignore' });
        console.log("Stopping existing containers...");
        execSync('docker compose down', { stdio: 'inherit' });
    } catch (error) {
        // Ignore if no containers are found
    }
    return new Promise((resolve, reject) => {
        const dockerUp = spawn('docker', ['compose', 'up', '-d', '--build'], { stdio: 'inherit' });
        dockerUp.on('close', (code) => {
            if (code === 0) {
                console.log("\nDocker containers are starting up");
                console.log(`Project name: ${projectName}`);
                resolve();
            } else {
                reject(new Error(`docker compose up exited with code ${code}`));
            }
        });
        dockerUp.on('error', (err) => {
            reject(err);
        });
    });
}

async function checkContainerReady(projectName) {
    console.log("Waiting for containers to be ready...");
    let attempts = 0;
    const maxAttempts = 30;
    return new Promise((resolve, reject) => {
        const intervalId = setInterval(async () => {
            attempts++;
            try {
                const output = execSync('docker compose ps --format json app');
                const containers = JSON.parse(output.toString());
                const isRunning = containers.some(container => container.State === 'running');
                if (isRunning) {
                    clearInterval(intervalId);
                    resolve();
                    return;
                }
            } catch (error) {
                 // Ignore errors, container might not be ready yet
            }

            if (attempts >= maxAttempts) {
                clearInterval(intervalId);
                reject(new Error(`Container ${projectName}-app is not ready after waiting. Please check docker logs for issues.`));
            } else {
                console.log(`Attempt ${attempts}/${maxAttempts}: Container not ready yet...`);
            }
        }, 2000);
    });
}


async function createLaravelProject(projectName, nginxPort, redisPort, mysqlPort) {
    console.log("Creating new Laravel project...");
    // await checkContainerReady(projectName);

    // Remove existing .env and .gitignore
    // try { fs.rmSync('.env'); } catch (e) {}
    // try { fs.rmSync('.gitignore'); } catch (e) {}

    const createProjectCmd = `composer create-project laravel/laravel temp --prefer-dist`;
    console.log(`Running command: docker compose exec app bash -c '${createProjectCmd}'`);
    try {
        execSync(`docker compose exec app bash -c '${createProjectCmd}'`, { stdio: 'inherit' });
    } catch (error) {
        console.error("\nError: Failed to create Laravel project. Please check docker logs: docker compose logs app");
        process.exit(1);
    }
    console.log("Laravel app created in temp folder.");

    console.log("Moving Laravel app to root directory...");
    try {
        // Move all visible files first
        execSync(`docker compose exec app bash -c 'mv temp/* . 2>/dev/null || true'`, { stdio: 'inherit' });
        // Move hidden files excluding . and ..
        execSync(`docker compose exec app bash -c 'mv temp/.[!.]* . 2>/dev/null || true'`, { stdio: 'inherit' });
        // Remove the temp directory
        execSync(`docker compose exec app bash -c 'rm -rf temp'`, { stdio: 'inherit' });
    } catch (error) {
        console.error("Error moving Laravel app to root directory:", error);
        process.exit(1);
    }
    console.log("Laravel app moved to root directory.");

    // Laravel Setup Options - Authentication, Stack, Testing (Prompts and Install) - ... (rest of the Laravel setup logic as in the bash script, translated to Node.js) ...
     // Get Laravel setup preferences
     console.log("\nLaravel Project Setup Options:\n");

     // Authentication
     console.log("Select authentication setup:");
     console.log("1. No authentication (skip)");
     console.log("2. Laravel Breeze (minimal)");
     console.log("3. Laravel Jetstream");
     let authChoice;
     while (true) {
         authChoice = await askQuestion("Choose authentication (1-3): ");
         if (['1', '2', '3'].includes(authChoice)) {
             break;
         }
         console.log("Please enter a number between 1 and 3");
     }

     let breezeStackChoice = '';
     let jetstreamStackChoice = '';
     let darkModeChoice = 'n';
     let teamsChoice = 'n';
     let testChoice = '1';

     // If Breeze selected, get stack preference
     if (authChoice === '2') {
         console.log("\nSelect Breeze stack:");
         console.log("1. Blade with Alpine.js");
         console.log("2. Livewire (Blade + Alpine.js + Livewire)");
         console.log("3. React with Inertia");
         console.log("4. Vue with Inertia");
         console.log("5. API only");
         while (true) {
             breezeStackChoice = await askQuestion("Choose stack (1-5): ");
             if (['1', '2', '3', '4', '5'].includes(breezeStackChoice)) {
                 break;
             }
             console.log("Please enter a number between 1 and 5");
         }

         const phpVersionOutput = execSync('php -v').toString();
         const phpVersionMatch = phpVersionOutput.match(/^PHP\s+([0-9]+\.[0-9]+)/m);
         const phpVersionDetected = phpVersionMatch ? phpVersionMatch[1] : '7.0'; // Default to 7.0 if not detected
         const phpMajorVersion = parseInt(phpVersionDetected.split('.')[0]);

         if (phpMajorVersion >= 8) {
             darkModeChoice = await askQuestion("Would you like to include dark mode support? [y/n]: ");
         } else {
             console.log(`Skipping dark mode installation (requires PHP ≥8.0, detected ${phpVersionDetected})`);
         }
     }

     // If Jetstream selected, get stack preference
     if (authChoice === '3') {
         console.log("\nSelect Jetstream stack:");
         console.log("1. Livewire + Blade");
         console.log("2. Inertia + Vue.js");
         while (true) {
             jetstreamStackChoice = await askQuestion("Choose stack (1-2): ");
             if (['1', '2'].includes(jetstreamStackChoice)) {
                 break;
             }
             console.log("Please enter 1 or 2");
         }
         teamsChoice = await askQuestion("Would you like to include team support? [y/n]: ");
     }

     // Testing preference
     console.log("\nSelect testing framework:");
     console.log("1. PHPUnit (default)");
     console.log("2. Pest (recommended)");
     while (true) {
         testChoice = await askQuestion("Choose testing framework (1-2): ");
         if (['1', '2'].includes(testChoice)) {
             break;
         }
         console.log("Please enter 1 or 2");
     }

     // Install selected features
     if (authChoice === '2') { // Breeze
         execSync(`docker compose exec app bash -c 'composer require laravel/breeze --dev'`, { stdio: 'inherit' });

         let stack = '';
         switch (breezeStackChoice) {
             case '1': stack = 'blade'; break;
             case '2': stack = 'livewire'; break;
             case '3': stack = 'react'; break;
             case '4': stack = 'vue'; break;
             case '5': stack = 'api'; break;
         }

         let breezeInstallCmd = `php artisan breeze:install ${stack}`;
         if (darkModeChoice.toUpperCase() === 'Y') {
             breezeInstallCmd = `php artisan breeze:install ${stack} --dark`;
         }
         execSync(`docker compose exec app bash -c '${breezeInstallCmd}'`, { stdio: 'inherit' });

         if (breezeStackChoice !== '5') {
             execSync(`docker compose exec app bash -c 'npm install && npm run build'`, { stdio: 'inherit' });
         }
     } else if (authChoice === '3') { // Jetstream
         execSync(`docker compose exec app bash -c 'composer require laravel/jetstream'`, { stdio: 'inherit' });

         let jetstreamInstallCmd = `php artisan jetstream:install `;
         if (jetstreamStackChoice === '1') {
             jetstreamInstallCmd += `livewire`;
         } else {
             jetstreamInstallCmd += `inertia`;
         }
         if (teamsChoice.toUpperCase() === 'Y') {
             jetstreamInstallCmd += ` --teams`;
         }
         execSync(`docker compose exec app bash -c '${jetstreamInstallCmd}'`, { stdio: 'inherit' });
         execSync(`docker compose exec app bash -c 'npm install && npm run build'`, { stdio: 'inherit' });
     }

     // Add Pest if selected
     if (testChoice === '2') {
         execSync(`docker compose exec app bash -c 'composer require pestphp/pest --dev --with-all-dependencies && php artisan pest:install'`, { stdio: 'inherit' });
     }


    // Add custom entries to .gitignore
    fs.appendFileSync('.gitignore', '\n# Custom entries\ndocker/\n.env.setup');
    console.log("Added custom entries to .gitignore");

    // Update Laravel .env with values from .env.setup
    let envContent = fs.readFileSync('.env.setup', 'utf8');
    envContent = envContent.replace(/APP_NAME=.*?(\r?\n)/, `APP_NAME=${projectName}$1`);
    envContent = envContent.replace(/APP_URL=.*?(\r?\n)/, `APP_URL=http://localhost:${nginxPort}$1`);
    envContent = envContent.replace(/DB_PORT=.*?(\r?\n)/, `DB_PORT=${mysqlPort}$1`);
    envContent = envContent.replace(/DB_DATABASE=.*?(\r?\n)/, `DB_DATABASE=${projectName}_db$1`);
    envContent = envContent.replace(/DB_USERNAME=.*?(\r?\n)/, `DB_USERNAME=${projectName}_user$1`);
    envContent = envContent.replace(/REDIS_PORT=.*?(\r?\n)/, `REDIS_PORT=${redisPort}$1`);
    fs.writeFileSync('.env', envContent);

    console.log("\nLaravel project created and configured successfully!");
    console.log("Environment configured with:");
    console.log(`- App URL: http://localhost:${nginxPort}`);
    console.log(`- Database: ${projectName}_db`);
    console.log(`- DB User: ${projectName}_user`);
    console.log(`- Redis Port: ${redisPort}`);
}

async function createNuxtProject(projectName) {
    console.log("Creating new Nuxt project...");
    await checkContainerReady(projectName);
    execSync(`docker compose exec app bash -c 'npm create nuxt@latest . << EOF\\n\\n\\n\\n\\nEOF'`, { stdio: 'inherit' });
    console.log("\nNuxt project created successfully!");
    console.log("Next steps:");
    console.log("1. Install dependencies: docker compose exec app npm install");
    console.log("2. Start development server: docker compose exec app npm run dev");
}

async function createVueProject(projectName) {
    console.log("Creating new Vue project...");
    await checkContainerReady(projectName);
    execSync(`docker compose exec app bash -c 'npm create vue@latest . << EOF\\n\\n\\n\\n\\n\\nEOF'`, { stdio: 'inherit' });
    console.log("\nVue project created successfully!");
    console.log("Next steps:");
    console.log("1. Install dependencies: docker compose exec app npm install");
    console.log("2. Start development server: docker compose exec app npm run dev");
}


async function main() {
    const projectType = await getProjectType();
    const projectName = await getProjectName();
    let phpVersion = '8.2'; // Default for Vue/Nuxt
    if (projectType === 'laravel') {
        phpVersion = await getPhpVersion();
         // Check PHP version compatibility warnings (same as bash script warnings)
        console.log("\nChecking PHP version compatibility...");
        switch (phpVersion) {
            case "8.1":
                console.warn("⚠️  Warning: PHP 8.1");
                console.warn("   - Laravel 11+ requires PHP 8.2 or higher");
                console.warn("   - Laravel Breeze 2+ requires PHP 8.2 or higher");
                console.warn("   - Some packages may require PHP 8.2");
                break;
            case "7.4":
                console.warn("⚠️  Warning: PHP 7.4");
                console.warn("   - Laravel 9+ requires PHP 8.0 or higher");
                console.warn("   - Laravel 8.x will be used");
                console.warn("   - Many packages may have compatibility issues");
                break;
            case "7.3":
                console.warn("⚠️  Warning: PHP 7.3");
                console.warn("   - Laravel 8+ requires PHP 7.4 or higher");
                console.warn("   - Laravel 7.x will be used");
                console.warn("   - Many packages may have compatibility issues");
                break;
            default:
                if (phpVersion !== "8.2" && phpVersion !== "8.3") {
                    console.warn(`⚠️  Warning: PHP version ${phpVersion} might have compatibility issues with Laravel`);
                }
        }
        await askQuestion("\nPress Enter to continue or Ctrl+C to abort");
    }


    const phpPort = await getPort("PHP", 9000, 9000, 9100);
    const mysqlPort = await getPort("MySQL", 3306, 3306, 3399);
    const mysqlTestPort = await getPort("MySQL Test", parseInt(mysqlPort) + 1, parseInt(mysqlPort) + 1, 3399);
    if (mysqlTestPort === mysqlPort) {
        console.error("Error: Test database port must be different from primary database port");
        process.exit(1);
    }
    const redisPort = await getPort("Redis", 6379, 6379, 6400);
    const nginxPort = await getPort("Nginx", 8080, 8080, 8100);

    await createDockerFile(phpVersion, projectName);
    await createNginxConfig();
    await createEnvSetupFile(projectName, phpVersion, phpPort, mysqlPort, mysqlTestPort, redisPort, nginxPort);

    // Log content of .env.setup for debugging
    console.log("\n--- .env.setup content ---");
    console.log(fs.readFileSync('.env.setup', 'utf8'));
    console.log("--- end .env.setup content ---\n");


    // **ADD THIS LINE:**
    fs.copyFileSync('.env.setup', '.env');
    console.log(".env file has been created by copying from .env.setup"); // Optional confirmation log

    // Log content of .env for debugging
    console.log("\n--- .env content ---");
    console.log(fs.readFileSync('.env', 'utf8'));
    console.log("--- end .env content ---\n");


    await dockerComposeUp(projectName);


    if (projectType === 'laravel') {
        setTimeout(async () => {
            await createLaravelProject(projectName, nginxPort, redisPort, mysqlPort);
        }, 2000)
    } else if (projectType === 'nuxt') {
        await createNuxtProject(projectName);
    } else if (projectType === 'vue') {
        await createVueProject(projectName);
    }

    console.log("\nNote: The .env.setup file contains your Docker configuration");
    readline.close();
}

main().catch(error => {
    console.error("An error occurred:", error);
    readline.close();
    process.exit(1);
});