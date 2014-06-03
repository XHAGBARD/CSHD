#!/bin/bash
#
#csadduser.sh
#
#Script para añadir usuarios y configurarlos en el servidor automaticamente.
#
#Comprobacion de poderes
if [ "`id -u`" != 0 ] ; then
echo "ERROR: Necesitas tener permisos de root para ejecutar el script."
exit 1
fi

#Extraer variables
mes=$[$(date +%m)+1]

#Creamos el usuario con sus opciones
useradd -d /home/$1 -e $(date +%d/$mes/%Y) -g 1221 -m -s /bin/nologin -p $(mkpasswd --hash=SHA-512 $2) $1
if [ $? -gt 0 ]; then
  echo
  echo "*** ERROR ***"
  echo
  exit 
fi

#Añadimos al usuario en Samba
(echo $2; echo $2) | sudo smbpasswd -s -a -U $1

#Habilitamos las quotas en /home para el Cloud
setquota -u $1 1457280 30000000 0 0 /home

echo "El usuario $1 ha sido creado correctamente."
