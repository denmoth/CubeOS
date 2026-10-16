# -*- coding: utf-8 -*-
# Собирает кадры build/anim_<сцена>_NNN.ppm в build/ui_anim_<сцена>.gif (50 мс на кадр, увеличение в 3 раза). Нужен Pillow.
import glob
import os
import re
from PIL import Image

scenes = {}
for f in sorted(glob.glob('build/anim_*_*.ppm')):
    m = re.match(r'.*anim_(.+)_(\d+)\.ppm$', f.replace('\\', '/'))
    if m:
        scenes.setdefault(m.group(1), []).append(f)
for name, files in scenes.items():
    frames = []
    for f in files:
        im = Image.open(f).convert('RGB')
        k = 3 if im.width <= 400 else 1
        frames.append(im.resize((im.width * k, im.height * k), Image.NEAREST))
    out = 'build/ui_anim_%s.gif' % name
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=50, loop=0, optimize=False)
    for f in files:
        os.remove(f)
    print(out, len(frames), 'frames')
