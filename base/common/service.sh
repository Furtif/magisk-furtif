#!/system/bin/sh
MODDIR=${0%/*}

# Load configuration file
CONFIG_FILE="/data/local/tmp/furtifconfig.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️ Configuration file not found at $CONFIG_FILE. Exiting..."
    exit 1
fi
. "$CONFIG_FILE"

# Wait for system boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done
sleep "$BOOT_DELAY"

# Function to send or update Discord messages with a timestamp
send_discord_message() {
    if [ "$USEDISCORD" = true ]; then
        # Get the current date and time
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        # Create the message content with the timestamp
        MESSAGE_CONTENT="$1 (Last updated: $TIMESTAMP)"

        if [ -z "$MESSAGE_ID" ]; then
            # Send a new message if MESSAGE_ID is not set
            response=$(curl -s -X POST -H "Content-Type: application/json" \
                -d "{\"content\": \"$MESSAGE_CONTENT\"}" "$DISCORD_WEBHOOK_URL")
            # Extract and save the message ID from the response (assuming the webhook supports it)
            MESSAGE_ID=$(echo "$response" | jq -r '.id')
            echo "Discord message sent. Message ID: $MESSAGE_ID"
        else
            # Update the existing message if MESSAGE_ID is set
            curl -s -X PATCH -H "Content-Type: application/json" \
                -d "{\"content\": \"$MESSAGE_CONTENT\"}" "$DISCORD_WEBHOOK_URL/messages/$MESSAGE_ID" || \
                echo "Failed to update Discord message"
        fi
    fi
}


# Function to check if apps are running
check_device_status() {
    PidPOGO=$(pidof "$POGO_PACKAGE_NAME")
    PidAPK=$(pidof "$APK_PACKAGE_NAME")
    if [ -z "$PidPOGO" ] || [ -z "$PidAPK" ]; then
        return 1
    fi
    return 0
}

# Function to perform a complete login and service start process
login_and_start_service() {
    echo "Performing login and starting service for FurtiF Tools..."
    am start -n "$APK_MAIN_ACTIVITY"
    sleep "$APP_LOAD_DELAY"

    # Login process
    input tap "$LOGIN_TAP_X" "$LOGIN_TAP_Y"
    sleep "$LOGIN_DELAY"

    input swipe "$SWIPE_START_X" "$SWIPE_START_Y" "$SWIPE_END_X" "$SWIPE_END_Y"
    sleep "$SWIPE_DELAY"

    input tap "$AUTHORIZE_TAP_X" "$AUTHORIZE_TAP_Y"
    sleep "$AUTHORIZE_DELAY"

    # Recheck and start service
    input tap "$SERVICE_RECHECK_TAP_X" "$SERVICE_RECHECK_TAP_Y"
    sleep "$SERVICE_CHECK_DELAY"

    input tap "$SERVICE_START_TAP_X" "$SERVICE_START_TAP_Y"
    sleep 10  # Allow Pokémon GO to launch

    # Check if Pokémon GO launched successfully
    retry=0
    while [ -z "$(pidof "$POGO_PACKAGE_NAME")" ] && [ "$retry" -lt "$MAX_RETRIES" ]; do
        echo "Retrying Start Service. Attempt $((retry + 1))..."
        input tap "$SERVICE_START_TAP_X" "$SERVICE_START_TAP_Y"
        sleep "$RETRY_DELAY"
        retry=$((retry + 1))
    done

    if [ -z "$(pidof "$POGO_PACKAGE_NAME")" ]; then
        send_discord_message "🔴 Pokémon GO failed to launch after retries."
    else
        send_discord_message "🟢 Pokémon GO successfully launched."
    fi
}

# Function to perform a double start
double_start_apk_tools() {
    echo "Performing Double Start for FurtiF Tools..."

    # First Launch
    echo "First launch of FurtiF Tools..."
    login_and_start_service

    # Close FurtiF Tools
    echo "Closing FurtiF Tools after first launch..."
    am force-stop "$APK_PACKAGE_NAME"
    sleep 5

    # Second Launch
    echo "Second launch of FurtiF Tools..."
    login_and_start_service
}

# Function to close apps and restart tools during health checks
close_apps_and_restart() {
    echo "Closing apps and restarting FurtiF Tools..."
    am force-stop "$APK_PACKAGE_NAME"
    am force-stop "$POGO_PACKAGE_NAME"
    send_discord_message "🔴 FurtiF™ Tools or Pokémon GO became unresponsive. Restarting..."
    sleep 5
    login_and_start_service
}

# Initial double launch flow to ensure a successful start
double_start_apk_tools

# Main loop for health checks
while true; do
    if ! check_device_status; then
        # Close apps and restart tools if any app is not running
        close_apps_and_restart
    fi
    sleep "$LOOP_INTERVAL"
done
