#!/usr/bin/env python3
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
    
    def create_banner():
        # 創建 320x180 的 banner
        img = Image.new('RGB', (320, 180), color='#0066CC')
        draw = ImageDraw.Draw(img)

        # 嘗試載入字型，如果失敗則用預設字型
        try:
            font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 24)
        except:
            font = ImageFont.load_default()

        # 計算文字位置以置中
        text = 'VideoTV'
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        x = (320 - text_width) // 2
        y = (180 - text_height) // 2

        # 繪製文字
        draw.text((x, y), text, fill='white', font=font)

        # 儲存圖片
        os.makedirs('android/app/src/main/res/drawable-xhdpi', exist_ok=True)
        img.save('android/app/src/main/res/drawable-xhdpi/banner.png')

        # 創建更高解析度版本 (640x360)
        img_hd = Image.new('RGB', (640, 360), color='#0066CC')
        draw_hd = ImageDraw.Draw(img_hd)

        try:
            font_hd = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 48)
        except:
            font_hd = ImageFont.load_default()

        bbox_hd = draw_hd.textbbox((0, 0), text, font=font_hd)
        text_width_hd = bbox_hd[2] - bbox_hd[0]
        text_height_hd = bbox_hd[3] - bbox_hd[1]
        x_hd = (640 - text_width_hd) // 2
        y_hd = (360 - text_height_hd) // 2

        draw_hd.text((x_hd, y_hd), text, fill='white', font=font_hd)

        os.makedirs('android/app/src/main/res/drawable-xxhdpi', exist_ok=True)
        img_hd.save('android/app/src/main/res/drawable-xxhdpi/banner.png')

        print('Banner images created successfully!')
        return True

    if __name__ == "__main__":
        create_banner()

except ImportError:
    print("PIL not available. Please install: pip3 install --user Pillow")
    sys.exit(1) 