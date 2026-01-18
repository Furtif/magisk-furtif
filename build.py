#!/usr/bin/env python3
"""
MagiskFurtif Build Script
========================
This script builds the MagiskFurtif module by creating a flashable zip file
with all necessary components and proper module metadata.

Usage:
    python3 build.py [--version VERSION]

Arguments:
    --version VERSION    Specify module version (default: 2.75)

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

# Base directory of the project
PATH_BASE = os.path.abspath(os.path.dirname(__file__))
# Source directory for module files
PATH_BASE_MODULE = os.path.join(PATH_BASE, "base")
# Output directory for built modules
PATH_BUILDS = os.path.join(PATH_BASE, "builds")


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def traverse_path_to_list(file_list, path):
    """
    Recursively traverse a directory and add all files to the file list.

    Args:
        file_list (list): List to append file paths to
        path (str): Directory path to traverse
    """
    for dp, dn, fn in os.walk(path):
        for f in fn:
            # Skip placeholder and gitkeep files
            if f in ["placeholder", ".gitkeep"]:
                continue
            file_list.append(os.path.join(dp, f))


def create_module_prop(path, frida_release):
    """
    Create the module.prop file with module metadata.

    Args:
        path (str): Directory path where to create the file
        frida_release (str): Version string for the module
    """
    module_prop = f"""id=magiskfurtif
name=MagiskFurtif
version=v{frida_release}
versionCode={frida_release.replace('.', '')}
author=Furtif
description=Runs FurtiF Tools on boot with magisk.
support=https://github.com/Furtif/magisk-furtif/issues
minMagisk=1530"""

    prop_path = os.path.join(path, "module.prop")
    with open(prop_path, "w", newline='\n') as f:
        f.write(module_prop)
    print(f"Created module.prop with version {frida_release}")


def create_module(frida_release):
    """
    Create a complete Magisk module with the specified version.

    Args:
        frida_release (str): Version string for the module
    """
    print(f"Creating MagiskFurtif module version {frida_release}...")

    # Setup paths
    module_dir = PATH_BUILDS
    module_zip = os.path.join(PATH_BUILDS, f"MagiskFurtif-{frida_release}.zip")

    # Clean up previous builds
    if os.path.exists(module_dir):
        shutil.rmtree(module_dir)
        print("Cleaned previous build directory")

    if os.path.exists(module_zip):
        os.remove(module_zip)
        print("Removed previous zip file")

    # Copy base module structure
    shutil.copytree(PATH_BASE_MODULE, module_dir)
    print("Copied base module files")

    # Change to module directory for relative path operations
    original_cwd = os.getcwd()
    os.chdir(module_dir)

    try:
        # Create module metadata
        create_module_prop(module_dir, frida_release)

        # Build the flashable zip
        print("Building flashable zip...")

        # Collect all files to include in the zip
        file_list = ["install.sh", "module.prop"]

        # Add files from subdirectories
        traverse_path_to_list(file_list, "./common")
        traverse_path_to_list(file_list, "./system")
        traverse_path_to_list(file_list, "./META-INF")

        # Create the zip file
        with zipfile.ZipFile(module_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_name in file_list:
                file_path = os.path.join(module_dir, file_name)
                if not os.path.exists(file_path):
                    print(
                        f"Warning: File {file_path} does not exist, skipping...")
                    continue

                # Add file to zip with proper path structure
                zf.write(file_path, arcname=file_name)
                print(f"Added {file_name} to zip")

        print(f"Successfully created {module_zip}")

    finally:
        # Restore original working directory
        os.chdir(original_cwd)


def parse_arguments():
    """
    Parse command-line arguments for the build script.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Build MagiskFurtif module",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python3 build.py                    # Use default version (2.75)
    python3 build.py --version 2.76    # Build with specific version
    python3 build.py -v 3.0.0          # Short form for version
        """
    )

    parser.add_argument(
        "-v", "--version",
        default="2.75",
        help="Module version (default: 2.75)"
    )

    return parser.parse_args()


def main():
    """
    Main build function that orchestrates the module creation process.
    """
    # Parse command-line arguments
    args = parse_arguments()
    frida_release = args.version

    print("=" * 50)
    print("MagiskFurtif Module Builder")
    print("=" * 50)

    # Ensure builds directory exists
    if not os.path.exists(PATH_BUILDS):
        os.makedirs(PATH_BUILDS)
        print(f"Created builds directory: {PATH_BUILDS}")

    # Module version configuration
    print(f"Building MagiskFurtif version {frida_release}...")

    try:
        # Create the module
        create_module(frida_release)

        print("\n" + "=" * 50)
        print("Build completed successfully!")
        print(
            f"Module location: {os.path.join(PATH_BUILDS, f'MagiskFurtif-{frida_release}.zip')}")
        print("=" * 50)

    except Exception as e:
        print(f"\nBuild failed with error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
