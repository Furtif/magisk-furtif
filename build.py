#!/usr/bin/env python3
"""
MagiskFurtif Build Script
========================
This script builds the MagiskFurtif module by creating a flashable zip file
with all necessary components and proper module metadata.

Usage:
    python3 build.py [--version VERSION]

Arguments:
    --version VERSION    Specify module version (default: 2.76)

Output:
    builds/MagiskFurtif-{version}.zip
"""

import os
import shutil
import zipfile
import argparse
from pathlib import Path

# ============================================================================
# PATH CONFIGURATION
# ============================================================================

# Base directory of the project - where this build script is located
PATH_BASE = os.path.abspath(os.path.dirname(__file__))
# Source directory for module files - contains the base module structure
PATH_BASE_MODULE = os.path.join(PATH_BASE, "base")
# Output directory for built modules - where the final zip files are stored
PATH_BUILDS = os.path.join(PATH_BASE, "builds")


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def traverse_path_to_list(file_list, path):
    """
    Recursively traverse a directory and add all files to the file list.
    
    This function walks through the directory tree starting from the given path,
    collecting all file paths while skipping placeholder and gitkeep files.
    
    Args:
        file_list (list): List to append file paths to (modified in-place)
        path (str): Directory path to traverse recursively
        
    Returns:
        None: The function modifies the file_list parameter directly
        
    Note:
        Skips files named "placeholder" and ".gitkeep" as these are typically
        used for maintaining directory structure in version control.
    """
    for dp, dn, fn in os.walk(path):
        for f in fn:
            # Skip placeholder and gitkeep files
            if f in ["placeholder", ".gitkeep"]:
                continue
            file_list.append(os.path.join(dp, f))


def create_module_prop(path, release_version):
    """
    Create the module.prop file with module metadata for Magisk.
    
    This file contains essential information that Magisk uses to identify,
    version, and manage the module. It's required for all Magisk modules.
    
    Args:
        path (str): Directory path where to create the module.prop file
        release_version (str): Version string for the module (e.g., "2.76")
        
    Returns:
        None: Creates the file on disk
        
    Note:
        - versionCode is derived from the version string by removing dots
        - minMagisk=1530 ensures compatibility with Magisk v15.3.0+
        - The support URL points to the GitHub issues page
    """
    module_prop = f"""id=magiskfurtif
name=MagiskFurtif
version=v{release_version}
versionCode={release_version.replace('.', '')}
author=Furtif
description=Runs FurtiF Tools on boot with magisk.
support=https://github.com/Furtif/magisk-furtif/issues
minMagisk=1530"""

    prop_path = os.path.join(path, "module.prop")
    with open(prop_path, "w", newline='\n') as f:
        f.write(module_prop)
    print(f"Created module.prop with version {release_version}")


def create_module(release_version):
    """
    Create a complete Magisk module with the specified version.
    
    This function orchestrates the entire module creation process:
    1. Cleans previous build artifacts
    2. Copies the base module structure
    3. Creates module metadata (module.prop)
    4. Builds the flashable zip file with proper structure
    
    Args:
        release_version (str): Version string for the module (e.g., "2.76")
        
    Returns:
        None: Creates the module zip file in the builds/ directory
        
    Raises:
        Exception: If any step of the build process fails
        
    Note:
        The resulting zip file can be flashed directly through Magisk Manager
        or custom recovery. The file structure follows Magisk module standards.
    """
    print(f"Creating MagiskFurtif module version {release_version}...")

    # Setup paths for this build
    module_dir = PATH_BUILDS
    module_zip = os.path.join(PATH_BUILDS, f"MagiskFurtif-{release_version}.zip")

    # Clean up previous builds to ensure fresh start
    if os.path.exists(module_dir):
        shutil.rmtree(module_dir)
        print("Cleaned previous build directory")

    if os.path.exists(module_zip):
        os.remove(module_zip)
        print("Removed previous zip file")

    # Copy base module structure to build directory
    # This creates the foundation for our module
    shutil.copytree(PATH_BASE_MODULE, module_dir)
    print("Copied base module files")

    # Change to module directory for relative path operations
    # This ensures proper zip structure when creating the archive
    original_cwd = os.getcwd()
    os.chdir(module_dir)

    try:
        # Create essential module metadata
        create_module_prop(module_dir, release_version)

        # Build the flashable zip with proper structure
        print("Building flashable zip...")

        # Collect all files to include in the zip
        # Start with essential files at the root level
        file_list = ["install.sh", "module.prop"]

        # Add files from subdirectories to maintain proper structure
        traverse_path_to_list(file_list, "./common")
        traverse_path_to_list(file_list, "./system")
        traverse_path_to_list(file_list, "./META-INF")

        # Create the zip file with compression
        with zipfile.ZipFile(module_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_name in file_list:
                file_path = os.path.join(module_dir, file_name)
                if not os.path.exists(file_path):
                    print(
                        f"Warning: File {file_path} does not exist, skipping...")
                    continue

                # Add file to zip with proper path structure
                # The arcname parameter ensures correct relative paths
                zf.write(file_path, arcname=file_name)
                print(f"Added {file_name} to zip")

        print(f"Successfully created {module_zip}")

    finally:
        # Always restore original working directory, even if an error occurs
        os.chdir(original_cwd)


def parse_arguments():
    """
    Parse command-line arguments for the build script.
    
    This function sets up argument parsing with support for version specification
    and provides helpful usage information including examples.
    
    Returns:
        argparse.Namespace: Parsed command-line arguments
        
    Attributes:
        version (str): Module version to build (default: "2.76")
        
    Note:
        The version should follow semantic versioning (e.g., "2.76", "3.0.0")
        and will be used in both the module.prop file and the output zip filename.
    """
    parser = argparse.ArgumentParser(
        description="Build MagiskFurtif module",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python3 build.py                    # Use default version (2.76)
    python3 build.py --version 2.76    # Build with specific version
    python3 build.py -v 3.0.0          # Short form for version
        """
    )

    parser.add_argument(
        "-v", "--version",
        default="2.76",
        help="Module version (default: 2.76)"
    )

    return parser.parse_args()


def main():
    """
    Main build function that orchestrates the module creation process.
    
    This function serves as the entry point and coordinates:
    1. Command-line argument parsing
    2. Build directory setup
    3. Module creation with error handling
    4. Success/failure reporting
    
    Returns:
        int: Exit code (0 for success, 1 for failure)
        
    Side Effects:
        - Creates builds/ directory if it doesn't exist
        - Generates MagiskFurtif-{version}.zip in builds/
        - Prints build progress and results to stdout
    """
    # Parse command-line arguments to get build configuration
    args = parse_arguments()
    release_version = args.version

    print("=" * 50)
    print("MagiskFurtif Module Builder")
    print("=" * 50)

    # Ensure builds directory exists for output files
    if not os.path.exists(PATH_BUILDS):
        os.makedirs(PATH_BUILDS)
        print(f"Created builds directory: {PATH_BUILDS}")

    # Display build configuration
    print(f"Building MagiskFurtif version {release_version}...")

    try:
        # Execute the module creation process
        create_module(release_version)

        # Report successful completion
        print("\n" + "=" * 50)
        print("Build completed successfully!")
        print(
            f"Module location: {os.path.join(PATH_BUILDS, f'MagiskFurtif-{release_version}.zip')}")
        print("=" * 50)

    except Exception as e:
        # Handle any build errors gracefully
        print(f"\nBuild failed with error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
