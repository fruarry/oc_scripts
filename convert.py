import subprocess

img_folder = "loona"

def get_images():
    import os
    img_list = []

    # Get all files in the folder
    files = os.listdir(img_folder)

    # Separate filename and extension
    file_info = [(os.path.splitext(file)[0], os.path.splitext(file)[1]) for file in files]

    # Print the filenames and extensions
    for name, ext in file_info:
        if ext == ".JPEG":
            img_list.append((name, ext))
            print(f"Filename: {name}, Extension: {ext}")
    return img_list

def convert_images(img_list):
    # ================================
    # determine image size
    def get_resize(img_file):
        from PIL import Image
        max_width = 320
        max_height = 200
        resize_width = 0
        resize_height = 0
        with Image.open(img_file) as img:
            width, height = img.size
            if (width/height) > (max_width/max_height):
                resize_width = max_width
                resize_height = int(max_width / (width/height))
            else:
                resize_height = max_height
                resize_width = int(max_height * (width/height))
        return resize_width, resize_height
    
    # ================================
    # convert with CTIF converter
    for file_name, extension in img_list:
        w, h = get_resize(f'{img_folder}/{file_name}{extension}')
        print(f"convert {img_folder}/{file_name}{extension} to {img_folder}/{file_name}.ctif")
        subprocess.call(f"java -jar CTIFConverter-0.2.2.jar -m oc-tier3 -W {w} -H {h} -P {img_folder}/{file_name}.png -o {img_folder}/{file_name}.ctif {img_folder}/{file_name}{extension}")

def push_to_github(img_list):
    # ================================
    # write update list
    with open(f'{img_folder}/update.log', 'w') as f:
        for file_name, extension in img_list:
            f.write(f'{file_name}.ctif\n')

    # ================================
    # push to remote
    from git import Repo

    print('pushing to remote')
    repo = Repo.init("")
    origin = repo.remote(name='origin')

    repo.index.add(f'{img_folder}/update.log')
    for file_name, extension in img_list:
        repo.index.add(f'{img_folder}/{file_name}.ctif')
    repo.index.commit(f'{img_folder} update')

    origin.push()
    print("update completed")

img_list = get_images()

convert_images(img_list)