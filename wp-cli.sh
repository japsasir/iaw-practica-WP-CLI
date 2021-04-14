#!/bin/bash

###-------------------------------------------------------###
### Script para montar un servidor con Wordpress y MySQL  ###
###-------------------------------------------------------###

## Variables
#!! IP pública. ¡Hay que adaptarla con cada cambio!
IP_PUBLICA=
# Contraseña aleatoria para el parámetro blowfish_secret
BLOWFISH=`tr -dc A-Za-z0-9 < /dev/urandom | head -c 64`
# Directorio de usuario
HTTPASSWD_DIR=/home/ubuntu
HTTPASSWD_USER=usuario
HTTPASSWD_PASSWD=usuario
# MySQL
DB_ROOT_PASSWD=root
DB_NAME=wordpress_db
DB_USER=wordpress_user
DB_PASSWORD=wordpress_password

# ------------------------------------------------------------------------------ Instalación y configuración de Apache, MySQL y PHP------------------------------------------------------------------------------ 

# Habilitamos el modo de shell para mostrar los comandos que se ejecutan
set -x
# Actualizamos y actualizamos la lista de paquetes
apt update  
## apt upgrade -y   #Comentado por agilizar la entrega

# Instalamos Apache
apt install apache2 -y

# Instalamos el sistema gestor de base de datos
apt install mysql-server -y

# Instalamos los módulos PHP necesarios para Apache
apt install php libapache2-mod-php php-mysql -y

# Reiniciamos el servicio Apache 
systemctl restart apache2


## REVISAR !!!
# Copiamos el archivo info.php adjunto al directorio html. No es necesario extraer de la carpeta.
cp $HTTPASSWD_DIR iaw-practica-08/info.php /var/www/html/info.php

# Configuramos las opciones de instalación de phpMyAdmin
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $BLOWFISH" |debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $BLOWFISH" | debconf-set-selections

# Instalamos phpMyAdmin 
apt install phpmyadmin php-mbstring php-zip php-gd php-json php-curl -y

# ------------------------------------------------------------------------------ Instalación y configuración de Wordpress------------------------------------------------------------------------------ 
# Ideas de instalación: https://codex.wordpress.org/es:Instalando_Wordpress
## Fase 1: Descarga y extracción ##
# Directorio raíz de nuestro apache
cd /var/www/html
# Descargamos Wordpress 
wget http://wordpress.org/latest.tar.gz
# Eliminamos instalaciones anteriores por seguridad
rm -rf /var/www/html/wordpress
# Descomprimimos el archivo que acabamos de descargar 
tar -xzvf latest.tar.gz
# Limpiamos el archivo comprimido residual.
rm latest.tar.gz

## Fase 2: Crear base de datos y un usuario##

# Por seguridad, hacemos un borrado preventivo de la base de datos wordpress_db
mysql -u root <<< "DROP DATABASE IF EXISTS $DB_NAME;"
# Creamos la base de datos wordpress_db
mysql -u root <<< "CREATE DATABASE $DB_NAME;"
# Nos aseguramos que no existe el usuario automatizado
mysql -u root <<< "DROP USER IF EXISTS $DB_USER@localhost;"
# Creamos el usuario 'wordpress_user' para Wordpress
mysql -u root <<< "CREATE USER $DB_USER@localhost IDENTIFIED BY '$DB_PASSWORD';"
# Concedemos privilegios al usuario que acabamos de crear
mysql -u root <<< "GRANT ALL PRIVILEGES ON $DB_NAME.* TO $DB_USER@localhost;"
# Aplicamos cambios con un comando flush. Esto evita tener que reiniciar mysql.
mysql -u root <<< "FLUSH PRIVILEGES;"

## Fase 3:Configurar el archivo wp-config.php##

# En primer lugar, borramos el index.html de Apache para evitar conflictos con nuestro php.
rm /var/www/html/index.html
# Creamos wp-config.php a partir de la plantilla
mv /var/wwww/html/wordpress/wp-config-sample.php /var/wwww/html/wordpress/wp-config.php
# Definimos variables dentro del archivo config de Wordpress.
# Base de datos
sed -i "s/database_name_here/$DB_NAME/" /var/www/html/wordpress/wp-config.php
# Usuario
sed -i "s/username_here/$DB_USER/" /var/www/html/wordpress/wp-config.php
# Contraseña
sed -i "s/password_here/$DB_PASSWORD/" /var/www/html/wordpress/wp-config.php

## Fase 4: Coloca los archivos##
# Vamos a colocar nuestros archivos en directorios diferentes al raíz. Vamos a ubicar todo en la carpeta que empleamos en prácticas anteriores.

# Copiamos el archivo /var/www/html/wordpress/index.php a /var/www/html/index.php 
cp /var/www/html/wordpress/index.php  /var/www/html/index.php

# Cambiamos la url de WordPress con WP_SITEURL y WP_HOME. El archivo de configuración modificado es el de la fase anterior.
sed -i "/DB_COLLATE/a define( 'WP_SITEURL', 'http://$IP_PUBLICA/wordpress' );" /var/www/html/wordpress/wp-config.php
sed -i "/WP_SITEURL/a define( 'WP_HOME', 'http://$IP_PUBLICA' );" /var/www/html/wordpress/wp-config.php

# Editamos el archivo /var/www/html/index.php para que la ruta sea correcta
sed -i "s#/wp-blog-header.php#/wordpress/wp-blog-header.php#" /var/www/html/index.php

# Copiamos el archivo htaccess incluido en nuestro repositorio git. No es necesario extraer de la carpeta. Hará de balanceador de carga en siguientes fases.
cp $HTTPASSWD_DIR iaw-WP-CLI/htaccess /var/www/html/.htaccess

# Configuración de las security keys. Estas claves añaden elementos aleatorios a la contraseña, lo cual ralentiza una entrada 'forzada'
# Se emplean 4 claves. Los cuatro campos 'salt' tienen un valor por defecto otorgado por Wordpress, pero lo podemos cambiar.

# Borramos el bloque que nos viene por defecto en el archivo de configuración 
sed -i "/AUTH_KEY/d" /var/www/html/wordpress/wp-config.php
sed -i "/SECURE_AUTH_KEY/d" /var/www/html/wordpress/wp-config.php
sed -i "/LOGGED_IN_KEY/d" /var/www/html/wordpress/wp-config.php
sed -i "/NONCE_KEY/d" /var/www/html/wordpress/wp-config.php
sed -i "/AUTH_SALT/d" /var/www/html/wordpress/wp-config.php
sed -i "/SECURE_AUTH_SALT/d" /var/www/html/wordpress/wp-config.php
sed -i "/LOGGED_IN_SALT/d" /var/www/html/wordpress/wp-config.php
sed -i "/NONCE_SALT/d" /var/www/html/wordpress/wp-config.php

# Definimos la variable SECURITY_KEYS haciendo una llamada a la API de Wordpress. 
SECURITY_KEYS=$(curl https://api.wordpress.org/secret-key/1.1/salt/)

# Reemplazamos "/" por "_" para que no nos falle el comando sed. Recordemos que emplear '/' en configuraciones suele llevarnos a error.
SECURITY_KEYS=$(echo $SECURITY_KEYS | tr / _)

# Creamos un nuevo bloque de SECURITY KEYS
sed -i "/@-/a $SECURITY_KEYS" /var/www/html/wordpress/wp-config.php

# Habilitamos el módulo rewrite (reescritura de las url)
a2enmod rewrite

# Le damos permisos al servidor web para /var/www/html como en prácticas anteriores
chown -R www-data:www-data /var/www/html

# Reiniciamos Apache
systemctl restart apache2

# ------------------------------------------------------------------------------ WP - CLI------------------------------------------------------------------------------ 

## Instalación de WP-CLI en el servidor LAMP

# Descargamos y guardamos el contenido de wp-cli.phar
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

# Le asignamos permisos de ejecución al archivo
chmod +x wp-cli.phar

# Movemos el archivo y cambiamos el nombre  a wp. A partir de aquí, la terminal debería ayudarnos usando 'wp'
mv wp-cli.phar /usr/local/bin/wp


# Eliminamos index.html
rm -rf index.html

# Descargamos el código fuente de Wordpress en Español y le damos permiso de root
wp core download --path=/var/www/html --locale=es_ES --allow-root

# Permisos necesarios sobre la carpeta de wordpress
chown -R www-data:www-data /var/www/html

# Creamos el archivo de configuración de Wordpress. Podemos revisarlo luego con el comando 'wp config get'
wp config create --dbname=$DB_NAME --dbuser=$DB_USER --dbpass=$DB_PASSWORD --allow-root

# Instalamos Wordpress con la configuración. Recordatorio de actualizar la IP en la lista de variables.
wp core install --url=$IP_PUBLICA --title="IAW Padilla" --admin_user=admin --admin_password=admin_password --admin_email=test@test.com --allow-root
