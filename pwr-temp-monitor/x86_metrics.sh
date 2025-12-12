#!/bin/bash
# x86 Metrics Collector for Prometheus Node Exporter Textfile Collector

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/system_metrics.prom"
TEMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "$OUTPUT_DIR"

HOSTNAME=$(hostname)

# Get CPU temperatures from /sys/class/thermal or /sys/class/hwmon
get_cpu_temp() {
    # Try coretemp first (Intel)
    if [ -d /sys/class/hwmon ]; then
        for hwmon in /sys/class/hwmon/hwmon*; do
            if [ -f "$hwmon/name" ]; then
                name=$(cat "$hwmon/name" 2>/dev/null)
                if [[ "$name" == "coretemp" || "$name" == "k10temp" || "$name" == "zenpower" ]]; then
                    # Find temp inputs
                    for temp in "$hwmon"/temp*_input; do
                        if [ -f "$temp" ]; then
                            val=$(cat "$temp" 2>/dev/null)
                            echo $((val / 1000))
                            return
                        fi
                    done
                fi
            fi
        done
    fi
    
    # Fallback to thermal_zone
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        val=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        echo $((val / 1000))
        return
    fi
    
    echo "0"
}

# Get all thermal zones
get_thermal_zones() {
    local metrics=""
    local zone_num=0
    
    for zone in /sys/class/thermal/thermal_zone*; do
        if [ -d "$zone" ]; then
            temp_file="$zone/temp"
            type_file="$zone/type"
            
            if [ -f "$temp_file" ]; then
                temp_raw=$(cat "$temp_file" 2>/dev/null || echo "0")
                temp=$(echo "scale=1; $temp_raw / 1000" | bc 2>/dev/null || echo "0")
                zone_type=$(cat "$type_file" 2>/dev/null || echo "unknown")
                zone_name=$(basename "$zone")
                
                metrics="${metrics}system_thermal_zone_celsius{host=\"${HOSTNAME}\",zone=\"${zone_name}\",type=\"${zone_type}\"} ${temp}\n"
            fi
        fi
    done
    
    echo -e "$metrics"
}

# Get CPU frequency
get_cpu_freq() {
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        echo $((freq * 1000))  # Convert kHz to Hz
    else
        echo "0"
    fi
}

# Get fan speeds if available
get_fan_speeds() {
    local metrics=""
    
    for hwmon in /sys/class/hwmon/hwmon*; do
        for fan in "$hwmon"/fan*_input; do
            if [ -f "$fan" ]; then
                fan_name=$(basename "$fan" | sed 's/_input//')
                rpm=$(cat "$fan" 2>/dev/null || echo "0")
                metrics="${metrics}system_fan_rpm{host=\"${HOSTNAME}\",fan=\"${fan_name}\"} ${rpm}\n"
            fi
        done
    done
    
    echo -e "$metrics"
}

# Collect metrics
CPU_TEMP=$(get_cpu_temp)
CPU_FREQ=$(get_cpu_freq)
THERMAL_ZONES=$(get_thermal_zones)
FAN_SPEEDS=$(get_fan_speeds)

# Write metrics
cat > "$TEMP_FILE" << EOF
# HELP system_cpu_temperature_celsius CPU temperature in Celsius
# TYPE system_cpu_temperature_celsius gauge
system_cpu_temperature_celsius{host="${HOSTNAME}"} ${CPU_TEMP}

# HELP system_cpu_frequency_hz CPU frequency in Hz
# TYPE system_cpu_frequency_hz gauge
system_cpu_frequency_hz{host="${HOSTNAME}"} ${CPU_FREQ}

# HELP system_thermal_zone_celsius Temperature of thermal zones in Celsius
# TYPE system_thermal_zone_celsius gauge
${THERMAL_ZONES}
# HELP system_fan_rpm Fan speed in RPM
# TYPE system_fan_rpm gauge
${FAN_SPEEDS}
EOF

mv "$TEMP_FILE" "$OUTPUT_FILE"
