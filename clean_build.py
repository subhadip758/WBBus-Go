import shutil
import os
import time

build_dir = r"c:\Users\Subhadip\Downloads\west_bengal_smart_bus\wbsb_web\android\app\build"

if os.path.exists(build_dir):
    print(f"Attempting to delete build folder: {build_dir}")
    for i in range(5):
        try:
            shutil.rmtree(build_dir)
            print("Successfully deleted build directory!")
            break
        except Exception as e:
            print(f"Attempt {i+1} failed: {e}")
            time.sleep(1)
else:
    print("Build directory does not exist or already clean.")
