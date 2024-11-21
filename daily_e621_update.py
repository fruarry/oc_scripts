import subprocess

n_total = 50
n_day = 40
n_week = 10

from datetime import datetime, timedelta
yesterday = datetime.now() - timedelta(1)
ytd_date = datetime.strftime(yesterday, '%Y-%m-%d')

def extract_frame(file_path, frame_path):
    import cv2 
    cap = cv2.VideoCapture(file_path)
    video_length = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) - 1
    count = 0
    while cap.isOpened():
        # Extract the frame
        ret, frame = cap.read()
        if not ret:
            continue
        count = count + 1
        # If it reaches 10%
        if count >= video_length//10:
            # Log the time again
            cv2.imwrite(frame_path, frame)
            break

def download_images():
    image_info = []

    import requests
    from bs4 import BeautifulSoup
    from PIL import Image
    
    header = { 
        "User-Agent": "Mozilla / 5.0(Windows NT 10.0; Win64; x64) AppleWebKit / 537.36(KHTML, like Gecko) Chrome / 80.0.3987.122  Safari / 537.36"
    }
    suffix_day = '+21%3A59%3A11+-0500&scale=day'
    suffix_week = '+21%3A59%3A11+-0500&scale=week'

    # ================================
    # fetch response day
    url = 'https://e621.net/popular?date='+ytd_date+suffix_day
    page = requests.get(url=url, headers=header)
    if page.status_code != 200:
        print(f"retruned {page.status_code}")
        exit()

    soup = BeautifulSoup(page.text, 'html.parser')
    post = soup.find_all(class_='posts-container')
    article = post[0].find_all('article')

    for i in range(n_day):
        image_info.append([article[i]['data-id'], article[i]['data-file-url']])

    # ================================
    # fetch response week
    url = 'https://e621.net/popular?date='+ytd_date+suffix_week
    page = requests.get(url=url, headers=header)
    if page.status_code != 200:
        print(f"retruned {page.status_code}")
        exit()

    soup = BeautifulSoup(page.text, 'html.parser')
    post = soup.find_all(class_='posts-container')
    article = post[0].find_all('article')

    i = 0
    count = 0
    while count <= n_week:
        img_info = [article[i]['data-id'], article[i]['data-file-url']]
        if not img_info in image_info:
            image_info.append(img_info)
            count += 1
        i += 1
        if i > 20:
            break

    # ================================
    # download images
    import os.path
    img_list = []
    for i in range(n_total):
        file_name = image_info[i][0]
        img_url = image_info[i][1]
        extension = os.path.splitext(img_url)[1]
        response = requests.get(img_url)
        if not response.ok:
            continue
        with open(f'daily_e621/{file_name}{extension}', 'wb') as img_file:
            img_file.write(response.content)
        
        if extension in ['.gif', '.GIF']:
            with Image.open(f'daily_e621/{file_name}{extension}') as im:
                im.seek(im.n_frames//10)
                im.save(f'daily_e621/{file_name}_{1}.png')
                file_name = f'{file_name}_{1}'
                extension = '.png'
        elif extension in ['.webm', '.WEBM']:
            extract_frame(f'daily_e621/{file_name}{extension}', f'daily_e621/{file_name}_1.jpg')
            file_name = f'{file_name}_{1}'
            extension = '.jpg'

        print(f'write to daily_e621/{file_name}{extension}')
        img_list.append((file_name, extension))

    return img_list

def convert_images(img_list):
    # ================================
    # determine image size
    from PIL import Image

    def get_resize(img_file):
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
        w, h = get_resize(f'daily_e621/{file_name}{extension}')
        print(f"convert daily_e621/{file_name}{extension} to ./daily_e621/ctif/{file_name}.ctif")
        subprocess.call(f"java -jar CTIFConverter-0.2.2.jar -m oc-tier3 -W {w} -H {h} -o daily_e621/ctif/{file_name}.ctif daily_e621/{file_name}{extension}")

def push_to_github(img_list):
    # ================================
    # write update list
    with open('daily_e621/ctif/update.log', 'w') as f:
        for file_name, extension in img_list:
            f.write(f'{file_name}.ctif\n')

    # ================================
    # push to remote
    from git import Repo

    print('pushing to remote')
    repo = Repo.init("")
    origin = repo.remote(name='origin')

    repo.index.add(f'daily_e621/ctif/update.log')
    for file_name, extension in img_list:
        repo.index.add(f'daily_e621/ctif/{file_name}.ctif')
    repo.index.commit('daily_e621 update')

    origin.push()
    print("update completed")

import pickle
img_list = download_images()

with open(f'daily_e621/log/{ytd_date}', 'wb') as f:
    pickle.dump(img_list, f)

# with open(f'daily_e621/log/2024-11-12', 'rb') as f:
#     img_list = pickle.load(f)
     
convert_images(img_list)

push_to_github(img_list)