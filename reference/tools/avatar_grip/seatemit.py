"""Write handseat (and handaxis) lines into COPIES of the cards, out/seat_cards_out/, keeping each file's line endings."""
import json, os, sys, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config
ROOT = str(config.WEAPONS)
OUT = str(config.OUT / 'seat_cards_out')
R = [r for r in json.load(open(str(config.OUT / 'seats.json'))) if 'seat' in r]
if len(sys.argv) > 1: R = [r for r in R if r['gun'] in sys.argv[1:]]
byfile = {}
for r in R: byfile.setdefault(r['file'], []).append(r)
def fmt(v): return ', '.join(('%.3f' % x).rstrip('0').rstrip('.') if '.' in ('%.3f' % x) else '%.3f' % x for x in v)
TAG = 'fitted 2026-10-11 to c_doom_marine (reload hands)'
for fn, rs in sorted(byfile.items()):
    raw = open(os.path.join(ROOT, fn), newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(eol)
    inserts = {}
    for r in rs:
        seat = '  handseat = %s      # where the avatar\'s palm goes on this part, %s' % (fmt(r['seat']), TAG)
        add = []
        if r.get('axis'):
            add.append('  handaxis = %s      # the line the hand closes round, index to little finger, %s' % (fmt(r['axis']), TAG))
        if r.get('handaxis_line') and add:
            # a fitted axis already on the card is replaced in place; one the card states by
            # hand (no fitted tag) is left alone
            j = r['handaxis_line'] - 1
            if TAG.split(' to ')[0] in lines[j] or 'reload hands' in lines[j]: lines[j] = add[0]
            add = []
        elif r.get('handaxis_line'):
            add = []
        if r.get('handseat_line'):
            i = r['handseat_line'] - 1
            assert lines[i].strip().startswith('handseat'), (fn, lines[i])
            lines[i] = seat
            if add: inserts.setdefault(i, []).extend(add)
        else:
            i = r['grab_line'] - 1
            assert lines[i].strip().startswith('grab'), (fn, lines[i])
            inserts.setdefault(i, []).extend([seat] + add)
    out = []
    for i, l in enumerate(lines):
        out.append(l)
        out.extend(inserts.get(i, []))
    os.makedirs(os.path.dirname(os.path.join(OUT, fn)), exist_ok=True)
    open(os.path.join(OUT, fn), 'w', newline='').write(eol.join(out))
    print('%-32s %s  %d parts' % (fn, 'CRLF' if eol == '\r\n' else 'LF', len(rs)))
