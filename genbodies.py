"""genbodies.py -- write MODELDEF, VRAVATAR, CVARINFO and the actor classes from what is
installed.

    python genbodies.py

Reads models/avatars/*/ and generates, for every body that has a model and a measured
.avatar beside it:

    MODELDEF.txt              one block per body
    VRAVATAR.txt              one entry per body
    CVARINFO.txt              the settings, plus fit-mode storage per body per hand
    zscript/avatar/bodies.zs  one actor class per body

GENERATED, NOT HAND-WRITTEN, for two specific reasons:

  - A MODELDEF block naming a class that does not exist is a FATAL error at startup, about
    eight seconds in, with nothing useful logged -- the kind of fault found by bisecting a
    file. Generating the classes and the blocks from one list means they cannot disagree.
  - Fit mode saves six numbers per hand per body into an archived cvar, and a cvar can only
    be created by CVARINFO, never from script. A body missing its pair cannot be fitted at
    all, and fit mode would have nowhere to write.

Run install_avatars.py first; it puts the models in and measures them.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AVATARS = os.path.join(HERE, "models", "avatars")

# ---- HAND-WRITTEN CONTENT SURVIVES A REGENERATION ------------------------------
#
# This script opens four lumps with mode "w" and rewrites each one whole from a template.
# Every template holds only the per-body material, so for a long time running it silently
# deleted every hand-written thing that had accumulated in those files. As of 2026-10-01 the
# casualties would have been:
#
#   CVARINFO.txt   vr_fit_aimray; the four colour cvars (vr_avatar_armour_colour,
#                  vr_avatar_breathe, vr_avatar_breathe_below, vr_avatar_colour); the three
#                  helmet cvars (vr_avatar_helmet, rsa_helmet_eyefade_near/_far)
#   MODELDEF.txt   the whole `Model RSA_Helmet` block
#   MENUDEF.txt    the height section, the helmet section and the colour option
#
# Features, not comments -- and they would have gone without a word, because the generator
# succeeds. Nothing in the file said this, which is why it survived as a trap.
#
# So: everything from KEEP_MARK to the end of a generated file is read before the file is
# truncated and written back out after the generated part. Put hand-written material below
# the mark and it is permanent; put it above and it is still deleted, which is why
# check_unmarked() below refuses rather than letting that happen quietly.
KEEP_MARK = "// ==== HAND-WRITTEN BELOW HERE -- genbodies.py KEEPS THIS ===="

# The same, for a ZScript file, where // is also a comment -- kept separate so the two can
# diverge if a generated file ever needs a different comment syntax.
KEEP_MARK_ZS = KEEP_MARK


def keep_tail(path, mark=KEEP_MARK):
    """Everything from `mark` onward in an existing file, or '' if there is none.

    Read BEFORE the file is opened for writing: mode "w" truncates, so a tail collected
    afterwards is always empty.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as r:
            text = r.read()
    except OSError:
        return ""
    i = text.find(mark)
    if i < 0:
        return ""
    tail = text[i:]
    if not tail.endswith("\n"):
        tail += "\n"
    return "\n" + tail


def check_unmarked(path, generated, mark=KEEP_MARK):
    """Lines in the existing file, above the mark, that this run would NOT have written.

    Compared against the text the generator just produced rather than against a list of
    allowed prefixes. A prefix list cannot work here: the hand-written cvars in CVARINFO.txt
    begin with `user` exactly like the generated ones, so a prefix check passes them and the
    first regeneration still eats them -- which is the whole failure being guarded against.
    Comparing against the real output has no such blind spot.

    The mark only protects what is BELOW it. Anything above it is still destroyed, so this
    refuses rather than trusting whoever edits next to know the rule. Being told to move
    three lines is a better day than finding out in a headset that the helmet is gone.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as r:
            text = r.read()
    except OSError:
        return []            # no file yet: nothing to lose
    head = text.split(mark, 1)[0]
    made = set()
    for line in generated.splitlines():
        t = line.strip()
        if t:
            made.add(t)
    strays = []
    for n, line in enumerate(head.splitlines(), 1):
        t = line.strip()
        if not t or t.startswith("//") or t.startswith("#"):
            continue
        if t in made:
            continue
        strays.append((n, t))
    return strays


def emit(path, generated, tail, label):
    """Write a generated lump, keeping its hand-written tail, refusing on a stray.

    Composed in memory first so the stray check can compare the existing file against what
    this run would actually produce -- and so a refusal happens before anything is truncated.
    """
    strays = check_unmarked(path, generated)
    if strays:
        return ["  %s:%d  %s" % (os.path.basename(path), n, t) for n, t in strays]
    with open(path, "w", encoding="utf-8", newline="") as w:
        w.write(generated)
        w.write(tail)
    return []


def pretty(name):
    """A body's name as a person would read it."""
    words = name.replace("_", " ").split()
    out = []
    for w in words:
        if w.lower() in ("c", "rs"):
            out.append(w.upper())
        else:
            out.append(w[:1].upper() + w[1:])
    return " ".join(out)

def camel(name):
    return "".join(p.capitalize() for p in name.split("_"))


def find_bodies():
    out = []
    if not os.path.isdir(AVATARS):
        return out
    for name in sorted(os.listdir(AVATARS)):
        d = os.path.join(AVATARS, name)
        if not os.path.isdir(d):
            continue
        mdl = [f for f in sorted(os.listdir(d)) if f.lower().endswith(".mdl")]
        avf = [f for f in sorted(os.listdir(d)) if f.lower().endswith(".avatar")]
        if not mdl:
            print("  skipped %-22s no .mdl in its folder" % name)
            continue
        if not avf:
            print("  skipped %-22s no .avatar -- run install_avatars.py" % name)
            continue
        tier = "?"
        has_handrest = False
        try:
            for line in open(os.path.join(d, avf[0]), encoding="utf-8"):
                t = line.strip()
                if line.startswith("tier"):
                    tier = line.split()[1]
                if t.startswith("handrest"):
                    has_handrest = True
        except OSError:
            pass

        # THE ENGINE'S CONTRACT, APPLIED HERE TOO. Without `handrest` the engine cannot build
        # O_hand, so the hand takes the controller's raw rotation and faces wherever the grip
        # faces -- and the avatar registry refuses the body outright. Writing it into the menu
        # anyway offers the player a body that cannot load.
        #
        # Checked as a rule, not by name: fix a body's measurements and it comes back with no
        # code change. doomslayer_lowpoly is the one this drops today.
        if not has_handrest:
            print("  skipped %-22s no `handrest` in its .avatar -- the engine refuses it" % name)
            continue
        out.append(dict(name=name, cls="RSA_" + camel(name), mdl=mdl[0],
                        avatar=avf[0], tier=tier))
    return out


MODELDEF_HEAD = """\
// GENERATED BY genbodies.py -- DO NOT EDIT BY HAND.
//
// One block per avatar actor. A MODELDEF block binds to exactly the class it names and not
// to its children, and a block naming a class that does not exist is FATAL at startup with
// nothing useful logged -- so these are generated from the same list as the classes and can
// never disagree with them.
//
// The models are Valve Source .mdl and are loaded as such. Nothing is converted: the file
// measured by tools/avatar/measure_avatar.py is the file drawn here.
//
// Scale is 1 on purpose. The body is sized every frame by the player's own eye height
// against the model's measured eye height -- a typed scale would be a tuned constant about
// a model, which is the thing this rebuild exists to remove.

"""

VRAVATAR_HEAD = """\
// GENERATED BY genbodies.py -- DO NOT EDIT BY HAND.
//
// Which bodies exist (VR_BODY_HANDS_SPEC.md C.4). `vr_avatar "<name>"` picks one; empty
// means none, and with none nothing is spawned, drawn or hooked.
//
// Another mod adds a body by shipping its own VRAVATAR lump beside its model, with no edit
// to this file and no engine change. The list is the union of them all.

"""

BODIES_HEAD = """\
// GENERATED BY genbodies.py -- DO NOT EDIT BY HAND.
//
// One class per body, because a MODELDEF block binds to the class it names and NOT to its
// children -- a single shared class with the model chosen at runtime is not possible without
// an engine change. Everything that makes an avatar an avatar lives in RSA_AvatarBase
// (actor.zs); these exist only to be named.

"""

CVARINFO_HEAD = """\
// GENERATED BY genbodies.py -- DO NOT EDIT BY HAND.
//
// `user` and archived, so a choice follows the player and survives a restart.

"""

CVARINFO_BASE = """\
// Which body to wear. A name from a VRAVATAR lump; empty means none, and with none nothing
// is spawned, drawn or hooked -- the mod is inert.
user string vr_avatar = "%s";

// Draw the WHOLE body from your own eyes, rather than only the hands and forearms.
//
// Off by default: until the arm solve lands (M3) the arms follow the hands rigidly, and a
// torso attached to them is visibly wrong seen from the inside. This exists so a body can
// be looked at on purpose anyway.
//
// It does not affect a mirror, a spectator or another player -- they always see the whole
// body, because what is hidden is decided per view, not in the pose.
user bool vr_avatar_fullbody = false;

// Draw the avatar's joints as axes (level 2 of the rig debug drawing).
user bool vr_avatar_debug = false;

// The in-game mirror. It hangs itself in front of you when you switch it on and stays put,
// so you can walk up to it and turn side-on -- which is most of what a mirror is for.
//
// A MONITOR, NOT A REFLECTION, and deliberately: the camera stands at the panel and TRACKS
// you, so you stay in frame while you walk, crouch and lean. A true reflection loses you the
// moment you step aside, which is exactly when you were trying to look at yourself.
//
// It renders the whole scene a second time. Switch it on to check something, off after.
user bool vr_mirror = false;
user float vr_mirror_dist = 96.0;       // how far in front of you it stands
user float vr_mirror_up = 34.0;         // its centre above your feet
user float vr_mirror_fov = 70.0;        // how much of you it takes in
user float vr_mirror_standoff = 8.0;    // camera clear of its own panel; see mirror.zs

// ---- the body fit (VR_BODY_HANDS_SPEC.md M3 task 3) ------------------------
//
// Measured off the player by `vr_fitmode body`: stand straight, both arms out to the sides,
// hold the trigger. Everything downstream scales from these two -- the avatar's world scale,
// and how far the arm solver reaches.
//
// Zero means never fitted. The engine then assumes the player is built like the body he is
// wearing, which is visibly wrong for a tall player on a short model and honest about it
// rather than quietly guessing.
user float vr_fit_height = 0.0;      // eye height standing, metres
user float vr_fit_armspan = 0.0;     // wrist to wrist, arms out, metres

// ---- fit mode storage (VR_BODY_HANDS_SPEC.md C.5) --------------------------
//
// Six numbers as one string: "x y z pitch yaw roll". Offsets are in the hand frame;
// rotations apply pitch about X, yaw about Z, roll about Y, in that order.
//
// ONE STRING AND NOT SIX CVARS: forty-two cvars for seven bodies is a config file nobody
// can read, and the six are only ever set or cleared together.
//
// Empty means never fitted, which is not an error -- the engine then uses the fit derived
// from the model's own measurements (spec B.5).

"""


def main():
    bodies = find_bodies()
    if not bodies:
        sys.stderr.write("genbodies: no bodies installed -- run install_avatars.py first\n")
        return 1

    p_modeldef = os.path.join(HERE, "MODELDEF.txt")
    p_vravatar = os.path.join(HERE, "VRAVATAR.txt")
    p_cvarinfo = os.path.join(HERE, "CVARINFO.txt")
    p_menudef = os.path.join(HERE, "MENUDEF.txt")

    # READ THE TAILS FIRST. Mode "w" truncates, so a tail read after the open is empty.
    tail_modeldef = keep_tail(p_modeldef)
    tail_vravatar = keep_tail(p_vravatar)
    tail_cvarinfo = keep_tail(p_cvarinfo)
    tail_menudef = keep_tail(p_menudef)

    # Composed in memory, written at the end: see emit(). Nothing is truncated until every
    # file has passed its stray check, so a refusal cannot leave the pack half-regenerated.
    with io.StringIO() as w:
        w.write(MODELDEF_HEAD)
        for b in bodies:
            w.write("Model %s\n{\n" % b["cls"])
            w.write("\tPath \"models/avatars/%s\"\n" % b["name"])
            w.write("\tModel 0 \"%s\"\n" % b["mdl"])
            w.write("\tScale 1.0 1.0 1.0\n")
            w.write("\tUSEACTORPITCH\n\tUSEACTORROLL\n")
            w.write("\tFrameIndex PIST A 0 0\n}\n\n")
        txt_modeldef = w.getvalue()

    with io.StringIO() as w:
        w.write(VRAVATAR_HEAD)
        for b in bodies:
            w.write("avatar %s\n{\n" % b["name"])
            w.write("\tactor  \"%s\"\n" % b["cls"])
            w.write("\tdata   \"models/avatars/%s/%s\"\n}\n\n" % (b["name"], b["avatar"]))
        txt_vravatar = w.getvalue()

    with open(os.path.join(HERE, "zscript", "avatar", "bodies.zs"),
              "w", encoding="utf-8", newline="") as w:
        w.write(BODIES_HEAD)
        for b in bodies:
            w.write("// %s, %s\n" % (b["name"],
                                     "fingers" if b["tier"] == "Full" else b["tier"]))
            w.write("class %s : RSA_AvatarBase {}\n\n" % b["cls"])

    with io.StringIO() as w:
        w.write(CVARINFO_HEAD)
        w.write(CVARINFO_BASE % bodies[0]["name"])
        for b in bodies:
            for side in ("R", "L"):
                w.write("user string vr_fit_hand_%s_%s = \"\";\n" % (b["name"], side))
            w.write("\n")
        txt_cvarinfo = w.getvalue()


    # ---- MENUDEF ---------------------------------------------------------
    #
    # THE ONLY INTERFACE THERE IS. The person using this is wearing a headset: he cannot
    # reach a keyboard, read a console or type a cvar name, so anything that is only a
    # console command does not exist as far as he is concerned.
    #
    # Generated with everything else, so the body list can never offer something that is not
    # installed -- picking a missing body would spawn nothing and say so in a console he
    # cannot see.
    with io.StringIO() as w:
        w.write("// GENERATED BY genbodies.py -- DO NOT EDIT BY HAND.\n\n")

        w.write("OptionString \"RSA_BodyList\"\n{\n")
        # "none", NOT the empty string. The option menu decides whether a list is numbers
        # or strings by testing whether the FIRST entry's value is empty -- an empty first
        # value sends the whole list down the numeric path, where it matches nothing and
        # the control shows its first entry forever whatever you pick. That is exactly what
        # it did: the body could not be changed from Off.
        w.write("\t\"none\", \"Off (no body)\"\n")
        for b in bodies:
            w.write("\t\"%s\", \"%s\"\n" % (b["name"], pretty(b["name"])))
        w.write("}\n")

        # AND THAT IS ALL THIS GENERATES. The menu itself used to be templated here too,
        # and the template had fallen well behind the real MENUDEF.txt: no height section,
        # no helmet section, no colour option, none of the explanatory lines the owner reads
        # from inside a headset. Running this would have quietly replaced the good menu with
        # the stale one. The body list is the only part that MUST be generated, because it
        # has to match the bodies actually installed; the menu is hand-written and lives
        # below the keep mark in MENUDEF.txt.
        txt_menudef = w.getvalue()

    # EVERY FILE CHECKED BEFORE ANY FILE IS WRITTEN, so a refusal cannot leave the pack
    # half-regenerated with two lumps describing different sets of bodies.
    strays = []
    for path, generated in ((p_modeldef, txt_modeldef), (p_vravatar, txt_vravatar),
                            (p_cvarinfo, txt_cvarinfo), (p_menudef, txt_menudef)):
        for n, line in check_unmarked(path, generated):
            strays.append("  %s:%d  %s" % (os.path.basename(path), n, line))
    if strays:
        sys.stderr.write(
            "genbodies: REFUSING TO RUN -- these lines sit above the keep mark, and this run\n"
            "would delete them. Move them below the line\n\n    %s\n\nin their own file, then\n"
            "run again. NOTHING HAS BEEN WRITTEN.\n\n%s\n"
            % (KEEP_MARK, "\n".join(strays)))
        return 1

    for path, generated, tail in ((p_modeldef, txt_modeldef, tail_modeldef),
                                  (p_vravatar, txt_vravatar, tail_vravatar),
                                  (p_cvarinfo, txt_cvarinfo, tail_cvarinfo),
                                  (p_menudef, txt_menudef, tail_menudef)):
        with open(path, "w", encoding="utf-8", newline="") as w:
            w.write(generated)
            w.write(tail)

    print("genbodies: wrote MODELDEF.txt, VRAVATAR.txt, CVARINFO.txt, MENUDEF.txt "
          "and zscript/avatar/bodies.zs")
    kept = [n for n, t in (("MODELDEF", tail_modeldef), ("VRAVATAR", tail_vravatar),
                           ("CVARINFO", tail_cvarinfo), ("MENUDEF", tail_menudef)) if t]
    if kept:
        print("genbodies: kept the hand-written tail of " + ", ".join(kept))
    else:
        print("genbodies: no hand-written tails found -- if that is a surprise, the keep mark\n"
              "           is missing and something has already been lost: " + KEEP_MARK)
    for b in bodies:
        print("  %-22s %-26s %-36s %s" % (b["name"], b["cls"], b["mdl"], b["tier"]))
    print("\nPick one in game with:  vr_avatar %s" % bodies[0]["name"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
