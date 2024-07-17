#!/bin/bash

# Archivo donde se guardarán las reglas DNAT
CONFIG_FILE="/etc/iptables/rules.v4"


# Función para configurar el sistema como gateway
setup_gateway() {
    echo "Configuración de Gateway en Linux"
    echo "---------------------------------"

    # Mostrar interfaces de red disponibles con sus direcciones IPv4
    echo "Interfaces de red disponibles con direcciones IPv4:"
    interfaces=($(ip -o -4 addr show scope global | awk '{print $2, $4}'))
    for ((i=0; i<${#interfaces[@]}; i+=2)); do
        echo "$((i/2)). ${interfaces[$i]} - ${interfaces[$i+1]}"
    done

    # Pedir al usuario que seleccione la interfaz principal
    read -p "Seleccione la interfaz principal (ingrese el número): " interface_index
    selected_interface=${interfaces[$interface_index]}

    echo "Ha seleccionado la interfaz: $selected_interface"

    # Eliminar todas las configuraciones de iptables relacionadas con NAT (POSTROUTING)
    echo "Eliminando configuraciones existentes de iptables..."
    sudo iptables -t nat -F POSTROUTING
    sudo iptables -t nat -X POSTROUTING

    # Configurar iptables para habilitar MASQUERADE en la interfaz seleccionada
    echo "Configurando iptables para habilitar MASQUERADE en $selected_interface..."
    sudo iptables -t nat -A POSTROUTING -o $selected_interface -j MASQUERADE

    # Mostrar las reglas de iptables nat
    #echo "Reglas de iptables nat actuales:"
    #sudo iptables -t nat -L -n -v

    # Verificar y configurar sysctl.conf para habilitar net.ipv4.ip_forward
    echo "Verificando configuración de sysctl para net.ipv4.ip_forward..."
    if ! grep -q "^net.ipv4.ip_forward\s*=\s*1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
        sudo sysctl -p /etc/sysctl.conf
        echo "Configuración de net.ipv4.ip_forward actualizada en sysctl.conf"
    fi


    # Informar que el gateway ha sido correctamente configurado
    echo "El gateway ha sido correctamente configurado en $selected_interface"
}






# Función para mostrar reglas DNAT en la tabla nat de iptables
show_dnat_rules() {
    echo "Reglas DNAT en iptables:"
    echo "------------------------"
    printf "%-5s %-15s %-15s %-15s\n" "ID" "Puerto Externo" "IP Interna" "Puerto Interno"

    # Obtener las reglas de PREROUTING en la tabla nat
    sudo iptables -t nat -L PREROUTING -n -v --line-numbers | awk '
    BEGIN {
        id = 0
    }
    /DNAT/ {
        id++
        external_port = internal_ip = internal_port = ""
        for (i=1; i<=NF; i++) {
            if ($i ~ /^dpt:/) external_port = substr($i, 5)
            if ($i ~ /^to:/) {
                split(substr($i, 4), arr, ":")
                internal_ip = arr[1]
                internal_port = arr[2]
            }
        }
        printf "%-5d %-15s %-15s %-15s\n", id, external_port, internal_ip, internal_port
    }'
}

# Función para eliminar una regla DNAT por número de línea
delete_dnat_rule() {
    read -p "Ingrese el número de línea de la regla DNAT que desea eliminar: " rule_line

    # Validar que el número de línea ingresado sea un número
    if ! [[ "$rule_line" =~ ^[0-9]+$ ]]; then
        echo "Error: Debe ingresar un número de línea válido."
        return 1
    fi

    # Eliminar la regla DNAT utilizando el número de línea
    sudo iptables -t nat -D PREROUTING "$rule_line"

    echo "Regla DNAT en línea $rule_line eliminada correctamente."
}

# Función para agregar una nueva regla DNAT de entrada
add_dnat_rule() {
    read -p "Ingrese el puerto externo: " external_port
    read -p "Ingrese la IP interna: " internal_ip
    read -p "Ingrese el puerto interno: " internal_port

    # Validar que los puertos sean números y que la IP interna sea válida
    if ! [[ "$external_port" =~ ^[0-9]+$ ]]; then
        echo "Error: Puerto externo inválido."
        return 1
    fi

    if ! [[ "$internal_port" =~ ^[0-9]+$ ]]; then
        echo "Error: Puerto interno inválido."
        return 1
    fi

    if ! [[ "$internal_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Error: IP interna inválida."
        return 1
    fi

    # Agregar la nueva regla DNAT
    sudo iptables -t nat -A PREROUTING -p tcp --dport "$external_port" -j DNAT --to "$internal_ip":"$internal_port"

    echo "Regla DNAT agregada correctamente: $external_port -> $internal_ip:$internal_port"
}


# Función para guardar las reglas DNAT en un archivo
save_config() {
    echo "Guardando configuración en $CONFIG_FILE ..."

    # Verificar si iptables-save está disponible
    if ! command -v iptables-save &> /dev/null; then
        echo "El comando iptables-save no está instalado."
        read -p "¿Desea instalar iptables-save ahora? (y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            sudo apt update
            sudo apt install iptables
        else
            echo "No se ha instalado iptables-save. La configuración no se ha guardado."
            return 1
        fi
    fi

    # Guardar la configuración de iptables en el archivo
    sudo iptables-save > "$CONFIG_FILE"
    echo "Configuración guardada correctamente en $CONFIG_FILE."
}


# Función para mostrar el menú
show_menu() {
    echo ""
    echo ""
    echo "Menú de Gestión de Reglas DNAT"
    echo "Sistema Operativo: Ubuntu 24.04"
    echo "------------------------------"
    echo "c. Configurar Gateway"
    echo "l. Mostrar reglas DNAT"
    echo "n. Agregar nueva regla DNAT"
    echo "d. Eliminar regla DNAT por número de línea"
    echo "s. Guardar la configuracion"
    echo "m. Volver a mostrar el menú"
    echo "q. Salir"
    echo
}

# Mostrar el menú inicial
show_menu

# Bucle principal
while true; do
    echo ""
    echo ""
    read -p "Seleccione una opción: " choice
    case $choice in
        q) exit 0 ;;
        c) setup_gateway ;;
        l) show_dnat_rules ;;
        d) delete_dnat_rule ;;
        n) add_dnat_rule ;;
        s) save_config ;;
        m) show_menu ;;
        *) echo "Opción inválida" ;;
    esac
done
