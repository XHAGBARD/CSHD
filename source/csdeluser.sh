#!/bin/bash
#
#csdeluser.sh
#
#Script para eliminar usuarios y sus configuraciones
#
#Comprobacion de poderes root
if [ "`id -u`" != 0 ] ; then
echo "ERROR: Necesitas tener permisos de root para ejecutar el script."
exit 1
fi
#Eliminamos al usuario
userdel -r $1
echo "El usuario $1 ha sido eliminado correctamente."
#Eliminamos la cuenta del usuario en Samba
smbpasswd -x $1
