##########################################################################################
#
# MagiskFurtif Module Installer Script
# ============================================================================
# This script handles the installation of the MagiskFurtif module using the
# standard Magisk module installation framework.
#
# The module provides automated management and monitoring of FurtiF™ Tools
# on Android devices with advanced notification and recovery capabilities.
#
##########################################################################################
##########################################################################################
# Installation Instructions
# ============================================================================
# Follow these steps to customize your module:
#
# 1. Place your files into system folder (delete the placeholder file)
# 2. Fill in your module's info into module.prop (handled automatically by build.py)
# 3. Configure and implement callbacks in this file
# 4. If you need boot scripts, add them into common/post-fs-data.sh or common/service.sh
# 5. Add your additional or modified system properties into common/system.prop
#
# For MagiskFurtif:
# - The main functionality is implemented in service.sh (late_start service)
# - Configuration is handled dynamically through the FurtiF™ Tools app
# - No system modifications are required (SKIPMOUNT=false, PROPFILE=false)
##########################################################################################

##########################################################################################
# MagiskFurtif Configuration Flags
# ============================================================================
# These flags control how Magisk handles the module installation and operation.
#
# For MagiskFurtif, we use minimal system integration as the module primarily
# runs as a service that monitors and manages external applications.

# SKIPMOUNT: Set to true if you do *NOT* want Magisk to mount any files for you.
# Most modules would NOT want to set this flag to true.
# MagiskFurtif: Set to false as we don't need custom system file mounting
SKIPMOUNT=false

# PROPFILE: Set to true if you need to load system.prop
# MagiskFurtif: Set to false as we don't modify system properties
PROPFILE=false

# POSTFSDATA: Set to true if you need post-fs-data script
# MagiskFurtif: Set to false as we use late_start service for main functionality
POSTFSDATA=false

# LATESTARTSERVICE: Set to true if you need late_start service script
# MagiskFurtif: Set to true as this is where our main monitoring logic runs
LATESTARTSERVICE=true

##########################################################################################
# System Directory Replace List
# ============================================================================
# List all directories you want to directly replace in the system.
# Check the Magisk documentation for more info why you would need this.
#
# Construct your list in the following format:
# REPLACE_EXAMPLE="
# /system/app/Youtube
# /system/priv-app/SystemUI
# /system/priv-app/Settings
# /system/framework
# "
#
# MagiskFurtif: No system replacements needed - we only monitor external apps
# MagiskFurtif: No system directory replacements required
REPLACE="
"

##########################################################################################
# Magisk Module Function Callbacks
# ============================================================================
# The following functions will be called by the installation framework.
# You do not have the ability to modify update-binary; the only way you can customize
# installation is through implementing these functions.
#
# When running your callbacks, the installation framework will make sure the Magisk
# internal busybox path is *PREPENDED* to PATH, so all common commands shall exist.
# Also, it will make sure /data, /system, and /vendor is properly mounted.
##########################################################################################
##########################################################################################
# Magisk Installation Framework Variables and Functions
# ============================================================================
# The installation framework exports some variables and functions.
# You should use these variables and functions for installation.
#
# ⚠️ IMPORTANT SECURITY NOTES:
# ! DO NOT use any Magisk internal paths as those are NOT public API.
# ! DO NOT use other functions in util_functions.sh as they are NOT public API.
# ! Non public APIs are not guaranteed to maintain compatibility between releases.
########################################################################################## Available Installation Framework Variables
# ============================================================================
#
# MAGISK_VER (string): the version string of current installed Magisk
# MAGISK_VER_CODE (int): the version code of current installed Magisk
# BOOTMODE (bool): true if the module is currently installing in Magisk Manager
# MODPATH (path): the path where your module files should be installed
# TMPDIR (path): a place where you can temporarily store files
# ZIPFILE (path): your module's installation zip
# ARCH (string): the architecture of the device. Value is either arm, arm64, x86, or x64
# IS64BIT (bool): true if $ARCH is either arm64 or x64
# API (int): the API level (Android version) of the device
#
# ============================================================================
# Available Installation Framework Functions
# ============================================================================
#
# ui_print <msg>
#     print <msg> to console
#     Avoid using 'echo' as it will not display in custom recovery's console
#
# abort <msg>
#     print error message <msg> to console and terminate installation
#     Avoid using 'exit' as it will skip the termination cleanup steps
#
# set_perm <target> <owner> <group> <permission> [context]
#     if [context] is empty, it will default to "u:object_r:system_file:s0"
#     this function is a shorthand for the following commands
#       chown owner.group target
#       chmod permission target
#       chcon context target
#
# set_perm_recursive <directory> <owner> <group> <dirpermission> <filepermission> [context]
#     if [context] is empty, it will default to "u:object_r:system_file:s0"
#     for all files in <directory>, it will call:
#       set_perm file owner group filepermission context
#     for all directories in <directory> (including itself), it will call:
#       set_perm dir owner group dirpermission context
##########################################################################################
##########################################################################################
# Boot Script Guidelines for Magisk Modules
# ============================================================================
# If you need boot scripts, DO NOT use general boot scripts (post-fs-data.d/service.d)
# ONLY use module scripts as it respects the module status (remove/disable) and is
# guaranteed to maintain the same behavior in future Magisk releases.
#
# Enable boot scripts by setting the flags in the config section above.
#
# For MagiskFurtif:
# - We use LATESTARTSERVICE=true for our main monitoring service
# - The service.sh script contains all the monitoring and recovery logic
# - POSTFSDATA=false as we don't need early boot initialization
##########################################################################################

# ============================================================================
# Module Installation Display
# ============================================================================
# This function controls what is displayed during module installation in Magisk Manager
# or custom recovery. It provides a professional installation experience.
print_modname() {
  ui_print " "
  ui_print "    ********************************************"
  ui_print "    *         MagiskFurtif by Furtif           *"
  ui_print "    ********************************************"
  ui_print " "
  ui_print "    Automated FurtiF™ Tools Management"
  ui_print "    Version: (auto-generated by build.py)"
  ui_print " "
}

# ============================================================================
# Module Installation Process
# ============================================================================
# This function handles the actual file extraction and installation.
# For MagiskFurtif, we extract the system directory which contains our scripts.
#
# The default implementation extracts $ZIPFILE/system to $MODPATH
# This is sufficient for MagiskFurtif as we don't need custom installation logic.
on_install() {
  ui_print "- Extracting MagiskFurtif module files..."
  
  # Extract the system directory from the zip file to the module path
  # The system directory contains our service scripts and configuration
  unzip -o "$ZIPFILE" 'system/*' -d $MODPATH >&2
  
  ui_print "- Module files extracted successfully"
  ui_print "- Service script will start on next boot"
}

# ============================================================================
# File Permissions Setup
# ============================================================================
# This function sets the appropriate permissions for all module files.
# This is called after on_install is complete.
#
# For MagiskFurtif, the default permissions are sufficient:
# - Directories: 0755 (rwxr-xr-x) - owner full access, others read/execute
# - Files: 0644 (rw-r--r--) - owner read/write, others read-only
set_permissions() {
  # Default Magisk module permissions
  # This ensures proper access while maintaining security
  set_perm_recursive $MODPATH 0 0 0755 0644
  
  # Note: Service scripts will be automatically made executable by Magisk
  # No additional permissions are required for MagiskFurtif
}

# ============================================================================
# Additional Helper Functions
# ============================================================================
# You can add more functions to assist your custom script code.
# For MagiskFurtif, no additional helper functions are currently needed.
# All functionality is implemented in the service.sh script.
##########################################################################################
