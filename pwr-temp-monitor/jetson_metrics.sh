#!/bin/bash
# Nvidia Jetson Metrics Collector for Prometheus Node Exporter Textfile Collector

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/jetson_metrics.prom"
TEMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "$OUTPUT_DIR"

HOSTNAME=$(hostname)

# Get thermal zone temperatures
get_thermal_zones() {
    local metrics=""
    
    for zone in /sys/devices/virtual/thermal/thermal_zone*; do
        if [ -d "$zone" ]; then
            temp_file="$zone/temp"
            type_file="$zone/type"
            
            if [ -f "$temp_file" ]; then
                temp_raw=$(cat "$temp_file" 2>/dev/null || echo "0")
                temp=$(echo "scale=1; $temp_raw / 1000" | bc 2>/dev/null || echo "0")
                zone_type=$(cat "$type_file" 2>/dev/null || echo "unknown")
                zone_name=$(basename "$zone")
                
                metrics="${metrics}jetson_thermal_zone_celsius{host=\"${HOSTNAME}\",zone=\"${zone_name}\",type=\"${zone_type}\"} ${temp}\n"
            fi
        fi
    done
    
    echo -e "$metrics"
}

# Get GPU temperature (Jetson-specific)
get_gpu_temp() {
    # Try common Jetson thermal zone names
    for zone in /sys/devices/virtual/thermal/thermal_zone*; do
        if [ -f "$zone/type" ]; then
            type=$(cat "$zone/type" 2>/dev/null)
            if [[ "$type" == *"GPU"* || "$type" == *"gpu"* ]]; then
                temp_raw=$(cat "$zone/temp" 2>/dev/null || echo "0")
                echo "scale=1; $temp_raw / 1000" | bc 2>/dev/null || echo "0"
                return
            fi
        fi
    done
    echo "0"
}

# Get CPU temperature
get_cpu_temp() {
    for zone in /sys/devices/virtual/thermal/thermal_zone*; do
        if [ -f "$zone/type" ]; then
            type=$(cat "$zone/type" 2>/dev/null)
            if [[ "$type" == *"CPU"* || "$type" == *"cpu"* || "$type" == "AO-therm" ]]; then
                temp_raw=$(cat "$zone/temp" 2>/dev/null || echo "0")
                echo "scale=1; $temp_raw / 1000" | bc 2>/dev/null || echo "0"
                return
            fi
        fi
    done
    # Fallback to zone0
    if [ -f /sys/devices/virtual/thermal/thermal_zone0/temp ]; then
        temp_raw=$(cat /sys/devices/virtual/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
        echo "scale=1; $temp_raw / 1000" | bc 2>/dev/null || echo "0"
        return
    fi
    echo "0"
}

# Get power consumption from INA sensors (Jetson power rails)
get_power_metrics() {
    local metrics=""
    
    # Check for INA3221 power monitors (common on Jetson)
    for hwmon in /sys/bus/i2c/drivers/ina3221/*/hwmon/hwmon*; do
        if [ -d "$hwmon" ]; then
            for power in "$hwmon"/power*_input; do
                if [ -f "$power" ]; then
                    label_file="${power/_input/_label}"
                    label="unknown"
                    if [ -f "$label_file" ]; then
                        label=$(cat "$label_file" 2>/dev/null | tr ' ' '_')
                    fi
                    # Power is in microwatts, convert to watts
                    power_uw=$(cat "$power" 2>/dev/null || echo "0")
                    power_w=$(echo "scale=3; $power_uw / 1000000" | bc 2>/dev/null || echo "0")
                    metrics="${metrics}jetson_power_watts{host=\"${HOSTNAME}\",rail=\"${label}\"} ${power_w}\n"
                fi
            done
            
            for curr in "$hwmon"/curr*_input; do
                if [ -f "$curr" ]; then
                    label_file="${curr/_input/_label}"
                    label="unknown"
                    if [ -f "$label_file" ]; then
                        label=$(cat "$label_file" 2>/dev/null | tr ' ' '_')
                    fi
                    # Current is in milliamps
                    curr_ma=$(cat "$curr" 2>/dev/null || echo "0")
                    curr_a=$(echo "scale=3; $curr_ma / 1000" | bc 2>/dev/null || echo "0")
                    metrics="${metrics}jetson_current_amps{host=\"${HOSTNAME}\",rail=\"${label}\"} ${curr_a}\n"
                fi
            done
            
            for volt in "$hwmon"/in*_input; do
                if [ -f "$volt" ]; then
                    label_file="${volt/_input/_label}"
                    label="unknown"
                    if [ -f "$label_file" ]; then
                        label=$(cat "$label_file" 2>/dev/null | tr ' ' '_')
                    fi
                    # Voltage is in millivolts
                    volt_mv=$(cat "$volt" 2>/dev/null || echo "0")
                    volt_v=$(echo "scale=3; $volt_mv / 1000" | bc 2>/dev/null || echo "0")
                    metrics="${metrics}jetson_voltage_volts{host=\"${HOSTNAME}\",rail=\"${label}\"} ${volt_v}\n"
                fi
            done
        fi
    done
    
    echo -e "$metrics"
}

# Get CPU/GPU frequencies
get_frequencies() {
    local metrics=""
    
    # CPU frequency
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
        freq_hz=$((freq * 1000))
        metrics="${metrics}jetson_cpu_frequency_hz{host=\"${HOSTNAME}\"} ${freq_hz}\n"
    fi
    
    # GPU frequency (Jetson-specific paths)
    for gpu_freq in /sys/devices/gpu.0/devfreq/*/cur_freq /sys/devices/57000000.gpu/devfreq/*/cur_freq /sys/devices/17000000.gv11b/devfreq/*/cur_freq; do
        if [ -f "$gpu_freq" ]; then
            freq=$(cat "$gpu_freq" 2>/dev/null || echo "0")
            metrics="${metrics}jetson_gpu_frequency_hz{host=\"${HOSTNAME}\"} ${freq}\n"
            break
        fi
    done
    
    echo -e "$metrics"
}

# Get fan speed if available
get_fan_speed() {
    local metrics=""
    
    # Jetson fan control
    for pwm in /sys/devices/pwm-fan/hwmon/hwmon*/pwm1; do
        if [ -f "$pwm" ]; then
            pwm_val=$(cat "$pwm" 2>/dev/null || echo "0")
            # Convert 0-255 to percentage
            pct=$(echo "scale=1; $pwm_val * 100 / 255" | bc 2>/dev/null || echo "0")
            metrics="${metrics}jetson_fan_speed_percent{host=\"${HOSTNAME}\"} ${pct}\n"
        fi
    done
    
    # Also check for RPM reading
    for rpm in /sys/devices/pwm-fan/hwmon/hwmon*/fan1_input; do
        if [ -f "$rpm" ]; then
            rpm_val=$(cat "$rpm" 2>/dev/null || echo "0")
            metrics="${metrics}jetson_fan_rpm{host=\"${HOSTNAME}\"} ${rpm_val}\n"
        fi
    done
    
    echo -e "$metrics"
}

# Collect all metrics
CPU_TEMP=$(get_cpu_temp)
GPU_TEMP=$(get_gpu_temp)
THERMAL_ZONES=$(get_thermal_zones)
POWER_METRICS=$(get_power_metrics)
FREQ_METRICS=$(get_frequencies)
FAN_METRICS=$(get_fan_speed)

# Write metrics
cat > "$TEMP_FILE" << EOF
# HELP jetson_cpu_temperature_celsius Jetson CPU temperature in Celsius
# TYPE jetson_cpu_temperature_celsius gauge
jetson_cpu_temperature_celsius{host="${HOSTNAME}"} ${CPU_TEMP}

# HELP jetson_gpu_temperature_celsius Jetson GPU temperature in Celsius
# TYPE jetson_gpu_temperature_celsius gauge
jetson_gpu_temperature_celsius{host="${HOSTNAME}"} ${GPU_TEMP}

# HELP jetson_thermal_zone_celsius Temperature of thermal zones in Celsius
# TYPE jetson_thermal_zone_celsius gauge
${THERMAL_ZONES}
# HELP jetson_power_watts Power consumption in watts
# TYPE jetson_power_watts gauge
# HELP jetson_current_amps Current draw in amps
# TYPE jetson_current_amps gauge
# HELP jetson_voltage_volts Voltage in volts
# TYPE jetson_voltage_volts gauge
${POWER_METRICS}
# HELP jetson_cpu_frequency_hz CPU frequency in Hz
# TYPE jetson_cpu_frequency_hz gauge
# HELP jetson_gpu_frequency_hz GPU frequency in Hz
# TYPE jetson_gpu_frequency_hz gauge
${FREQ_METRICS}
# HELP jetson_fan_speed_percent Fan speed percentage
# TYPE jetson_fan_speed_percent gauge
# HELP jetson_fan_rpm Fan speed in RPM
# TYPE jetson_fan_rpm gauge
${FAN_METRICS}
EOF

mv "$TEMP_FILE" "$OUTPUT_FILE"
