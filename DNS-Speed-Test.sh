#!/bin/bash

# =================================================================================
#   SCRIPT DE BENCHMARK DE DNS (v3 - Corrección de Falsos Ceros)
#   - Detecta y descarta resultados con latencia 0 como fallos.
# =================================================================================

# --- Configuración de Resolvers ---
# Formato: "IP,Nombre del Proveedor"
# Lista definitiva y ampliada con los servidores más relevantes.
RESOLVERS=(
    # --- Servidores DNS Públicos Globales (Clásicos) ---
    "1.1.1.1,Cloudflare"
    "1.0.0.1,Cloudflare (Secundario)"
    "8.8.8.8,Google"
    "8.8.4.4,Google (Secundario)"
    "9.9.9.9,Quad9 (Seguridad)"
    "149.112.112.112,Quad9 (Secundario)"
    "208.67.222.222,OpenDNS"
    "208.67.220.220,OpenDNS (Secundario)"
    # --- Servidores DNS con Foco en Privacidad/Seguridad ---
    "76.76.2.0,ControlD (Free)"
    "76.76.10.0,ControlD (Free Sec.)"
    "45.90.28.0,NextDNS"
    "45.90.30.0,NextDNS (Secundario)"
    "94.140.14.14,AdGuard DNS"
    "94.140.15.15,AdGuard DNS (Sec.)"
    "185.228.168.9,CleanBrowse (Security)"
    "185.228.169.9,CleanBrowse (Security Sec.)"
    "193.19.108.2,Mullvad"
    "185.222.222.222,DNS.SB (Privacy)"
    # --- Servidores DNS de Metrotel (Etiquetados según uso y registro) ---
    "200.42.0.5,Metrotel (Oficial)"
    "200.42.4.5,Metrotel (Oficial Sec.)"
    "190.12.96.195,Metrotel (vía red Telecom)"
    "190.12.96.251,Metrotel (vía red Telecom)"
    "200.110.216.250,Metrotel (vía red Telecom)"
    "190.111.233.107,Metrotel (vía red Telecom)"
    # --- Servidores DNS de Otros Proveedores Locales ---
    "181.30.128.254,Telecentro"
    "200.63.159.227,iPlan"
)

# --- Variables ---
DOMAIN_FILE="dominios_temp.txt"
LIST_URL="http://s3-us-west-1.amazonaws.com/umbrella-static/top-1m.csv.zip"
ZIP_FILE="top-1m.csv.zip"
CSV_FILE="top-1m.csv"
RESULTS_FILE=$(mktemp)

# --- Función de Limpieza ---
cleanup() {
    echo ""
    echo "🧹 Limpiando archivos temporales..."
    rm -f "$DOMAIN_FILE" "$ZIP_FILE" "$CSV_FILE" "$RESULTS_FILE"
    echo "Listo."
}
trap cleanup EXIT

# --- Comprobaciones Previas ---
echo "⚙️  Verificando herramientas necesarias..."
if ! command -v dnsperf &>/dev/null || ! command -v wget &>/dev/null || ! command -v unzip &>/dev/null || ! command -v bc &>/dev/null; then
    echo "❌ Error: Faltan una o más herramientas (dnsperf, wget, unzip, bc)."
    echo "sudo apt update && sudo apt install -y dnsperf wget unzip bc"
    exit 1
fi
echo "Herramientas OK."
echo ""

# --- Preparación de la Lista de Dominios ---
echo "🌐 Preparando la lista de dominios para el test..."
if [ ! -f "$CSV_FILE" ]; then
    echo "Descargando lista de dominios populares..."
    wget -q --show-progress "$LIST_URL"
    unzip -o -q "$ZIP_FILE"
fi
cat "$CSV_FILE" | cut -d, -f2 | head -n 1000 | awk '{print $1 " A"}' >"$DOMAIN_FILE"
echo "Lista de dominios preparada."
echo ""

# --- Bucle de Pruebas ---
echo "🚀 Iniciando benchmark de DNS para ${#RESOLVERS[@]} servidores (esto puede tardar varios minutos)..."
echo "--------------------------------------------------------------------------------"
for entry in "${RESOLVERS[@]}"; do
    IFS=',' read -r server name <<< "$entry"

    printf "%-40s" "Probando: $name ($server)..."
    output=$(dnsperf -s "$server" -d "$DOMAIN_FILE" -c 100 -l 15 2>&1)
    latency=$(echo "$output" | grep "Average Latency" | awk '{print $4}')
    qps=$(echo "$output" | grep "Queries per second" | awk '{print $4}')

    # --- SECCIÓN CORREGIDA ---
    # Se comprueba si la latencia es un NÚMERO POSITIVO. Si es texto, o cero, se considera un fallo.
    if ! [[ "$latency" =~ ^[0-9]+([.][0-9]+)?$ ]] || [ -z "$qps" ] || (( $(echo "$latency <= 0" | bc -l) )); then
        printf "❌ FALLÓ (Sin respuesta o respuesta inválida)\n"
        latency="9999"
        qps="0"
    else
        echo "✅ Hecho"
    fi
    # --- FIN DE LA SECCIÓN CORREGIDA ---

    echo "$latency;$qps;$server;$name" >>"$RESULTS_FILE"
done

# --- Análisis Inteligente de Resultados ---
echo ""
echo "======================= ANÁLISIS Y RECOMENDACIÓN ======================="

best_latency=$(sort -t ';' -k 1,1n "$RESULTS_FILE" | head -n 1 | cut -d ';' -f 1)
latency_threshold=$(echo "$best_latency * 1.20" | bc -l) # Umbral del 20%
recommended_server_line=$(awk -F';' -v threshold="$latency_threshold" '$1 <= threshold' "$RESULTS_FILE" | sort -t ';' -k 2,2nr | head -n 1)
recommended_server_ip=$(echo "$recommended_server_line" | cut -d ';' -f 3)
recommended_server_name=$(echo "$recommended_server_line" | cut -d ';' -f 4)

echo "Logic: Se busca el servidor con mayor capacidad (QPS) dentro del grupo"
echo "       de servidores con la latencia más competitiva (dentro de un 20%"
echo "       del récord de velocidad de ${best_latency}ms)."
echo ""
if [ -z "$recommended_server_name" ] || [[ "$best_latency" == "9999" ]]; then
    echo "⚠️ No se pudo determinar un servidor recomendado. Revisa la tabla para ver fallos."
else
    echo "🏆 MEJOR OPCIÓN RECOMENDADA: $recommended_server_name ($recommended_server_ip)"
fi
echo ""

# --- Muestra de Resultados Finales Detallados ---
echo "====================================== RESULTADOS FINALES DETALLADOS ======================================"
echo " (Ordenados por Latencia. -> Recomendado, * Grupo de Élite)"
echo "-----------------------------------------------------------------------------------------------------------"
printf "%-5s %-30s %-18s %-22s %-22s %-5s\n" "Rank" "Proveedor" "Servidor DNS" "Latencia Media (ms)" "Consultas/seg (qps)" "Nota"
echo "-----------------------------------------------------------------------------------------------------------"

rank=1
sort -t ';' -k 1,1n -k 2,2nr "$RESULTS_FILE" | while IFS=';' read -r lat qps srv name; do
    nota=""
    if [ "$srv" == "$recommended_server_ip" ] && [[ "$best_latency" != "9999" ]]; then
        nota=" ->"
    elif (( $(echo "$lat <= $latency_threshold" | bc -l) )) && [[ "$lat" != "9999" ]]; then
        nota=" *"
    fi
    printf "%-5s %-30s %-18s %-22s %-22s %-5s\n" "$rank" "$name" "$srv" "$lat" "$qps" "$nota"
    rank=$((rank + 1))
done

echo "==========================================================================================================="
