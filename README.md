docker compose up -d --build

docker compose exec -u root library-app bash -c "cd /tmp && laravel new library-app && cp -r library-app/. /var/www/ && rm -rf library-app"


when the app is created and exists in /var/www/, run the following command to install the dependencies:
docker compose exec library-app php artisan migrate

when you are inside the container and the app is running, run the following command to start the queue:
docker compose exec library-app php artisan queue:work