#!/system/bin/sh
# ============================================================================
# MagiskFurtif Service Script
# ============================================================================
# This script runs as a Magisk late_start service and manages the FurtiF™ Tools
# application monitoring and automation system.
#
# Features:
# - Automatic app monitoring and restart functionality
# - Discord webhook notifications for status updates
# - Rotom API integration for device health monitoring
# - Configurable device-specific settings
#
# IMPORTANT: DO NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module are placed. This ensures your module will still work
# even if Magisk changes its mount point in the future.
# ============================================================================

# Module directory detection
MODDIR=${0%/*}

# ============================================================================
# CONFIGURATION SECTION
# ============================================================================

# Path to Termux binary directory
# This path varies depending on Android version and device type:
# - Android 14+: /data/data/com.termux/files/usr/bin
# - ATV devices (e.g., H96): /system/xbin
# - Other devices: /vendor/bin or /system/bin
# - Play Store Termux: /data/data/com.termux/files/usr/bin
BINDIR="/data/data/com.termux/files/usr/bin"

# Wait for application to fully load and initialize
# Adjust this duration based on your device performance
LOADER_TIME=40

# Device identification
# Used for logging, notifications, and API communications
DEVICE_NAME="Pixel5"

# Set the package name of the application to monitor
PACKAGE_NAME="xxx.xxxxxxx.xxxxx"

# Discord webhook configuration
# Replace "YOUR_WEBHOOK_URL_HERE" with your actual Discord webhook URL
# to send status messages and alerts to your Discord channel
DISCORD_WEBHOOK_URL="YOUR_WEBHOOK_URL_HERE"

# Discord notification toggle
# Set to 'true' to enable Discord notifications, 'false' to disable
USE_DISCORD=false

# Rotom API configuration
# Replace "YOUR_ROTOM_URL_HERE" with your Rotom API endpoint
# Used for checking device status and health metrics
ROTOMAPI_URL="YOUR_ROTOM_URL_HERE/api/status"

# Rotom API toggle
# Set to 'true' to enable Rotom API status checks, 'false' to disable
USE_ROTOM=false

# Rotom API authentication credentials
# Only required if your Rotom API uses authentication
# Set ROTOMAPI_USE_AUTH to 'true' if authentication is required
ROTOMAPI_USER="USER"
ROTOMAPI_PASSWORD="PASSWORD"
ROTOMAPI_USE_AUTH=false

# ============================================================================
# BOOT SEQUENCE INITIALIZATION
# ============================================================================
# This script runs in late_start service mode, ensuring execution after
# most system services have started.

# Wait for system boot completion by monitoring sys.boot_completed property
# The property will be "1" once the boot process is fully completed
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# Additional delay to ensure system stability after boot completion
sleep 5

# ============================================================================
# OPTIONAL SYSTEM CONFIGURATIONS
# ============================================================================

# OpenGLES version configuration
# Uncomment and modify as needed for your device:
# 196608 = 0x30000 (OpenGL ES 3.0)
# 196609 = 0x30001 (OpenGL ES 3.1)
# 196610 = 0x30002 (OpenGL ES 3.2)
# resetprop ro.opengles.version=196608

# Screen unlock automation (if needed)
# Reference: https://stackoverflow.com/questions/29072501/how-to-unlock-android-phone-through-adb
# Uncomment and modify as needed:
# input keyevent 26                    # Press lock button
# input touchscreen swipe 930 880 930 380  # Swipe up to unlock
# input swipe 930 880 930 380           # Alternative swipe command
# input text 1234                       # Enter passcode (replace with yours)
# input keyevent 66                    # Press Enter

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

# Check device status via Rotom API
# Queries the Rotom API to retrieve device health information and memory status
rotom_device_status() {
    # Only execute if Rotom API integration is enabled
    if [ "$USE_ROTOM" = true ]; then
        # Fetch API response with or without authentication based on configuration
        if [ "$ROTOMAPI_USE_AUTH" = true ]; then
            response=$("$BINDIR"/curl -s -u "$ROTOMAPI_USER:$ROTOMAPI_PASSWORD" "$ROTOMAPI_URL")
        else
            response=$("$BINDIR"/curl -s "$ROTOMAPI_URL")
        fi
        # Extract device information matching our device name from API response
        device_info=$(echo "$response" | "$BINDIR"/jq -r --arg name "$DEVICE_NAME" '.devices[] | select((.origin | split(" • ")[1]) == $name)')
        # Get the actual device ID from the device info
        device_id=$(echo "$device_info" | "$BINDIR"/jq -r '.deviceId')
        # Count workers for this device from the workers array using the actual device ID
        worker_count=$(echo "$response" | "$BINDIR"/jq -r --arg device_id "$device_id" '.workers[] | select(.deviceId == $device_id) | .deviceId' | wc -l || echo "0")
        # Validate device information - send alert if not found or null
        if [ -z "$device_info" ] || [ "$device_info" == "null" ]; then
            message="❌ **API Error: $DEVICE_NAME**\n\n"
            message="${message}🔍 **Issue:** Device not found in Rotom API\n"
            message="${message}🔧 **Action:** Restarting applications..."
            send_discord_message "$message"
            # Optional: Uncomment below for automatic reboot on critical failure
            # reboot
            close_apps_if_offline_and_start_it
            sleep 5
            return
        fi
        # Extract device status and memory information from API response
        is_alive=$(echo "$device_info" | "$BINDIR"/jq -r '.isAlive')
        mem_free_kb=$(echo "$device_info" | "$BINDIR"/jq -r '.lastMemory.memFree')
        # Convert memory from KB to MB
        mem_free_mb=$((mem_free_kb / 1024))
        # Send status update if device is online and healthy
        if [ "$is_alive" = "true" ]; then
            message="📱 **Device Status: $DEVICE_NAME**\n\n"
            message="${message}🟢 **IsAlive:** $is_alive\n"
            message="${message}💾 **Free Memory:** ${mem_free_mb} MB\n"
            message="${message}👥 **Workers:** $worker_count"
            send_discord_message "$message"
        fi
        
        # Handle device offline status or low memory conditions (< 200MB)
        if [ "$is_alive" = "false" ] || [ "$mem_free_kb" -lt 204800 ]; then
            message="🚨 **Device Alert: $DEVICE_NAME**\n\n"
            if [ "$is_alive" = "false" ]; then
                message="${message}🔴 **Status:** Offline\n"
            fi
            if [ "$mem_free_kb" -lt 204800 ]; then
                message="${message}💾 **Memory:** Low (${mem_free_mb} MB)\n"
            fi
            message="${message}🔧 **Action:** Restarting applications..."
            send_discord_message "$message"
            # Optional: Uncomment below for automatic reboot on critical issues
            # reboot
            close_apps_if_offline_and_start_it
            sleep 5
        fi
    fi
}

# Send Discord webhook notification
# Sends formatted messages to Discord channel via webhook URL
send_discord_message() {
    # Only send if Discord notifications are enabled
    if [ "$USE_DISCORD" = true ]; then
        # Dynamic color selection based on message content (before JSON processing)
        if echo "$1" | grep -q "❌\|🚨\|🔴\|Error\|error\|Offline\|offline"; then
            # Error/critical messages - red
            selected_color=16711680
            elif echo "$1" | grep -q "✅\|🚀\|Started\|✨"; then
            # Success messages - green
            selected_color=5814783
            elif echo "$1" | grep -q "🔄\|⏳\|Recovery\|🔧"; then
            # Warning/recovery messages - orange
            selected_color=16776960
            elif echo "$1" | grep -q "📱\|🟢\|Status"; then
            # Status messages - blue
            selected_color=255
        else
            # Default messages - purple
            selected_color=10496692
        fi
        # Escape special characters for JSON compatibility
        message=$(echo "$1" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
        # Create optimized JSON payload with Discord embed formatting
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
        payload="{\"content\": null, \"embeds\": [{\"title\": \"FurtiF Tools Monitor\", \"description\": \"$message\", \"color\": $selected_color, \"timestamp\": \"$timestamp\"}]}"
        # Send webhook request to Discord
        "$BINDIR"/curl -X POST -H "Content-Type: application/json" \
        -d "$payload" "$DISCORD_WEBHOOK_URL" || {
            ui_print "Failed to send Discord message"
            return 1
        }
    fi
    return 0
}

# Check if target applications are running
# Monitors FurtiF™ Tools process status
check_device_status() {
    # Get process IDs for target applications
    PidAPP=$(pidof "$PACKAGE_NAME")
    PidAPK=$(pidof com.github.furtif.furtifformaps)
    # Device is considered offline if either process is not running
    if [[ -z "$PidAPP" || -z "$PidAPK" ]]; then
        return 1
    fi
    return 0
}

# Force-close applications and restart FurtiF™ Tools
# Executes recovery procedure when device is detected as offline
close_apps_if_offline_and_start_it() {
    # Force-stop target applications to clear any issues
    am force-stop com.github.furtif.furtifformaps
    am force-stop "$PACKAGE_NAME"
    # Notify about the recovery action
    message="🔄 **Device Recovery: $DEVICE_NAME**\n\n"
    message="${message}📱 **Action:** Force-stopping applications\n"
    message="${message}⏳ **Status:** Waiting before restart..."
    send_discord_message "$message"
    # Wait before restarting to ensure clean shutdown
    sleep 5
    # Restart the FurtiF™ Tools application
    start_apk_tools
}

# Start FurtiF™ Tools application
# Launches the main application and waits for initialization
start_apk_tools() {
    # Launch FurtiF™ Tools main activity
    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    # Send confirmation that tools have been started
    message="✅ **Device Started: $DEVICE_NAME**\n\n"
    message="${message}🚀 **Application:** FurtiF™ Tools launched\n"
    message="${message}⏱️ **Wait:** $LOADER_TIME seconds for initialization\n"
    message="${message}✨ **Status:** Ready for operation"
    send_discord_message "$message"
    sleep "${LOADER_TIME}"
}

# ============================================================================
# MAIN EXECUTION LOOP
# ============================================================================

# Allow system to stabilize before starting monitoring
sleep 15

# Continuous monitoring loop
# Checks device status every 5 minutes and performs recovery actions as needed
while true; do
    # If device is offline (missing processes), execute recovery procedure
    if ! check_device_status; then
        close_apps_if_offline_and_start_it
        sleep 5
        continue
    fi
    # Normal operation: wait 5 minutes before next status check
    sleep 300
    # Perform Rotom API status check if enabled
    rotom_device_status
done
