# RS_Avatar

The VR body. RS_Avatar draws the player a real torso-up avatar in the world --
head, spine, arms and legs -- and keeps it consistent with where the headset and
the controllers actually are, rather than with where a viewmodel pretends they
are. The ZScript side lives in `zscript/avatar/`: the body actor itself, the
body set (`bodies.zs`), the arm/leg solving and the mirror pass, plus a fit mode
for calibrating a body to the player's own proportions. `genbodies.py` builds the
body models and `pack.py` packs the folder into `RS_Avatar.pk3`.

It needs the UZDXREMA engine fork; the bone reads, forced model angles and body
hooks it drives are not in stock GZDoom.
