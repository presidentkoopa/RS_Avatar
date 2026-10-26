import sys
import config
E=str(config.ERMAC)+'/'
# Ermac's ready (gun frame, hand.md3 frame, hand2.md3 frame), from his "with both hands" blocks
SETS = {
 'pistol': ('pistol/berreta.md3', 0, 19, 4, 6),       # last: hand.md3 frame for one hand
 'shotgun': ('shotgun/shotgun.md3', 0, 30, 15, 30),
 'ssg': ('ssg/ssg.md3', 0, 47, 33, 47),
 'chaingun': ('chaingun/chaingun.md3', 0, 84, 70, 84),
 'rocket': ('rocketlauncher/rocketlauncher.md3', 0, 95, 80, 95),
 'plasma': ('plasmarifle/plasma_rifle.md3', 0, 106, 91, 106),
 'bfg': ('bfg9000/bfg9000.md3', 0, 113, 98, 113),
 'flamer': ('incinerator/flamethrower.md3', 0, 151, 136, 151),
}
PL = dict(scale=[-1.0, 1.0, 1.0], off=[0.0, -24.0, -10.0])
def items(name, hook=(0,0,0), two=True):
    g, gf, h1, h2, h1one = SETS[name]
    out = [dict(path=E+g, frame=gf, color=[150,155,170], **PL),
           dict(path=E+'hand/hand.md3', frame=h1 if two else h1one, color=[225,170,135], **PL)]
    if two:
        out.append(dict(path=E+'hand/hand2.md3', frame=h2, color=[120,200,140], **PL))
    return out
