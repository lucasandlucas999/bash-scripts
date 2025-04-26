#!/bin/bash

# Lucas Acuña
# Ult. Modificación: 26/04/2025 13:42 hs

# ¡ MODIFICACIONES PENDIENTES !
# 1. Pedir ip de servidor
# 2. Pedir puerto de servidor
# 3. Pedir puerto de cliente
# 4. Colocar por ssh key
# 5. Hacer que funcione como servicio


# INSTRUCCIONES: 
# El script tiene que ejecutarse como servidor, preferiblemente colocar en la carpeta root y darle permisos de ejecucion con chmod +x {nombre_del_archivo}.sh

# El nombre del cliente es un identificador nada mas <---- ACTUALIZAR Y HACER FUNCIONAL

# El puerto remoto debe colocarse el puerto con el que el se hará el reverse ssh en el servidor, ejemplo: En el servidor principal se ejecuta  ssh -p 2201 root@172.16.0.114
# siendo 2201 el puerto colocado

SERVER_IP="172.16.0.114"   # IP de tu servidor con AWX 
SERVER_SSH_PORT="22"       # Puerto del servidor 

# Pedir información al usuario
echo "=== Configuración del Túnel Reverse SSH ==="
read -p "Nombre identificador del cliente: " CLIENT_NAME
read -p "Puerto remoto en el servidor para este cliente (ej: 2201): " REMOTE_PORT
read -p "Usuario en el servidor AWX (ej: infosv): " SSH_USER
read -s -p "Contraseña del usuario: " SSH_PASSWORD
echo ""

# Para abrir el túnel
COMMAND="ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -N -R ${REMOTE_PORT}:localhost:22 ${SSH_USER}@${SERVER_IP} -p ${SERVER_SSH_PORT}"
echo ""
echo "======================================="
echo "Se va a crear un túnel:"
echo "Cliente: localhost:22 -> Servidor: ${SERVER_IP}:${REMOTE_PORT}"
echo "======================================="

# ssh para tunel
if ! command -v sshpass &> /dev/null; then
    echo "Instalando sshpass..."
    sudo apt update
    sudo apt install -y sshpass
fi

sshpass -p "${SSH_PASSWORD}" ${COMMAND}
