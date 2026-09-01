from dataclasses import dataclass
from typing import Tuple
import math

@dataclass
class Camera:
    azimuth_deg: float = 45.0
    elevation_deg: float = 30.0
    scale: float = 8.0
    origin: Tuple[float,float] = (128,64)

    def project(self, x, y, z):
        a = math.radians(self.azimuth_deg)
        e = math.radians(self.elevation_deg)
        u = x*math.cos(a) - y*math.sin(a)
        v = (x*math.sin(a) + y*math.cos(a))*math.sin(e)
        return (
            self.origin[0] + u*self.scale,
            self.origin[1] + v*self.scale - z*self.scale*math.cos(e)
        )

def box_corners(x,y,z,w,d,h):
    return {
        "bfl":(x,y,z), "bfr":(x+w,y,z), "bbr":(x+w,y+d,z), "bbl":(x,y+d,z),
        "tfl":(x,y,z+h), "tfr":(x+w,y,z+h),
        "tbr":(x+w,y+d,z+h), "tbl":(x,y+d,z+h)
    }
