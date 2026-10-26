"""Where everything is. Set DOOMWORK to the DOOMWork folder if it is not E:/DOOMWork, and
AVGRIP_OUT to send the outputs somewhere other than ./out next to these scripts."""
import os
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get('DOOMWORK', 'E:/DOOMWork'))
WEAPONS = ROOT / 'RS_VR_Weapons'                                         # the cards and meshes
CSV = ROOT / '_reports' / 'gun_seating_2026-10-02' / 'WEAPON_SETS.csv'   # hidden surfaces per gun
# Ermac's posed hands and guns (Force Unleashed). The one thing read from _old, by the owner's
# leave: they are the measuring tool for the review pictures and the two-hand pistol hold, and
# never ship anywhere.
ERMAC = ROOT / '_old' / 'doom-force-unleashed_devbuild' / 'models'
DATA = HERE / 'data'
OUT = Path(os.environ.get('AVGRIP_OUT', HERE / 'out'))
OUT.mkdir(parents=True, exist_ok=True)

# [RELOAD HANDS] the reference body and the engine's own avatar tools, for the part seats
AVATAR_TOOLS = ROOT / 'UZDXREMA' / 'tools' / 'avatar'           # measure_avatar, test_curl, studio, iqm
CURL_TABLE = AVATAR_TOOLS / 'handcurl.txt'                         # the finger table the engine reads
BODY_DIR = ROOT / 'RS_Avatar' / 'models' / 'avatars' / 'c_doom_marine'
BODY_MAP = AVATAR_TOOLS / 'bonemaps' / 'c_doom_marine.bonemap'
BODY_SCALE = 0.655                                                 # RS_AVATAR.md 3: map units per body unit
