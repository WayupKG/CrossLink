# Логотип CrossLink — «Стекло»

Экран Mac и матовый стеклянный телефон поверх него. Холст 1024×1024.

| Файл | Куда идёт |
|---|---|
| `mac_icon.svg` | `macos/CrossLink/Assets.xcassets/AppIcon.appiconset` (16–1024 px) |
| `android_bg.svg`, `android_fg.svg` | `android/app/src/main/res/mipmap-*/ic_launcher_{background,foreground}.png` (108–432 px) |
| `glyph.svg` | значок строки меню Mac (`MenuBarIcon`, шаблон 18/36 px); тот же силуэт вектором — `drawable/ic_launcher_monochrome.xml`, `drawable/ic_stat_crosslink.xml` |

Стекло — это размытие (`feGaussianBlur`), которого нет в VectorDrawable, поэтому слои Android — PNG.

Рендер в PNG (Chrome рисует фильтры точно; QuickLook — нет):

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --hide-scrollbars --default-background-color=00000000 \
  --screenshot=mac_icon.png --window-size=1024,1024 "file://$PWD/mac_icon.svg"
sips -z 512 512 mac_icon.png --out icon_512.png
```
