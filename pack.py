"""Pack RS_Avatar into RS_Avatar.pk3.

    python pack.py

Everything in this folder goes in, except the pk3 itself and this script. Paths inside the
archive are exactly the paths on disk, because MODELDEF and the VRAVATAR lump both name
files by that path -- rewriting one silently while packing would give the engine a path that
does not resolve, and a missing model reports as "no model", not as "bad path".
"""
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "RS_Avatar.pk3")
SKIP_EXT = (".pk3", ".py", ".bak")


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    n = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(HERE):
            dirs[:] = [d for d in dirs if d not in ("__pycache__", ".git")]
            for f in sorted(files):
                if f.lower().endswith(SKIP_EXT):
                    continue
                p = os.path.join(root, f)
                rel = os.path.relpath(p, HERE).replace(os.sep, "/")
                z.write(p, rel)
                n += 1
    print("packed %s (%d files)" % (OUT, n))
    if n == 0:
        sys.stderr.write("pack.py: nothing was packed -- that cannot be right\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
