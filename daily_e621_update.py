import subprocess

from datetime import datetime, timedelta
yesterday = datetime.now() - timedelta(1)
ytd_date = datetime.strftime(yesterday, '%Y-%m-%d')


def download_images():
    # ================================
    # fetch response
    url = 'https://e621.net/popular?date='+ytd_date+'+00%3A12%3A00+-0400&scale=day'
    header = { 
        "User-Agent": "Mozilla / 5.0(Windows NT 10.0; Win64; x64) AppleWebKit / 537.36(KHTML, like Gecko) Chrome / 80.0.3987.122  Safari / 537.36"
        }

    import requests
    from bs4 import BeautifulSoup

    page = requests.get(url=url, headers=header)
    if page.status_code != 200:
        print(f"retruned {page.status_code}")
        exit()

    soup = BeautifulSoup(page.text, 'html.parser')
    post = soup.find_all(id='posts-container')
    article = post[0].find_all('article')

    image_info = []
    for i in range(50):
        image_info.append([article[i]['data-id'], article[i]['data-large-url']])

    # ================================
    # download images
    import os.path
    img_list = []
    for i in range(50):
        file_name = image_info[i][0]
        img_url = image_info[i][1]
        extension = os.path.splitext(img_url)[1]
        response = requests.get(img_url)
        if not response.ok:
            continue
        with open(f'./daily_e621/{file_name}{extension}', 'wb') as img_file:
            img_file.write(response.content)
        print(f'write to ./daily_e621/{file_name}{extension}')
        img_list.append((file_name, extension))

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
        w, h = get_resize(f'{file_name}{extension}')
        print(f"convert ./daily_e621/{file_name}{extension} to ./daily_e621/ctif/{file_name}.ctif")
        subprocess.call(f"java -jar CTIFConverter-0.2.2.jar -m oc-tier3 -W {w} -H {h} -P ./daily_e621/preview/{file_name}.png -o ./daily_e621/ctif/{file_name}.ctif ./daily_e621/{file_name}{extension}")

def push_to_github(img_list):
    # ================================
    # write update list
    with open('./daily_e621/ctif/update.log', 'w') as f:
        for file_name, extension in img_list:
            f.write(f'{file_name}.ctif\n')

    # ================================
    # push to remote
    from git import Repo

    print('pushing to remote')
    repo = Repo.init("./")
    origin = repo.remote(name='origin')

    for file_name, extension in img_list:
        repo.index.add(f'./daily_e621/ctif/{file_name}.ctif')
    repo.index.commit('daily_e621 update')

    origin.push()
    print("update completed")

import pickle
img_list = download_images()

with open(f'./daily_e621/log/{ytd_date}', 'wb') as f:
    pickle.dump(img_list, f)

# with open(f'./daily_e621/log/2024-08-29', 'rb') as f:
#     img_list = pickle.load(f)
    
convert_images(img_list)

push_to_github(img_list)