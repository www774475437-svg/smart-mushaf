"""Adjusts the web project that `flutter create` generates in CI."""
import json
import pathlib
from PIL import Image

web = pathlib.Path('web')
idx = web / 'index.html'
s = idx.read_text()
s = s.replace('<html>', '<html lang="ar" dir="rtl">')
import re
s = re.sub(r'<title>.*?</title>', '<title>المصحف الذكي</title>', s)
s = re.sub(r'<meta name="description" content="[^"]*">',
           '<meta name="description" content="المصحف الذكي: مصحف المدينة مع التلاوات والتفاسير والحفظ والتسميع">', s)
s = s.replace('content="smart_mushaf"', 'content="المصحف الذكي"')
idx.write_text(s)

man = web / 'manifest.json'
m = json.loads(man.read_text())
m['name'] = 'المصحف الذكي'
m['short_name'] = 'المصحف الذكي'
m['background_color'] = '#0A3D31'
m['theme_color'] = '#0F5C4A'
m['description'] = 'مصحف المدينة مع التلاوات والتفاسير والحفظ والتسميع'
man.write_text(json.dumps(m, ensure_ascii=False, indent=2))

logo = Image.open('assets/images/logo.png').convert('RGB')
for name, size in [('icons/Icon-192.png', 192), ('icons/Icon-512.png', 512),
                   ('icons/Icon-maskable-192.png', 192), ('icons/Icon-maskable-512.png', 512), ('favicon.png', 32)]:
    p = web / name
    p.parent.mkdir(exist_ok=True)
    logo.resize((size, size), Image.LANCZOS).save(p)
print('web patched')
