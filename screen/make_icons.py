"""The guides switch's icons for Ford's camera view row: our own drawing in
the row's style. Two guides seen from the driver's seat as on the screen: each a column of blocks narrowing into
the distance, with a thin rail outside.

Matched to the truck's theme (ford-CX430, which takes ford-MY20's icons; confirmed on the truck):
40 x 40 (MY20's small icon size), drawn over rows 3 to 32 like MY20's front-view icons (rows 2 to 32), one flat
colour per state, the colours MY20's own front-view icons use:
    night: off (MY20's unselected, the "_active" link) 198 198 198, on (selected) 27 148 250
    day:   off 54 57 58, on 0 60 255
The row draws a full-path icon without state suffixes, so the snippet picks the file by on / off and by the palette
(UiTheme.palette.iconPath holds /day/ or /night/).
    python3 make_icons.py     (writes guides_{on,off}_{day,night}.png beside this file)"""
import os
from PIL import Image, ImageDraw

S = 8                       # drawn 8x, scaled down: smooth edges
N = 40
TOP, BOTTOM = 3.2, 32.0     # rows the drawing spans
here = os.path.dirname(os.path.abspath(__file__))
COLOURS = {
    'paths_off_night.png': (198, 198, 198), 'paths_on_night.png': (27, 148, 250),
    'paths_off_day.png': (54, 57, 58), 'paths_on_day.png': (0, 60, 255),
}

def x_at(x_bottom, y, vanish=(20, -32)):
    """x on a line from (x_bottom, BOTTOM) towards the vanishing point, at height y"""
    t = (BOTTOM - y) / (BOTTOM - vanish[1])
    return x_bottom + (vanish[0] - x_bottom) * t

def draw(colour):
    im = Image.new('RGBA', (N * S, N * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = colour + (255,)
    h = BOTTOM - TOP
    # rows of blocks, near to far, as fractions of the height from the bottom: (start, end)
    rows = [(0.00, 0.25), (0.33, 0.52), (0.60, 0.75), (0.82, 1.00)]
    for inner, outer in ((16.6, 10.0), (23.4, 30.0)):          # left track (inner, outer edge), right track
        for a, b in rows:
            yb, yt = BOTTOM - a * h, BOTTOM - b * h
            pts = [(x_at(outer, yb), yb), (x_at(inner, yb), yb), (x_at(inner, yt), yt), (x_at(outer, yt), yt)]
            d.polygon([(x * S, y * S) for x, y in pts], fill=c)
        side = -1 if outer < 20 else 1                          # the thin rail outside the tire
        rail, w = outer + side * 2.2, 1.25
        pts = [(x_at(rail, BOTTOM), BOTTOM), (x_at(rail + side * w, BOTTOM), BOTTOM),
               (x_at(rail + side * w, TOP), TOP), (x_at(rail, TOP), TOP)]
        d.polygon([(x * S, y * S) for x, y in pts], fill=c)
    return im.resize((N, N), Image.BOX)

for name, colour in COLOURS.items():
    draw(colour).save(os.path.join(here, name))
    print('wrote', name)
