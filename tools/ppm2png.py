# -*- coding: utf-8 -*-
import glob, os
from PIL import Image
for f in glob.glob('build/ui_*.ppm'):
    im = Image.open(f)
    k = 3 if im.width <= 400 else 1
    im = im.resize((im.width * k, im.height * k), Image.NEAREST)
    im.save(f.replace('.ppm', '.png'))
    print(f)
