import os
import shutil

pathDownload = r"C:\\Users\\Brian\\Downloads\\"
pathDesktop =  r"C:\\Users\\Brian\\Desktop\\"

file_types = {
    "Images": [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".heic"],
    "Documents": [".pdf", ".docx", ".doc", ".txt", ".xlsx", ".pptx"],
    "Videos": [".mp4", ".mov", ".avi", ".mkv"],
    "Music": [".mp3", ".wav", ".aac"],
    "Archives": [".zip", ".rar", ".7z", ".tar", ".gz"],
    "3D_Print": [".stl", ".3mf"],
    "Apps": [".exe", ".msi", ".msix"]
}

# Process Downloads with ALL file types
for file in os.listdir(pathDownload):
    filename, ext = os.path.splitext(file)
    for folder, extensions in file_types.items():
        if ext.lower() in extensions:
            folder_path = os.path.join(pathDownload, folder)
            os.makedirs(folder_path, exist_ok=True)
            shutil.move(os.path.join(pathDownload, file), folder_path)
            break

# Process Desktop EXCLUDING "Apps" type
for file in os.listdir(pathDesktop):
    filename, ext = os.path.splitext(file)
    for folder, extensions in file_types.items():
        if folder == "Apps":  # Skip Apps category for Desktop
            continue
        if ext.lower() in extensions:
            folder_path = os.path.join(pathDesktop, folder)
            os.makedirs(folder_path, exist_ok=True)
            shutil.move(os.path.join(pathDesktop, file), folder_path)
            break
