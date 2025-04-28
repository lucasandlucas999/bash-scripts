#!/bin/bash

# Lucas Acuña
# Última Modificación: 28/04/2025 10:14 hs

# INSTRUCCIONES:
# El script tiene que ejecutarse como servidor, preferiblemente colocar en la carpeta root y darle permisos de ejecución con chmod +x {nombre_del_archivo}.sh
# El nombre del cliente es un identificador nada más <---- ACTUALIZAR Y HACER FUNCIONAL
# El puerto remoto debe colocarse el puerto con el que se hará el reverse ssh en el servidor, ejemplo: En el servidor principal se ejecuta ssh -p 2201 root@172.16.0.114

export LANG=es_ES.cp850
if ! command -v dialog &> /dev/null; then
    echo "El programa 'dialog' no está instalado. Instalando..."
    sudo dnf update
    sudo dnf install -y dialog
fi
SERVER_IP="172.16.0.114"   # IP del servidor con AWX 
SERVER_SSH_PORT="22"       # Puerto del servidor 

CLIENT_NAME=$(dialog --inputbox "Nombre identificador del cliente:" 8 40 3>&1 1>&2 2>&3)
REMOTE_PORT=$(dialog --inputbox "Puerto remoto en el servidor para este cliente (ej: 2201):" 8 40 3>&1 1>&2 2>&3)
SSH_USER=$(dialog --inputbox "Usuario en el servidor AWX (ej: infosv):" 8 40 3>&1 1>&2 2>&3)
SSH_PASSWORD=$(dialog --passwordbox "Contraseña del usuario:" 8 40 3>&1 1>&2 2>&3)

# verificar si los campos estan vacios o el usuario cancelo
if [[ -z "$CLIENT_NAME" || -z "$REMOTE_PORT" || -z "$SSH_USER" || -z "$SSH_PASSWORD" ]]; then
    dialog --msgbox "Información incompleta. El script se cerrará." 6 40
    exit 1
fi

COMMAND="ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -N -R ${REMOTE_PORT}:localhost:22 ${SSH_USER}@${SERVER_IP} -p ${SERVER_SSH_PORT}"
dialog --msgbox "Se va a crear un túnel SSH con los siguientes detalles:\n\nCliente: localhost:22 -> Servidor: ${SERVER_IP}:${REMOTE_PORT}\n\nPresiona OK para continuar." 10 50

if ! command -v sshpass &> /dev/null; then
    dialog --msgbox "Instalando sshpass..." 6 30
    sudo dnf update
    sudo dnf install -y sshpass
fi

# generar el servicio 
SERVICE_FILE="/etc/systemd/system/reverse-ssh-${CLIENT_NAME}.service"

cat <<EOF | sudo tee $SERVICE_FILE > /dev/null
[Unit]
Description=Tunel para ${CLIENT_NAME}
After=network.target

[Service]
ExecStart=/usr/bin/sshpass -p "${SSH_PASSWORD}" ${COMMAND}
Restart=always
User=root
WorkingDirectory=/root
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=reverse-ssh-${CLIENT_NAME}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable reverse-ssh-${CLIENT_NAME}.service
sudo systemctl start reverse-ssh-${CLIENT_NAME}.service
dialog --msgbox "El túnel SSH se ha establecido como servicio.\n\nPara detenerlo, usa: sudo systemctl stop reverse-ssh-${CLIENT_NAME}.service" 6 50
clear
