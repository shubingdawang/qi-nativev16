from colorsys import hsv_to_rgb
from engine.render.renderer import Palette

def make_palette(hue=0.08, saturation=0.45, value=0.78):
    """
    Generate a restrained palette from a hue/theme.
    No object category is encoded here: the same generator can style cats,
    chairs, food, clothing, plants, or machines.
    """
    def c(h, s, v):
        r,g,b = hsv_to_rgb(h % 1.0, max(0,min(1,s)), max(0,min(1,v)))
        return (round(r*255), round(g*255), round(b*255), 255)

    base = c(hue, saturation, value)
    return Palette(
        outline=c(hue, min(1,saturation+.12), value*.38),
        shadow=c(hue, min(1,saturation+.08), value*.58),
        base=base,
        mid=c(hue, saturation*.90, value*.68),
        light=c(hue, saturation*.45, min(1,value*.98)),
        accent=c((hue+.06)%1, min(1,saturation+.10), min(1,value+.08)),
        dark_accent=c((hue-.035)%1, min(1,saturation+.16), value*.52),
    )
