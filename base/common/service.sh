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

# Device identification (AUTO-CONFIGURED)
# Automatically retrieved from FurtiF™ Tools configuration file
# These placeholder values are overwritten during runtime
# - Actual values come from get_device_name() function
# - Reads 'RotomDeviceName' field from FurtiF™ Tools config.json
# - Used for logging, notifications, and API communications
DEVICE_NAME="xxxx"

# Package name (AUTO-CONFIGURED)
# Automatically retrieved from FurtiF™ Tools configuration file
# This placeholder value is overwritten during runtime
# - Actual value comes from get_package_name() function
# - Reads 'PackageName' field from FurtiF™ Tools config.json
# - Used for process monitoring and lifecycle management
PACKAGE_NAME="xxx.xxxxxxx.xxxxx"

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

# Get device name from FurtiF™ Tools configuration file
# Reads the RotomDeviceName field from the main app configuration
# Returns: Device name string for API communications and logging
get_device_name() {
    su -c "cat /data/data/com.github.furtif.furtifformaps/files/config.json" | "$BINDIR"/jq -r ".RotomDeviceName"
}

# Get package name from FurtiF™ Tools configuration file
# Reads the PackageName field from the main app configuration
# Returns: Package name string for process monitoring
get_package_name() {
    su -c "cat /data/data/com.github.furtif.furtifformaps/files/config.json" | "$BINDIR"/jq -r ".PackageName"
}

# Get Rotom mode status from FurtiF™ Tools configuration
# Checks if Rotom integration mode is enabled in the app settings
# Returns: "true" if Rotom mode is enabled, "false" otherwise
get_is_rotom_mode() {
    su -c "cat /data/data/com.github.furtif.furtifformaps/files/config.json" | "$BINDIR"/jq -r ".IsRotomMode"
}

# Get auto-start setting from FurtiF™ Tools configuration
# Checks if automatic app restart is enabled in Rotom settings
# Returns: "true" if auto-start is enabled, "false" otherwise
get_try_auto_start() {
    su -c "cat /data/data/com.github.furtif.furtifformaps/files/config.json" | "$BINDIR"/jq -r ".RotomTryAutoStart"
}

# Check device status via Rotom API
# Queries the Rotom API to retrieve device health information and memory status
# Triggers recovery actions if device is offline or has low memory
# Parameters: None (uses global configuration variables)
# Returns: None (sends notifications and triggers recovery as needed)
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
        # The device name is compared against the second part of the 'origin' field (split by ' • ')
        device_info=$(echo "$response" | "$BINDIR"/jq -r --arg name "$DEVICE_NAME" '.devices[] | select((.origin | split(" • ")[1]) == $name)')
        
        # Get the actual device ID from the device info for worker counting
        device_id=$(echo "$device_info" | "$BINDIR"/jq -r '.deviceId')
        
        # Count active workers for this device from the workers array using the device ID
        # This helps monitor the workload distribution across devices
        worker_count=$(echo "$response" | "$BINDIR"/jq -r --arg device_id "$device_id" '.workers[] | select(.deviceId == $device_id) | .deviceId' | wc -l || echo "0")
        
        # Validate device information - send alert if device not found or response is null
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
        
        # Convert memory from KB to MB for human-readable display
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
        # Low memory threshold: 204800 KB = 200 MB
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
# Sends formatted messages to Discord channel via webhook URL with rich embed formatting
# Parameters: $1 - Message content to send
# Returns: 0 on success, 1 on failure
send_discord_message() {
    # Only send if Discord notifications are enabled
    if [ "$USE_DISCORD" = true ]; then     
        # Escape special characters for JSON compatibility
        # Convert newlines to \n and escape quotes for JSON payload
        message=$(echo "$1" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
        
        # Default message color - purple (10496692)
        selected_color=10496692
        
        # Dynamic color selection based on message content (before JSON processing)
        # This provides visual context for different types of notifications
        if echo "$1" | grep -qiE "recovery|restart|waiting"; then
            # Warning/recovery messages - orange (16776960)
            selected_color=16776960
        elif echo "$1" | grep -qiE "error|offline"; then
            # Error/critical messages - red (16711680)
            selected_color=16711680
        elif echo "$1" | grep -qiE "started|success|ready"; then
            # Success messages - green (5814783)
            selected_color=5814783
        elif echo "$1" | grep -qiE "status|online|alive"; then
            # Status messages - blue (255)
            selected_color=255
        fi
        
        # Create optimized JSON payload with Discord embed formatting
        # Includes timestamp for better message tracking
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
        payload="{\"content\": null, \"embeds\": [{\"title\": \"FurtiF Tools Monitor\", \"description\": \"$message\", \"color\": $selected_color, \"timestamp\": \"$timestamp\"}]}"
        
        # Send webhook request to Discord API
        # Use curl to POST the JSON payload to the webhook URL
        "$BINDIR"/curl -X POST -H "Content-Type: application/json" \
        -d "$payload" "$DISCORD_WEBHOOK_URL" || {
            ui_print "Failed to send Discord message"
            return 1
        }
    fi
    return 0
}

# Check if target applications are running
# Monitors FurtiF™ Tools and associated app process status
# Returns: 0 if both processes are running, 1 if either is missing
check_device_status() {
    # Get process IDs for target applications
    # PACKAGE_NAME: The main app (configured from FurtiF™ Tools settings)
    # com.github.furtif.furtifformaps: The FurtiF™ Tools app itself
    PidAPP=$(pidof "$PACKAGE_NAME")
    PidAPK=$(pidof com.github.furtif.furtifformaps)
    
    # Device is considered offline if either process is not running
    # Both apps must be active for the system to be considered healthy
    if [[ -z "$PidAPP" || -z "$PidAPK" ]]; then
        return 1
    fi
    return 0
}

# Force-close applications and restart FurtiF™ Tools
# Executes recovery procedure when device is detected as offline
# This function ensures clean shutdown and restart of the application stack
# Parameters: None (uses global configuration variables)
# Returns: None (triggers application restart sequence)
close_apps_if_offline_and_start_it() {
    # Force-stop target applications to clear any issues or crashes
    # This ensures a clean state before restarting
    am force-stop com.github.furtif.furtifformaps
    am force-stop "$PACKAGE_NAME"
    
    # Notify about the recovery action via Discord (if enabled)
    message="🔄 **Device Recovery: $DEVICE_NAME**\n\n"
    message="${message}📱 **Action:** Force-stopping applications\n"
    message="${message}⏳ **Status:** Waiting before restart..."
    send_discord_message "$message"
    
    # Wait before restarting to ensure clean shutdown and resource cleanup
    sleep 5
    
    # Restart the FurtiF™ Tools application
    start_apk_tools
}

# Start FurtiF™ Tools application
# Launches the main application and waits for initialization
# This function initiates the app startup sequence and allows time for full initialization
# Parameters: None (uses global configuration variables)
# Returns: None (sends notification and waits for initialization)
start_apk_tools() {
    # Launch FurtiF™ Tools main activity using Android Activity Manager
    # This starts the main application interface
    am start -n com.github.furtif.furtifformaps/com.github.furtif.furtifformaps.MainActivity
    
    # Send confirmation that tools have been started
    message="✅ **Device Started: $DEVICE_NAME**\n\n"
    message="${message}🚀 **Application:** FurtiF™ Tools launched\n"
    message="${message}⏱️ **Wait:** $LOADER_TIME seconds for initialization\n"
    message="${message}✨ **Status:** Ready for operation"
    send_discord_message "$message"
    
    # Wait for application to fully initialize and become operational
    # The LOADER_TIME is configurable based on device performance
    sleep "${LOADER_TIME}"
}

# ============================================================================
# MAIN EXECUTION LOOP
# ============================================================================

# Allow system to stabilize before starting monitoring
# This ensures all system services and dependencies are fully loaded
sleep 15

# Continuous monitoring loop
# This is the main operational loop that runs continuously:
# 1. Refreshes configuration from FurtiF™ Tools settings
# 2. Validates that Rotom mode and auto-start are enabled
# 3. Checks application process status
# 4. Triggers recovery if apps are not running
# 5. Performs Rotom API status checks (if enabled)
# 6. Waits 5 minutes between iterations
while true; do
    # Refresh configuration from FurtiF™ Tools settings
    # This allows for dynamic configuration changes without service restart
    DEVICE_NAME=$(get_device_name)
    PACKAGE_NAME=$(get_package_name)
    IS_ROTOM=$(get_is_rotom_mode)
    AUTO_START=$(get_try_auto_start)
    
    # Skip monitoring if Rotom mode is disabled
    # This allows the service to remain dormant when not needed
    if [ "$IS_ROTOM" = "false" ]; then
        sleep 300
        continue
    fi
    
    # Skip monitoring if auto-start is disabled
    # This provides fine-grained control over the recovery behavior
    if [ "$AUTO_START" = "false" ]; then
        sleep 300
        continue
    fi
    
    # Check if device is offline (missing processes)
    # If either app is not running, execute recovery procedure
    if ! check_device_status; then
        close_apps_if_offline_and_start_it
        sleep 5
        continue
    fi
    
    # Normal operation: wait 5 minutes before next status check
    # This prevents excessive resource usage while maintaining responsiveness
    sleep 300
    
    # Perform Rotom API status check if enabled
    # This provides external health monitoring and alerting
    rotom_device_status
done
