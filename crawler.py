import json
import sys
import time
import traceback
import re
import requests
from bs4 import BeautifulSoup
import undetected_chromedriver as uc
from selenium.webdriver.common.by import By


def fetch_video_list(url, max_count=25):
    options = uc.ChromeOptions()
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')
    driver = uc.Chrome(options=options)
    driver.get(url)
    print('[Debug] Browser opened, waiting...')
    time.sleep(5)
    video_items = driver.find_elements(By.CLASS_NAME, 'video-img-box')
    video_list = []
    for item in video_items[:max_count]:
        try:
            img = item.find_element(By.TAG_NAME, 'img')
            img_url = img.get_attribute('data-src') or img.get_attribute('src')
            title_elem = item.find_element(By.CSS_SELECTOR, '.detail .title a')
            title = title_elem.text.strip()
            detail_url = title_elem.get_attribute('href')
            video_res = fetch_video_detail_m3u8(detail_url)
            video_list.append({
                'img_url': img_url,
                'title': title,
                'detail_url': detail_url,
                'video': video_res.get('m3u8_url'),
                'key_url': video_res.get('key_url')
            })
        except Exception as e:
            print(f'[Warn] failed to parse item: {e}')
    driver.quit()
    return video_list


def fetch_video_detail_m3u8(detail_url):
    options = uc.ChromeOptions()
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')
    driver = uc.Chrome(options=options)
    driver.get(detail_url)
    time.sleep(1)
    m3u8_url = None
    key_url = None
    try:
        scripts = driver.find_elements(By.TAG_NAME, 'script')
        for script in scripts:
            text = script.get_attribute('innerHTML')
            if text and '.m3u8' in text:
                match = re.search(r'(https?://[^\'"\s]+\.m3u8)', text)
                if match:
                    m3u8_url = match.group(1)
                    break
        if m3u8_url:
            try:
                res = requests.get(m3u8_url, timeout=8)
                if res.status_code == 200:
                    m3u8_txt = res.text
                    key_match = re.search(r'#EXT-X-KEY:METHOD=AES-128,URI="([^"]+)"', m3u8_txt)
                    if key_match:
                        key_url = key_match.group(1)
                        if not key_url.startswith('http'):
                            from urllib.parse import urljoin
                            key_url = urljoin(m3u8_url, key_url)
            except Exception as err:
                print(f'[Error] read key failed: {err}')
    except Exception as e:
        print(f'[Error] parse m3u8 failed: {e}')
    driver.quit()
    return {'m3u8_url': m3u8_url, 'key_url': key_url}


def main():
    target_url = 'https://jable.tv/categories/chinese-subtitle/'
    out_file = 'video_list.json'
    if len(sys.argv) > 1:
        out_file = sys.argv[1]
    try:
        data = fetch_video_list(target_url)
        with open(out_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f'Wrote {len(data)} items to {out_file}')
    except Exception as e:
        traceback.print_exc()
        print(f'[Error] failed: {e}')


if __name__ == '__main__':
    main()
