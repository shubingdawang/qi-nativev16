from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from engine.geometry.coords import Camera
from engine.render.renderer import PixelRenderer,BoxPart

S=[
("leg1",.15,.15,0,.18,.18,.55,"wood"),
("leg2",2.05,.15,0,.18,.18,.55,"wood"),
("leg3",.15,1.65,0,.18,.18,.55,"wood"),
("leg4",2.05,1.65,0,.18,.18,.55,"wood"),
("frame",0,0,.45,2.25,1.85,.32,"wood"),
("mattress",.12,.10,.77,2.01,1.65,.32,"mattress"),
("blanket",.18,.18,1.09,1.85,1.35,.10,"blanket"),
("pillow",.20,1.12,1.19,1.75,.38,.12,"pillow"),
("headboard",.08,1.70,.70,2.09,.12,.95,"wood")
]
C={
"wood":{"top":(183,132,83,255),"front":(150,98,58,255),"side":(125,78,48,255)},
"mattress":{"top":(245,236,214,255),"front":(220,205,180,255),"side":(198,181,153,255)},
"blanket":{"top":(231,145,155,255),"front":(202,108,123,255),"side":(183,91,108,255)},
"pillow":{"top":(250,247,235,255),"front":(225,219,201,255),"side":(205,197,177,255)}
}
parts=[BoxPart(a,b,c,d,e,f,g,C[k]) for a,b,c,d,e,f,g,k in S]
r=PixelRenderer((256,256),3,Camera(45,30,8,(128,45)))
r.render(parts).save(Path(__file__).with_name("bed_2_5d_demo.png"))
print("bed_2_5d_demo.png")
