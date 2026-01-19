#!/system/bin/sh
# ============================================================================
# MagiskFurtif Post-Filesystem Data Script
# ============================================================================
# This script runs in post-fs-data mode, which executes early in the boot process
# after the data partition is mounted but before the late_start service phase.
#
# Purpose:
# - Perform early boot initialization tasks
# - Set up any required system configurations
# - Prepare environment for the main service script
#
# For MagiskFurtif, this script is intentionally minimal as most functionality
# is handled by the main service.sh script that runs in late_start mode.
#
# IMPORTANT: DO NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module are placed. This ensures your module will still work
# even if Magisk changes its mount point in the future.
# ============================================================================

# Module directory detection
# $MODDIR points to the directory where this module is installed
MODDIR=${0%/*}

# This script will be executed in post-fs-data mode
# Currently no additional setup is required for MagiskFurtif
# Add custom initialization code below if needed in the future
