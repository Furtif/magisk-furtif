#!/user/bin/env python3
import os
import shutil
import zipfile

PATH_BASE = os.path.abspath(os.path.dirname(__file__))
PATH_BASE_MODULE = os.path.join(PATH_BASE, "base")
PATH_BUILDS = os.path.join(PATH_BASE, "builds")


def traverse_path_to_list(file_list, path):
    for dp, dn, fn in os.walk(path):
        for f in fn:
            if f == "placeholder" or f == ".gitkeep":
                continue
            file_list.append(os.path.join(dp, f))


def create_module_prop(path, frida_release):
    # Create module.prop file.
    module_prop = """id=magiskfurtif
name=MagiskFurtif
version=v{0}
versionCode={1}
author=Furtif
description=Runs FurtiF Tools on boot with magisk.
support=https://github.com/Furtif/magisk-furtif/issues
minMagisk=1530""".format(frida_release, frida_release.replace(".", ""))

    with open(os.path.join(path, "module.prop"), "w", newline='\n') as f:
        f.write(module_prop)


def create_module(frida_release):
    # Create directory.
    module_dir = os.path.join(PATH_BUILDS, "module_temp")
    module_zip = os.path.join(PATH_BUILDS, f"MagiskFurtif-{frida_release}.zip")

    # Ensure clean slate.
    if os.path.exists(module_dir):
        print(f"Removing existing temporary directory: {module_dir}")
        shutil.rmtree(module_dir)

    if os.path.exists(module_zip):
        print(f"Removing existing zip file: {module_zip}")
        os.remove(module_zip)

    # Copy base module into module dir.
    shutil.copytree(PATH_BASE_MODULE, module_dir)

    # Temporarily change to module directory to gather files.
    os.chdir(module_dir)

    # Create module.prop.
    create_module_prop(module_dir, frida_release)

    # Create flashable zip.
    print("Building Magisk module.")

    file_list = ["install.sh", "module.prop"]

    traverse_path_to_list(file_list, "./common")
    traverse_path_to_list(file_list, "./system")
    traverse_path_to_list(file_list, "./META-INF")

    with zipfile.ZipFile(module_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        for file_name in file_list:
            path = os.path.join(module_dir, file_name)
            if not os.path.exists(path):
                print(f"File {path} does not exist.")
                continue
            zf.write(path, arcname=file_name)

    # Change back to the base directory before cleaning up.
    os.chdir(PATH_BASE)

    # Clean up intermediate directory.
    print(f"Cleaning up temporary directory: {module_dir}")
    shutil.rmtree(module_dir)



def main():
    # Create necessary folders.
    if not os.path.exists(PATH_BUILDS):
        os.makedirs(PATH_BUILDS)

    # Fetch frida information.
    frida_release = "1.8"
    frida_release = "1.8"

    print(f"MagiskFurtif version is {frida_release}.")
        
    # Create flashable modules.
    create_module(frida_release)

    print("Done. Only zip file remains in builds directory.")


if __name__ == "__main__":
    main()
