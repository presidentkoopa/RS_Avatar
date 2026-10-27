"""Every part of every live card: role, subject, surfaces or joint, grab, handseat, dof, with line numbers."""
import re, json, os, sys
import config
ROOT=str(config.WEAPONS)
FILES=['WMCARD.01_pistol','WMCARD.02_pump','WMCARD.03_revolver_breaktop','WMCARD.04_revolver_swingout','WMCARD.05_rifle','WMCARD.06_breakaction','WMCARD.07_smg','WMCARD.08_cell','WMCARD.09_chaingun','WMCARD.10_launcher','WMCARD.11_bfg','WMCARD.12_chainsaw','WMCARD.13_flamethrower','WMCARD.14_magazine_shotgun','WMCARD.grenade','bd22/WMCARD.bd22','RS_Modern/WMCARD.breach','RS_Modern/WMCARD.breach_set']
def vec(s): return [float(x) for x in s.split('#')[0].split(',')]
CLS={}; BAR={}; BASE={}
def parse():
    out=[]
    for fn in FILES:
        lines=open(os.path.join(ROOT,fn),encoding='utf-8',newline='').read().replace('\r\n','\n').split('\n')
        gun=None; arche=None; part=None; depth=0; gtype=None; gclass=None
        for i,raw in enumerate(lines,1):
            l=raw.split('#')[0].strip()
            if not l: continue
            m=re.match(r'^weapon\s+"([^"]+)"',l)
            if m: gun=m.group(1); gtype=None; continue
            m=re.match(r'^archetype\s+"?([^"\s]+)',l)
            if m and part is None and gun is None: arche=m.group(1)
            if part is None:
                m=re.match(r'^type\s*=\s*(\S+)',l)
                if m and gun: gtype=m.group(1)
                m=re.match(r'^class\s*=\s*(\S+)',l)
                if m and gun: gclass=m.group(1); CLS[gun]=gclass
                m=re.match(r'^barrel\s*=\s*(.*)$',l)
                if m and gun: BAR[gun]=vec(m.group(1))
                m=re.match(r'^base\s*=\s*(\S+)',l)
                if m and gun: BASE[gun]=m.group(1)
                m=re.match(r'^part\s+(\S+)',l)
                if m and gun:
                    part=dict(file=fn,gun=gun,type=gtype,id=m.group(1),line=i,surfaces=[],dof={}); depth=1; continue
            else:
                if l in ('dof','dof2','index'):
                    depth+=1; part['_in']=l; continue
                if l=='end':
                    depth-=1
                    if depth==0: out.append(part); part=None
                    else: part.pop('_in',None)
                    continue
                m=re.match(r'^(\w+)\s*=\s*(.*)$',l)
                if not m: continue
                k,v=m.group(1),m.group(2).strip()
                if part.get('_in')=='dof': part['dof'][k]=v; continue
                if part.get('_in'): continue
                if k=='surface' or k=='surfaces': part['surfaces']+= [x.strip() for x in v.split(',')]
                elif k in ('grab','handseat','handaxis'): part[k]=vec(v); part[k+'_line']=i
                else: part[k]=v
    return out
if __name__=='__main__':
    P=parse()
    sel=[p for p in P if p.get('role')=='action' or p.get('subject') in ('slide','forend','foregrip')]
    print(len(P),'parts;',len(sel),'action/forend/foregrip')
    for p in sel: print('%-22s %-12s %-8s %-8s %-10s grab=%s seat=%s surf=%s joint=%s dof=%s' % (p['gun'],p['id'],p.get('role'),p.get('subject'),p.get('type'),p.get('grab'),p.get('handseat'),p['surfaces'],p.get('joint'),p['dof'].get('kind')))
    json.dump(P,open(str(config.OUT / 'parts.json'),'w'),indent=1)
