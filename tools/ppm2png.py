# -*- coding: utf-8 -*-
import glob, os
from PIL import Image
for f in glob.glob('build/ui_*.ppm'):
    im = Image.open(f)
    im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
    im.save(f.replace('.ppm', '.png'))
    print(f)
