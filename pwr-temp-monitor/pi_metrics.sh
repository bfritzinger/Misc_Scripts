#!/bin/bash
# Pi Metrics Collector for Prometheus Node Exporter Textfile Collector
# Place output in /var/lib/node_exporter/textfile_collector/

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/pi_metrics.prom"
TEMP_FILE="${OUTPUT_FILE}.tmp"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Get temperature (in Celsius)
TEMP_RAW=$(vcgencmd measure_temp 2>/dev/null)
TEMP=$(echo "$TEMP_RAW" | grep -oP '\d+\.\d+' || echo "0")

# Get voltage
VOLT_RAW=$(vcgencmd measure_volts 2>/dev/null)
VOLTAGE=$(echo "$VOLT_RAW" | grep -oP '\d+\.\d+' || echo "0")

# Get throttle status (hex value)
THROTTLE_RAW=$(vcgencmd get_throttled 2>/dev/null)
THROTTLE_HEX=$(echo "$THROTTLE_RAW" | grep -oP '0x[0-9a-fA-F]+' || echo "0x0")
THROTTLE_DEC=$((THROTTLE_HEX))

# Parse throttle flags
# Bit 0: Under-voltage detected
# Bit 1: Arm frequency capped
# Bit 2: Currently throttled
# Bit 3: Soft temperature limit active
# Bit 16: Under-voltage has occurred
# Bit 17: Arm frequency capping has occurred
# Bit 18: Throttling has occurred
# Bit 19: Soft temperature limit has occurred

UNDERVOLT_NOW=$(( (THROTTLE_DEC >> 0) & 1 ))
FREQ_CAP_NOW=$(( (THROTTLE_DEC >> 1) & 1 ))
THROTTLED_NOW=$(( (THROTTLE_DEC >> 2) & 1 ))
SOFT_TEMP_NOW=$(( (THROTTLE_DEC >> 3) & 1 ))
UNDERVOLT_OCCURRED=$(( (THROTTLE_DEC >> 16) & 1 ))
FREQ_CAP_OCCURRED=$(( (THROTTLE_DEC >> 17) & 1 ))
THROTTLED_OCCURRED=$(( (THROTTLE_DEC >> 18) & 1 ))
SOFT_TEMP_OCCURRED=$(( (THROTTLE_DEC >> 19) & 1 ))

# Get CPU frequency (in Hz, convert to MHz for readability)
FREQ_RAW=$(vcgencmd measure_clock arm 2>/dev/null)
FREQ_HZ=$(echo "$FREQ_RAW" | grep -oP '\d+$' || echo "0")

# Get hostname for labeling
HOSTNAME=$(hostname)

# Write metrics to temp file (atomic write)
cat > "$TEMP_FILE" << EOF
# HELP rpi_temperature_celsius Raspberry Pi GPU/SoC temperature in Celsius
# TYPE rpi_temperature_celsius gauge
rpi_temperature_celsius{host="${HOSTNAME}"} ${TEMP}

# HELP rpi_voltage_volts Raspberry Pi core voltage
# TYPE rpi_voltage_volts gauge
rpi_voltage_volts{host="${HOSTNAME}"} ${VOLTAGE}

# HELP rpi_clock_hz Raspberry Pi ARM clock frequency in Hz
# TYPE rpi_clock_hz gauge
rpi_clock_hz{host="${HOSTNAME}"} ${FREQ_HZ}

# HELP rpi_throttle_status Raw throttle status value
# TYPE rpi_throttle_status gauge
rpi_throttle_status{host="${HOSTNAME}"} ${THROTTLE_DEC}

# HELP rpi_undervoltage_now Currently experiencing undervoltage (1=yes, 0=no)
# TYPE rpi_undervoltage_now gauge
rpi_undervoltage_now{host="${HOSTNAME}"} ${UNDERVOLT_NOW}

# HELP rpi_freq_capped_now ARM frequency currently capped (1=yes, 0=no)
# TYPE rpi_freq_capped_now gauge
rpi_freq_capped_now{host="${HOSTNAME}"} ${FREQ_CAP_NOW}

# HELP rpi_throttled_now Currently throttled (1=yes, 0=no)
# TYPE rpi_throttled_now gauge
rpi_throttled_now{host="${HOSTNAME}"} ${THROTTLED_NOW}

# HELP rpi_soft_temp_limit_now Soft temperature limit active (1=yes, 0=no)
# TYPE rpi_soft_temp_limit_now gauge
rpi_soft_temp_limit_now{host="${HOSTNAME}"} ${SOFT_TEMP_NOW}

# HELP rpi_undervoltage_occurred Undervoltage has occurred since boot (1=yes, 0=no)
# TYPE rpi_undervoltage_occurred gauge
rpi_undervoltage_occurred{host="${HOSTNAME}"} ${UNDERVOLT_OCCURRED}

# HELP rpi_freq_capped_occurred Frequency capping has occurred since boot (1=yes, 0=no)
# TYPE rpi_freq_capped_occurred gauge
rpi_freq_capped_occurred{host="${HOSTNAME}"} ${FREQ_CAP_OCCURRED}

# HELP rpi_throttled_occurred Throttling has occurred since boot (1=yes, 0=no)
# TYPE rpi_throttled_occurred gauge
rpi_throttled_occurred{host="${HOSTNAME}"} ${THROTTLED_OCCURRED}

# HELP rpi_soft_temp_occurred Soft temp limit has occurred since boot (1=yes, 0=no)
# TYPE rpi_soft_temp_occurred gauge
rpi_soft_temp_occurred{host="${HOSTNAME}"} ${SOFT_TEMP_OCCURRED}
EOF

# Atomic move
mv "$TEMP_FILE" "$OUTPUT_FILE"
