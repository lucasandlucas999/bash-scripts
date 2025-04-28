#!/bin/bash

# Script para instalar AWX Operator en Ubuntu y configurar múltiples instancias
# Autor: Lucas
# Fecha: 28/04/2025

set -e

# colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} $1 no está instalado. Instalando..."
        return 1
    else
        echo -e "${GREEN}[OK]${NC} $1 ya está instalado"
        return 0
    fi
}

# instalar las dependencias
install_dependencies() {
    print_message "Verificando e instalando dependencias..."
    
    sudo apt update
    
    if ! check_command docker; then
        print_message "Instalando Docker..."
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt update
        sudo apt install -y docker-ce
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
        print_message "Docker instalado correctamente"
    fi
    if ! check_command kubectl; then
        print_message "Instalando kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        print_message "kubectl instalado correctamente"
    fi
    if ! check_command kind; then
        print_message "Instalando kind..."
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        sudo chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
        print_message "kind instalado correctamente"
    fi
    if ! check_command kustomize; then
        print_message "Instalando kustomize..."
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        sudo mv kustomize /usr/local/bin/
        print_message "kustomize instalado correctamente"
    fi
}

# crear y configurar un clúster de kind
create_kind_cluster() {
    local cluster_name=$1
    local container_port=$2
    local host_port=$3
    
    print_message "Creando cluster kind con nombre: $cluster_name (Puerto: $host_port)"
    
    cat > kind-config-$cluster_name.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $cluster_name
networking:
  disableDefaultCNI: false
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: $container_port
        hostPort: $host_port
        protocol: TCP
EOF
    
    kind create cluster --config kind-config-$cluster_name.yaml

    if [ $? -eq 0 ]; then
        print_message "Cluster kind '$cluster_name' creado correctamente"
    else
        echo -e "${RED}[ERROR]${NC} Error al crear el cluster kind '$cluster_name'"
        exit 1
    fi
}

install_awx_operator() {
    local namespace=$1
    local awx_name=$2
    local nodeport=$3
    
    print_message "Instalando AWX Operator en el namespace '$namespace'"
    
    mkdir -p ./awx-$awx_name/paso1
    mkdir -p ./awx-$awx_name/paso2
    
    cat > ./awx-$awx_name/paso1/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Find the latest tag here: https://github.com/ansible/awx-operator/releases
  - github.com/ansible/awx-operator/config/default?ref=2.19.1

# Set the image tags to match the git version from above
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: $namespace
EOF
    
    kubectl create namespace $namespace 2>/dev/null || true
    
    print_message "Aplicando configuración del paso 1..."
    kustomize build ./awx-$awx_name/paso1/ | kubectl apply -f -
    
    print_message "Esperando a que el operador AWX esté listo..."
    kubectl wait deployment/awx-operator-controller-manager --namespace=$namespace --for=condition=Available --timeout=300s
    
    cat > ./awx-$awx_name/paso2/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Find the latest tag here: https://github.com/ansible/awx-operator/releases
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
  - awx.yaml

# Set the image tags to match the git version from above
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: $namespace
EOF

    cat > ./awx-$awx_name/paso2/awx.yaml << EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: $awx_name
spec:
  service_type: nodeport
  nodeport_port: $nodeport
EOF

    print_message "Aplicando configuración del paso 2..."
    kustomize build ./awx-$awx_name/paso2/ | kubectl apply -f -
    
    print_message "Abriendo puerto $nodeport en el firewall..."
    sudo ufw allow $nodeport/tcp
    
    print_message "Instalación de AWX iniciada. Esto puede tardar varios minutos..."
    print_message "Puedes verificar el progreso con: kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager -n $namespace"
    
    print_message "Esperando a que los pods de AWX estén listos (esto puede tardar varios minutos)..."
    while [[ $(kubectl get pods -n $namespace -l "app.kubernetes.io/name=$awx_name" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
        echo -n "."
        sleep 10
    done
    
    # contraseña de administrador
    print_message "Obteniendo contraseña del administrador..."
    local password=$(kubectl get secret $awx_name-admin-password -o jsonpath="{.data.password}" -n $namespace | base64 --decode)
    
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}AWX instalado correctamente${NC}"
    echo -e "${GREEN}Nombre: $awx_name${NC}"
    echo -e "${GREEN}Namespace: $namespace${NC}"
    echo -e "${GREEN}URL de acceso: http://$(hostname -I | awk '{print $1}'):$nodeport${NC}"
    echo -e "${GREEN}Usuario: admin${NC}"
    echo -e "${GREEN}Contraseña: $password${NC}"
    echo -e "${GREEN}==========================================${NC}"
}

main() {
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}   Instalador Automatizado de AWX Operator   ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    
    # comprobar si se ejecuta como root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}[ADVERTENCIA]${NC} Este script requiere permisos de superusuario para algunas operaciones."
        echo -e "${YELLOW}[ADVERTENCIA]${NC} Se te pedirá contraseña sudo cuando sea necesario."
    fi
    echo -e "\n¿Qué acción deseas realizar?"
    echo -e "1) Instalar la primera instancia de AWX"
    echo -e "2) Añadir una nueva instancia de AWX"
    echo -e "3) Salir"
    
    read -p "Selecciona una opción (1-3): " option
    
    case $option in
        1)
            install_dependencies
            read -p "Nombre para el cluster (por defecto: awx-cluster): " cluster_name
            cluster_name=${cluster_name:-awx-cluster}
            
            read -p "Puerto para AWX (por defecto: 30080): " port
            port=${port:-30080}
            
            create_kind_cluster "$cluster_name" 30080 $port
          
            install_awx_operator "awx" "awx" $port
            ;;
            
        2)
            if ! check_command kind; then
                install_dependencies
            fi
            
            read -p "Nombre para el nuevo cluster (ej: awx-cluster2): " cluster_name
            if [ -z "$cluster_name" ]; then
                echo -e "${RED}[ERROR]${NC} Debes proporcionar un nombre para el cluster"
                exit 1
            fi
            
            read -p "Nombre para la instancia AWX (ej: awx2): " awx_name
            if [ -z "$awx_name" ]; then
                echo -e "${RED}[ERROR]${NC} Debes proporcionar un nombre para la instancia AWX"
                exit 1
            fi
            
            read -p "Namespace para la instancia (ej: awx-$awx_name): " namespace
            namespace=${namespace:-awx-$awx_name}
            
            read -p "Puerto para AWX (ej: 30081): " port
            if [ -z "$port" ]; then
                echo -e "${RED}[ERROR]${NC} Debes proporcionar un puerto para AWX"
                exit 1
            fi
            
            create_kind_cluster "$cluster_name" $port $port
            install_awx_operator "$namespace" "$awx_name" $port
            ;;
            
        3)
            echo -e "${GREEN}Saliendo del instalador. ¡Hasta pronto!${NC}"
            exit 0
            ;;
            
        *)
            echo -e "${RED}[ERROR]${NC} Opción no válida"
            exit 1
            ;;
    esac
}


main
