"""The Windows icon from the app icon (the phone's: a teal metronome on charcoal). python make-ico.py <png> <ico>"""
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGBA").save(sys.argv[2], sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
