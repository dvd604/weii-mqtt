#!/bin/bash

set -euo pipefail

# --- CONFIG ---
MQTT_HOST="${MQTT_HOST}"
MQTT_PORT="${MQTT_PORT:-1883}"
MAC_ADDRESS="${MAC_ADDRESS}"

DISCOVERY_PREFIX="homeassistant"
DEVICE_ID="weii_balance_board"

SENSOR_ID="weii_weight"
SENSOR_TOPIC="$DISCOVERY_PREFIX/sensor/$SENSOR_ID"
ATTRIBUTES_TOPIC="$SENSOR_TOPIC/attributes"

SWITCH_ID="weii_auto_publish"
SWITCH_TOPIC="$DISCOVERY_PREFIX/switch/$SWITCH_ID"

AUTO_PUBLISH="ON"
RETRY_DELAY=5

# --- FUNCTIONS ---

publish_discovery() {
  # Weight sensor with attributes
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SENSOR_TOPIC/config" -r -m "{
    \"name\": \"Wii Weight\",
    \"state_topic\": \"$SENSOR_TOPIC/state\",
    \"unique_id\": \"$SENSOR_ID\",
    \"device_class\": \"weight\",
    \"unit_of_measurement\": \"kg\",
    \"availability_topic\": \"$SENSOR_TOPIC/availability\",
    \"json_attributes_topic\": \"$ATTRIBUTES_TOPIC\",
    \"device\": {
      \"identifiers\": [\"$DEVICE_ID\"],
      \"name\": \"Wii Balance Board\",
      \"manufacturer\": \"Nintendo\",
      \"model\": \"Wii Balance Board\"
    }
  }"

  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SENSOR_TOPIC/availability" -m "online"

  # Auto-publish switch
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SWITCH_TOPIC/config" -r -m "{
    \"name\": \"Wii Auto Publish\",
    \"command_topic\": \"$SWITCH_TOPIC/set\",
    \"state_topic\": \"$SWITCH_TOPIC/state\",
    \"unique_id\": \"$SWITCH_ID\",
    \"payload_on\": \"ON\",
    \"payload_off\": \"OFF\",
    \"device\": {
      \"identifiers\": [\"$DEVICE_ID\"],
      \"name\": \"Wii Balance Board\",
      \"manufacturer\": \"Nintendo\",
      \"model\": \"Wii Balance Board\"
    }
  }"

  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SWITCH_TOPIC/state" -m "$AUTO_PUBLISH"
}

# --- MAIN ---

publish_discovery

# Switch listener (background)
mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SWITCH_TOPIC/set" |
while read -r line; do
  case "$line" in
    ON)
      AUTO_PUBLISH="ON"
      echo "$(date '+[%Y-%m-%d %H:%M:%S]') Auto publish enabled."
      mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SWITCH_TOPIC/state" -m "ON"
      ;;
    OFF)
      AUTO_PUBLISH="OFF"
      echo "$(date '+[%Y-%m-%d %H:%M:%S]') Auto publish disabled."
      mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SWITCH_TOPIC/state" -m "OFF"
      ;;
    *)
      echo "$(date '+[%Y-%m-%d %H:%M:%S]') Unknown switch command: $line"
      ;;
  esac
done &

# Main weigh loop with Garmin sync
while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$TIMESTAMP] Starting weii weight measurement..."

  TMP_OUTPUT=$(mktemp)

  # Stream weii output to stdout and temp file
  weii --disconnect-when-done "$MAC_ADDRESS" 2>weii_err.log | tee "$TMP_OUTPUT"
  EXIT_CODE=${PIPESTATUS[0]}

  if [ $EXIT_CODE -ne 0 ]; then
    echo "[$TIMESTAMP] [ERROR] weii exited with code $EXIT_CODE"
    cat weii_err.log
    rm -f weii_err.log "$TMP_OUTPUT"
    sleep $RETRY_DELAY
    continue
  fi

  WEIGHT=$(grep 'Done, weight:' "$TMP_OUTPUT" | sed -E 's/.*Done, weight: ([0-9]+(\.[0-9]+)?).*/\1/')
  rm -f "$TMP_OUTPUT" weii_err.log

  if [ -z "$WEIGHT" ]; then
    echo "[$TIMESTAMP] [WARNING] No valid weight found."
    sleep $RETRY_DELAY
    continue
  fi

  echo "[$TIMESTAMP] Weight read: $WEIGHT kg"

  # Publish to MQTT if auto-publish is ON
  if [ "$AUTO_PUBLISH" == "ON" ]; then
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$SENSOR_TOPIC/state" -m "$WEIGHT"
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$ATTRIBUTES_TOPIC" -m "{
      \"last_weigh_time\": \"$(date --iso-8601=seconds)\"
    }"
    echo "[$TIMESTAMP] Published to MQTT: $SENSOR_TOPIC/state ? $WEIGHT"

    # Garmin sync
    if [ -x "/app/garmin_weight_sync.py" ]; then
      echo "[$TIMESTAMP] Syncing weight to Garmin..."
      python3 /app/garmin_weight_sync.py "$WEIGHT" || \
        echo "[$TIMESTAMP] [ERROR] Garmin sync failed"
    else
      echo "[$TIMESTAMP] Garmin sync script not found or not executable."
    fi
  else
    echo "[$TIMESTAMP] Auto-publish OFF; skipping publish and Garmin sync."
  fi

  sleep $RETRY_DELAY
done
