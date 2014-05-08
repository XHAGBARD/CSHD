#!/bin/bash

#
#Seedbox CinemaScopeHD Server
#
##################################################################
#
# Copyright (c) 2014  (https://github.com/XHAGBARD/)
#
# Script instalador de los servicios completos y necesarios para el funcionamiento del servidor de Streaming y Cloud
#
#
#
#Comprobacion de poderes#
if [ "`id -u`" != 0 ] ; then
echo "ERROR: Necesitas tener permisos de root para ejecutar el script."
exit 1
fi
#@VARIABLES##
#===========#

#Opcion de cambiar la contraseña de root

#while true; do
#    read -p "¿Deseas cambiar la contraseña de root?" yn
#    case $yn in
#        [Ss]* ) passwd root;
#                if [ $? -gt 0 ]; then
#        echo
#        echo "**** ERROR ****"
#        echo
#        exit
#fi; break;;
#        [Nn]* ) break;;
#        * ) echo "Ss o Nn.";;
#    esac
#done

#Almacenar contraseña
cont=0
while [ "$cont" = 0 ]; do
echo Contraseña de root:
    read -s pass
echo Repita la contraseña:
    read -s pass2

        if [ "$pass" != "$pass2" ]; then
        clear
        else
        cont=1
        break
        fi

done

#Cambiamos la contraseña de root
(echo $pass; echo $pass) | passwd root

#Recogemos nombre de root
csid=$(id -nu)

#Recogemos el nombre del equipo
nombre=$(uname -n)

#Recogemos la ip del sistema
ip=$(ip addr show eth0 | grep "inet " | sed "s/^.*inet //" | sed "s/\/.*$//" )

##PUERTOS##
#=========#

#Puerto OpenVPN
echo -e -n "Puerto OpenVPN [Por Defecto: 1194]: "
read puertovpn_pre
if [ "$puertovpn_pre" = "" ]; then
puertovpn=1194
else
puertovpn=$puertovpn_pre
fi

#Puerto SSH
echo -e -n "Puerto SSH [Por Defecto: 21976]: "
read puertossh_pre
if [ "$puertossh_pre" = "" ]; then
puertossh=21976
else
puertossh=$puertossh_pre
fi

#Fin PUERTOS

#Almacenamos la contraseña de mysql en debconf para desatenderla del usuario.
debconf-set-selections <<< "mysql-server mysql-server/root_password password $pass"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $pass"

#Almacenamos la contraseña de phpmyadmin en debconf para desatenderla del usuario.
debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean true'
debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $pass"
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $pass"
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $pass"
debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2'

##Instalación##
#=============#

#Añadimos Webmin al repositorio
#Descargamos clave PGP
cd /tmp
wget http://www.webmin.com/jcameron-key.asc

#Añadimos la clave
apt-key add jcameron-key.asc

#Añadimos la ruta al repositorio
echo "deb http://download.webmin.com/download/repository sarge contrib" | sudo tee -a /etc/apt/sources.list

#Actualizacion de los repositorios#
apt-get update

#Actualizacion del sistema#
apt-get -y upgrade

#Instalacion de los paquetes necesarios para el servidor#
apt-get install -y apache2 php5 php5-curl libapache2-mod-php5 mysql-client mysql-server phpmyadmin sendmail vsftpd lftp samba samba-common smbfs smbclient openvpn openssl openssh-server zip quota whois sudo makepasswd webmin mailutils

if [ $? -gt 0 ]; then
        echo
        echo "**** ERROR ****"
        echo
        exit
fi;

#Creamos el grupo para los usuarioa
groupadd -g 1221 usuarios

#Creamos carpeta para usarla posteriormente
mkdir /etc/cshd/

#Creamos carpeta para los backups
mkdir /etc/cshd/backup

##Apache2##
#========#
#Activacion modulo mod_rewrite
a2enmod rewrite

#Habilitar sites por defecto
cp /etc/apache2/sites-available/default /etc/apache2/sites-enabled/default

#Modificar AllowOverride del default
sed -i '8,13 s/AllowOverride None/AllowOverride All/g' /etc/apache2/sites-enabled/default

#Añadir modulo Zend  para soporte Joomla
echo "zend_extension = /usr/lib/php5/20090626/ioncube_loader_lin_5.3.so" >> /etc/php5/apache2/php.ini

#Copiamos el módulo Zend a su directorio
cp ~/CSHD/source/ioncube_loader_lin_5.3.so /usr/lib/php5/20090626/

##Fin Apache2##

##Permisos para www-data##
#========================#
#Modificamos sudoers para añadir al usuario www-data permisos de ejecucion en useradd, smbpasswd, mkpasswd y setquota
echo " " >> /etc/sudoers
echo "www-data  ALL=(ALL) NOPASSWD: /usr/sbin/useradd, /usr/sbin/smbpasswd, /usr/sbin/mkpasswd, /usr/sbin/setquota" >> /etc/sudoers

#Modificamos el php.ini para eliminar la restriccion de "exec"
sed -i '/,pcntl_exec/d' /etc/php5/apache2/php.ini

#Script para añadir usuarios en registro de Joomla
#Permisos
touch /var/www/csexec.sh
chmod +x /var/www/csexec.sh
chown www-data:www-data csexec.sh

#Script
echo "#!/bin/bash" >> /var/www/csexec.sh
echo "mes=$[$(date +%m)+1]" >> /var/www/csexec.sh
echo "sudo useradd -m -e $(date +%d/$mes/%Y) -g 1221 -s /bin/false -p $(mkpasswd --hash=SHA-512 $2) $1" >> /var/www/csexec.sh
echo "(echo $2; echo $2) | sudo smbpasswd -s -a -U $1" >> /var/www/csexec.sh
echo "setquota -u $1 1457280 30000000 0 0 /home" >> /var/www/csexec.sh

##Copia de Seguridad##
#====================#

#Programamos copia de seguridad para la BBDD
#Creamos el script
touch /etc/cshd/cps.sh
echo "#!/bin/bash" >> /etc/cshd/cps.sh
echo "date=$(date +%d%b%Y)" >> /etc/cshd/cps.sh
echo "tar -jvcf /etc/cshd/bakup/www-$date.tar.bz2 /var/www/" >> /etc/cshd/cps.sh
echo "mysqldump -u$csid -p$pass -r/home/cshd/mysql_joomla-$date.sql joomla" >> /etc/cshd/cps.sh
echo "mysqldump -u$csid -p$pass -r/home/cshd/mysql_phpbb3-$date.sql joomla_phpBB3" >> /etc/cshd/cps.sh


#Asignamos permisos de ejecución
chmod +x /etc/cshd/cps.sh

#Programamos cron para iniciar la copia semanalmente los lunes a la madrugada
echo "0 0 * * 1 root /etc/cshd/cps.sh" >> /etc/crontab

##Fin Copia de Seguridad##

##SSH##
#=====#
#Copia de seguridad
if [ -f /etc/ssh/sshd_config_bak ]; then
continue
else
cp /etc/ssh/sshd_config /etc/ssh/sshd_config_bak

fi

#Cambiamos el puerto por defecto para mayor seguridad
perl -pi -e "s/Port 22/Port $puertossh/g" /etc/ssh/sshd_config

#Habilitamos la version 2
perl -pi -e "s/\#Protocol 2/Protocol 2/g" /etc/ssh/sshd_config

#Ampliamos la seguridad a 1024
perl -pi -e "s/ServerKeyBits 768/ServerKeyBits 1024/g" /etc/ssh/sshd_config

##Fin SSH##

##VSFTP##
#======#
#Copia de seguridad
if [ -f /etc/vsftpd.conf_bak ]; then
continue
else
cp /etc/vsftpd.conf /etc/vsftpd.conf_bak
fi

#Habilitamos opción de escritura
perl -pi -e "s/\#write_enable=YES/write_enable=YES/g" /etc/vsftpd.conf

#Cambiamos y habilitamos el mensaje de bienvenida del servidor FTP
perl -pi -e "s/\#ftpd_banner=Welcome to blah FTP service./ftpd_banner=Servidor CinemaScopeHD FTP/g" /etc/vsftpd.conf

##Fin VSFTP##

##SAMBA##
#=======#
#Copia de seguridad
if [ -f /etc/samba/smb.conf_bak ]; then
continue
else
cp /etc/samba/smb.conf /etc/samba/smb.conf_bak
fi
#Cambiar nombre del grupo de trabajo
perl -pi -e "s/workgroup = WORKGROUP/workgroup = CINEMASCOPEHD/g" /etc/samba/smb.conf

#Cambiar la descripcion del servidor
perl -pi -e "s/server string = %h server (Samba, Ubuntu)/server string = %h Samba/g" /etc/samba/smb.conf

#Habilitar el acceso al servidor desde las interfaces de la VPN
perl -pi -e "s/;   interfaces = 127.0.0.0\/8 eth0/interfaces = 127.0.0.0\/8 eth0 10.8.0.0\/24 tun0/g" /etc/samba/smb.conf

#Habilitar el acceso a los usuarios
perl -pi -e "s/#   security = user/security = user/g" /etc/samba/smb.conf

#Habilitar carpetas personales para el Cloud
echo " " >> /etc/samba/smb.conf
echo "[homes]" >> /etc/samba/smb.conf
echo "comment = Directorio Personal" >> /etc/samba/smb.conf
echo "browseable = yes" >> /etc/samba/smb.conf
echo "read only = no" >> /etc/samba/smb.conf
echo "create mask = 0700" >> /etc/samba/smb.conf
echo "directory mask = 0700" >> /etc/samba/smb.conf
echo "valid users = %U" >> /etc/samba/smb.conf
echo " " >> /etc/samba/smb.conf

#Añadimos directivas para mejorar la velocidad en la VPN
sed -i '66i\### Rendimiento ###' /etc/samba/smb.conf
sed -i '67i\use sendfile = yes' /etc/samba/smb.conf
sed -i '68i\strict locking = no' /etc/samba/smb.conf
sed -i '69i\read raw = yes' /etc/samba/smb.conf
sed -i '70i\write raw = yes' /etc/samba/smb.conf
sed -i '71i\oplocks = yes' /etc/samba/smb.conf
sed -i '72i\aio read size = 65535' /etc/samba/smb.conf
sed -i '73i\max xmit = 65535' /etc/samba/smb.conf
sed -i '74i\deadtime = 15' /etc/samba/smb.conf
sed -i '75i\getwd cache = yes' /etc/samba/smb.conf
sed -i '76i\socket options = TCP_NODELAY SO_SNDBUF=65535 SO_RCVBUF=65535' /etc/samba/smb.conf
sed -i '77i\ ' /etc/samba/smb.conf

#Creación de la carpeta compartida para todos los usuarios
echo "[cinemascopehd]" >> /etc/samba/smb.conf
echo "comment=CSHD Streaming" >> /etc/samba/smb.conf
echo "path=/home/CSHD/" >> /etc/samba/smb.conf
echo "public=yes" >> /etc/samba/smb.conf
echo "writable=no" >> /etc/samba/smb.conf
echo "browseable=yes" >> /etc/samba/smb.conf
echo "readonly=yes" >> /etc/samba/smb.conf

##Fin SAMBA##

##OpenVPN##
#=========#
#Borramos cualquier configuracion previa
rm -f -r /etc/openvpn/easy-rsa/
#Configuramos y creamos las claves privadas y publicas del servidor VPN
#Creamos la carpeta donde se almacenaran las claves
mkdir /etc/openvpn/easy-rsa/

#Copiamos  las claves de ejemplo que vienen por defecto a nuestra nueva carpeta
cp -r /usr/share/doc/openvpn/examples/easy-rsa/2.0/* /etc/openvpn/easy-rsa/

#Generamos el Master CA
cd /etc/openvpn/easy-rsa/
ln -s openssl-* openssl.cnf
source vars
./clean-all
./build-ca

#Creamos el certificado del servidor
./build-key-server cshdserver

#Creamos Diffie Hellman para el servidor
./build-dh

#Copiamos los certificados y claves generados a la raiz de openVPN
cd keys/
cp cshdserver.crt cshdserver.key ca.crt dh1024.pem  /etc/openvpn/

#Creamos el certificado del cliente
cd /etc/openvpn/easy-rsa/
source vars
./build-key cshdcliente

#Creamos dos carpetas para almacenar los archivos de configuracion necesarios para ambos sistemas
mkdir -p ~/CSHD/ca/windows
mkdir ~/CSHD/ca/linux

#Copiamos las claves del cliente para generar un pack para ambos sistemas Windows y Linux
cd /etc/openvpn/easy-rsa/keys/
cp ca.crt cshdcliente.crt cshdcliente.key ~/CSHD/ca/windows/
cp ca.crt cshdcliente.crt cshdcliente.key ~/CSHD/ca/linux

#Generamos los archivos de configuracion de la VPN para ambos clientes, Windows y Linux
#Configuracion cliente Windows
touch ~/CSHD/ca/windows/client.ovpn
echo "client" >> ~/CSHD/ca/windows/client.ovpn
echo "remote $ip" >> ~/CSHD/ca/windows/client.ovpn
echo "port $puertovpn" >> ~/CSHD/ca/windows/client.ovpn
echo "proto udp" >> ~/CSHD/ca/windows/client.ovpn
echo "dev tun" >> ~/CSHD/ca/windows/client.ovpn
echo "dev-type tun" >> ~/CSHD/ca/windows/client.ovpn
echo "ns-cert-type server" >> ~/CSHD/ca/windows/client.ovpn
echo "reneg-sec 86400" >> ~/CSHD/ca/windows/client.ovpn
echo "auth-user-pass" >> ~/CSHD/ca/windows/client.ovpn
echo "auth-retry interact" >> ~/CSHD/ca/windows/client.ovpn
echo "comp-lzo yes" >> ~/CSHD/ca/windows/client.ovpn
echo "verb 3" >> ~/CSHD/ca/windows/client.ovpn
echo "ca ca.crt" >> ~/CSHD/ca/windows/client.ovpn
echo "cert cshdcliente.crt" >> ~/CSHD/ca/windows/client.ovpn
echo "key cshdcliente.key" >> ~/CSHD/ca/windows/client.ovpn
echo "management 127.0.0.1 $puertovpn" >> ~/CSHD/ca/windows/client.ovpn
echo "management-hold" >> ~/CSHD/ca/windows/client.ovpn
echo "management-query-passwords" >> ~/CSHD/ca/windows/client.ovpn
echo "auth-retry interact" >> ~/CSHD/ca/windows/client.ovpn

#Generamos el archivos de configuracion de Linux
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/CSHD/ca/linux/
perl -pi -e "s/remote my-server-1 1194/remote $ip $puertovpn/g" ~/CSHD/ca/linux/client.conf
perl -pi -e "s/cert client.cert/cshdcliente.cert/g" ~/CSHD/ca/linux/client.conf
perl -pi -e "s/key client.key/cshdcliente.key/g" ~/CSHD/ca/linux/client.conf

#Elminamos los archivos posibles que ya estén creados
rm ~/CSHD/ca/cliente_win.zip
rm ~/CSHD/ca/cliente_lin.tar.gz

#Creamos un zip de ambas carpetas
cd ~/CSHD/ca/windows
zip ~/CSHD/ca/cliente_win.zip ./*
zip ~/CSHD/ca/cliente_android.zip ./*
cd ~/CSHD/ca/linux
tar -czvf ~/CSHD/ca/cliente_lin.tar.gz ./*

#Movemos los archivos comprimidos a /var/www para que se lo puedan descargar los usuarios desde la web.
mkdir /var/www/ca/

#Damos permisos a www-data en la nueva carpeta
chown www-data:www-data /var/www/ca
chmod 755 /var/www/ca
mv -f ~/CSHD/ca/cliente_win.zip /var/www/ca/
mv -f ~/CSHD/ca/cliente_lin.tar.gz /var/www/ca/
mv -f ~/CSHD/ca/cliente_android.zip /var/www/ca/

#Damos permisos 555 al archivo para su descarga
chmod 555 /var/www/ca/cliente_win.zip
chmod 555 /var/www/ca/cliente_lin.tar.gz

#Configuramos el servidor OpenVPN
#Copiamos los ejemplos de la configuracion
cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn
gzip -d /etc/openvpn/server.conf.gz

#Editamos el archivo de configuracion
perl -pi -e "s/cert server.crt/cert cshdserver.crt/g" /etc/openvpn/server.conf
perl -pi -e "s/key server.key/key cshdserver.key/g" /etc/openvpn/server.conf

#Añadimos la directiva para habilitar el acceso a la VPN mediante contraseña
echo "plugin /usr/lib/openvpn/openvpn-auth-pam.so login" >> /etc/openvpn/server.conf

#Configuracion del servicio de transporte en la tarjeta de red
#Habilitamos la comuniacion entre ambas redes
sysctl -w net.ipv4.ip_forward=1

#Habilitamos el enmascaramiento para la red virtual
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

##Fin OpenVPN##

##QUOTAS##
#========#
#Copia de seguridad de fstab
if [ -f /etc/fstab_bak ]; then
continue
else
cp /etc/fstab /etc/fstab_bak
fi
#Añadimos al fstab las opciones para habilitar las quotas en el directorio /home
awk '$2~"^/home$"{$4="usrquota,grpquota,"$4}1' OFS="\t" /etc/fstab > /etc/fstab_pre
cp /etc/fstab_pre /etc/fstab
rm /etc/fstab_pre
#Remontamos las unidades para efectuar los cambios
mount -o remount /home

#Chequeamos los archivos
quotacheck -avug

#Habilitamos las quotas en el directorio /home
quotaon /home

##Fin QUOTAS##

#Copiamos los archivos de añadir y eliminar usuarios en su ruta
cp ~/CSHD/source/csadduser.sh /etc/cshd/
cp ~/CSHD/source/csdeluser.sh /etc/cshd/

#Asignamos permisos de ejecución
chmod +x /etc/cshd/csadduser.sh
chmod +x /etc/cshd/csdeluser.sh

#Creamos una entrada en bashrc para crear un alias al script
echo "#Inicio Alias Personalizados" >> ~/.bashrc
echo "alias csadduser='sh /etc/cshd/csadduser.sh'" >> ~/.bashrc
echo "alias csdeluser='sh /etc/cshd/csdeluser.sh'" >> ~/.bashrc
echo "#Fin Alias Personalizados" >> ~/.bashrc

#Copiamos los manuales de ambos scripts
cp ~/CSHD/source/csadduser.1 /usr/share/man/man1
cp ~/CSHD/source/csdeluser.1 /usr/share/man/man1

#Cargamos los sources
source /etc/bash.bashrc

#Reiniciamos servicios
service smbd restart
service vsftpd restart
service apache2 restart
service openvpn restart
service mysql restart

##Resultados##
#============#
clear
echo -e "\033[1mToda la configuración puedes visualizarla en /cshd.info\033[0m"
echo " " | tee -a /cshd.info
echo "CSHD Script - 2014 (c) http://github.com/XHAGBARD" | tee -a /cshd.info
echo "#Resultados de la configuración" | tee -a /cshd.info
echo "Información del Sistema" | tee -a /cshd.info
echo "IP: $ip" | tee -a /cshd.info
echo "Nombre Equipo: $nombre" | tee -a /cshd.info
echo "Nombre del dominio: www.cinemascopehd.me" | tee -a /cshd.info
echo " " | tee -a /cshd.info
echo "Comandos Añadir/Eliminar usuarios localmente" | tee -a /cshd.info
echo "csadduser <usuario>" | tee -a /cshd.info
echo "csdeluser <usuario>" | tee -a /cshd.info
echo " Más Información: man csadduser y man csdeluser" | tee -a /cshd.info
echo " " | tee -a /cshd.info
echo "#Web" | tee -a /cshd.info
echo "Dirección web: www.cinemascopehd.me" | tee -a /cshd.info
echo "Administración Web: www.cinemascopehd.me/administrator" | tee -a /cshd.info
echo "Forzar Copia de Seguridad: http://www.cinemascopehd.me/index.php?option=com_akeeba&view=backup&key=copiaseguridad" | tee -a /cshd.info
echo " " | tee -a /cshd.info
echo "#VPN" | tee -a /cshd.info
echo "Red: 10.8.0.0" | tee -a /cshd.info
echo "IP Local Equipo: 10.8.0.1" | tee -a /cshd.info
echo "Configuración Windows: http://www.cinemascopehd.me/ca/cliente_win.zip" | tee -a /cshd.info
echo "Configuración Linux: http://www.cinemascopehd.me/ca/cliente_lin.tar.gz" | tee -a /cshd.info
echo "Configuración Android: http://www.cinemascopehd.me/ca/cliente_android.zip" | tee -a /cshd.info
echo "Conexión VPN: $ip" | tee -a /cshd.info
echo "Puerto: $puertovpn" | tee -a /cshd.info
echo " " | tee -a /cshd.info
echo "#SSH" | tee -a /cshd.info
echo "Conexión: $ip" | tee -a /cshd.info
echo "Puerto: $puertossh" | tee -a /cshd.info
echo " " | tee -a /cshd.info
echo "#SAMBA" | tee -a /cshd.info
echo "Ruta: \\\\10.8.0.1\\cinemascopehd" | tee -a /cshd.info
echo "Cloud Personal: \\\\10.8.0.1\\<usuario>" | tee -a /cshd.info
echo " " | tee -a /cshd.info
echo "#Webmin" | tee -a /cshd.info
echo "Acceso: http://www.cinemascopehd.me:10000" | tee -a /cshd.info
echo " "| tee -a /cshd.info
echo "Datos de Acceso" | tee -a /cshd.info
echo "username: $csid" | tee -a /cshd.info
echo "contraseña: $pass" | tee -a /cshd.info
echo " "
echo "***REINICIANDO SERVICIO SSH***"
echo "Es muy posible que tengas que volver a conectarte al nuevo puerto configurado"
service ssh restart
