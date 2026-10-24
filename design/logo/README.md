# Логотип CrossLink — «Стекло»

Экран Mac и матовый стеклянный телефон поверх него. Холст 1024×1024.

| Файл | Куда идёт |
|---|---|
| `mac_icon.svg` | `macos/CrossLink/Assets.xcassets/AppIcon.appiconset` (16–1024 px) |
| `android_bg.svg`, `android_fg.svg` | `android/app/src/main/res/mipmap-*/ic_launcher_{background,foreground}.png` (108–432 px) |
| `glyph.svg` | значок строки меню Mac (`MenuBarIcon`, шаблон 18/36 px); тот же силуэт вектором — `drawable/ic_launcher_monochrome.xml`, `drawable/ic_stat_crosslink.xml` |

Стекло — это размытие (`feGaussianBlur`), которого нет в VectorDrawable, поэтому слои Android — PNG.

На иконках Mac и Android есть плёночное зерно, как на тёмной панели вверху приложения. Оно
накладывается отдельно для каждого размера PNG, чтобы оставаться в один пиксель: зерно, нарисованное
на 1024 px и уменьшенное, усредняется и пропадает. Сила — `GRAIN` в `export.py` (0,028); на
иконках Mac 16–32 px зерна нет, на 64 px — слабее.

Все PNG пересобирает один скрипт (Chrome рисует фильтры точно, QuickLook — нет):

```bash
python3 -m venv .venv && .venv/bin/pip install pillow numpy
.venv/bin/python design/logo/export.py
```

Значок строки меню (`glyph.svg`) зерна не получает: это шаблон одного цвета.
