#!/usr/bin/env python3
"""Build one browsable page pairing every sweep render with 77AVEMU's.

    ./av-sweep.sh  renders 8 2000        # this core, one PNG per title
    ./ref-sweep.sh renders 6             # 77AVEMU, the same list
    ./gallery.py   renders               # -> renders/gallery.html

`results.tsv` answers "how many titles render something". It cannot answer "is
this the right picture", and that question is the one that matters: a title can
render 98% coverage in 369 colours and still be wrong, and a title can render a
flat grey screen and be exactly right (Dragon Buster's cave is grey on both
machines). Only the two images side by side settle it, and 68 of them are far
easier to judge on one page than as 136 separate files.

Two things the page does that a plain contact sheet would not:

* It compares in **palette-nibble space**. `PAL.v` expands a 4-bit gun level
  with CSP's `{n,$F}` and 77AVEMU replicates the nibble, so a byte-exact
  comparison calls every non-black pixel different and tells you nothing. Both
  keep the level in the high nibble, so `>>4` on each side makes the number mean
  something.
* It resamples to the logical grid. This core emits 640x200 always -- 320 mode
  is pixel-doubled by design -- while the reference emits 320x200 in 320 mode
  and line-doubles 640x200 into a 640x400 buffer. Comparing raw would score two
  identical pictures as completely different.

**The agreement figure is not a pass mark.** The two machines are stopped at
points chosen independently of each other (2000 frames here, 20 M instructions
there), so a title part-way through an attract sequence or a palette fade will
differ from one further along for no reason worth chasing. Use the page to find
candidates, then put both machines on the same screen before calling anything a
fault -- see docs/REFERENCE.md trap 20.

The output directory is gitignored: it changes every time a title is fixed or
the collection changes, and the PNGs are regenerable from the two sweeps.
"""
import base64
import csv
import glob
import html
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import read_png                                   # noqa: E402


def nib(p):
    return (p[0] >> 4, p[1] >> 4, p[2] >> 4)


def stats(w, h, px):
    nz = sum(1 for p in px if p[:3] != (0, 0, 0))
    return 100.0 * nz / (w * h), len(set(p[:3] for p in px))


def agreement(opx, ow, rpx, rw, rh):
    """Fraction of logical pixels whose palette nibbles match."""
    same = tot = 0
    cols = rw if rw == 320 else 640
    for y in range(200):
        for x in range(cols):
            o = opx[y * ow + (2 * x if rw == 320 else x)]
            r = rpx[(y if rh == 200 else 2 * y) * rw + x]
            tot += 1
            if nib(o) == nib(r):
                same += 1
    return 100.0 * same / tot if tot else 0.0


def collect(out):
    rates = {}
    tsv = os.path.join(out, 'results.tsv')
    if os.path.exists(tsv):
        for r in csv.reader(open(tsv), delimiter='\t'):
            if not r or r[0] == 'MAIN_PF':
                continue
            san = ''.join(c if c.isalnum() or c in '._-' else '_' for c in r[5])
            rates[san] = (int(r[0]), int(r[1]))

    cards = []
    for f in sorted(glob.glob(os.path.join(out, 'shots', '*.png'))):
        base = os.path.basename(f)
        g = os.path.join(out, 'ref-shots', base)
        if not os.path.exists(g):
            continue
        ow, oh, opx = read_png(f)
        rw, rh, rpx = read_png(g)
        ocov, ocol = stats(ow, oh, opx)
        rcov, rcol = stats(rw, rh, rpx)
        match = agreement(opx, ow, rpx, rw, rh)

        if ocov < 1 and rcov < 1:
            verdict, klass = 'both blank', 'blank'
        elif ocov < 1 <= rcov:
            verdict, klass = 'we draw nothing', 'differs'
        elif match >= 95:
            verdict, klass = 'match', 'match'
        elif match >= 75:
            verdict, klass = 'close', 'close'
        else:
            verdict, klass = 'differs', 'differs'

        m, s = rates.get(base[:-4], (0, 0))
        cards.append(dict(
            name=base[:-4].replace('_', ' ').strip(), klass=klass, verdict=verdict,
            match=match, ocov=ocov, ocol=ocol, rcov=rcov, rcol=rcol,
            mode='320x200 / 4096 colour' if rw == 320 else '640x200',
            main=m, sub=s,
            ours=base64.b64encode(open(f, 'rb').read()).decode(),
            ref=base64.b64encode(open(g, 'rb').read()).decode()))

    order = {'differs': 0, 'close': 1, 'match': 2, 'blank': 3}
    cards.sort(key=lambda c: (order[c['klass']], c['match']))
    return cards, order


CSS = '''
:root{
  --ground:#eef0f4; --surface:#fff; --ink:#0e1116; --muted:#5e6675;
  --line:#d7dbe2; --accent:#2b4fa8;
  --match:#2c7a57; --close:#8a6a16; --differs:#a63d22; --blank:#5e6675;
  --shadow:0 1px 2px rgb(14 17 22 / .06), 0 8px 24px rgb(14 17 22 / .05);
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --ground:#0f1216; --surface:#171b21; --ink:#e4e8ee; --muted:#8e97a6;
  --line:#242a33; --accent:#7ba2ff;
  --match:#5fcb98; --close:#e0b85c; --differs:#f08a66; --blank:#8e97a6;
  --shadow:0 1px 2px rgb(0 0 0 / .4), 0 8px 24px rgb(0 0 0 / .3);
}}
:root[data-theme="dark"]{
  --ground:#0f1216; --surface:#171b21; --ink:#e4e8ee; --muted:#8e97a6;
  --line:#242a33; --accent:#7ba2ff;
  --match:#5fcb98; --close:#e0b85c; --differs:#f08a66; --blank:#8e97a6;
  --shadow:0 1px 2px rgb(0 0 0 / .4), 0 8px 24px rgb(0 0 0 / .3);
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif;
  line-height:1.5; -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1180px; margin:0 auto; padding:40px 24px 72px;
      display:flex; flex-direction:column; gap:28px}
.masthead{display:flex; flex-direction:column; gap:10px}
h1{margin:0; font-size:clamp(24px,3.4vw,34px); letter-spacing:-.02em;
   font-weight:650; text-wrap:balance}
.sub{margin:0; color:var(--muted); max-width:62ch}
.rail{display:flex; gap:2px; height:5px; border-radius:3px; overflow:hidden; margin-top:2px}
.rail i{flex:1}
.tally{display:flex; flex-wrap:wrap; gap:10px}
.tally button{
  font:inherit; font-size:13px; cursor:pointer; display:flex; align-items:baseline; gap:8px;
  background:var(--surface); color:var(--ink); border:1px solid var(--line);
  border-radius:999px; padding:7px 14px;
}
.tally button[aria-pressed="true"]{border-color:var(--accent); box-shadow:inset 0 0 0 1px var(--accent)}
.tally b{font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-variant-numeric:tabular-nums}
.tally button:focus-visible{outline:2px solid var(--accent); outline-offset:2px}
.note{font-size:13.5px; color:var(--muted); border-left:2px solid var(--line);
      padding-left:14px; max-width:74ch}
.note strong{color:var(--ink); font-weight:600}
.grid{display:grid; gap:22px; grid-template-columns:repeat(auto-fill,minmax(330px,1fr))}
.card{background:var(--surface); border:1px solid var(--line); border-radius:10px;
      padding:16px; display:flex; flex-direction:column; gap:12px; box-shadow:var(--shadow)}
.card-h{display:flex; align-items:flex-start; gap:10px; justify-content:space-between}
.card h2{margin:0; font-size:13.5px; font-weight:500; letter-spacing:-.01em; word-break:break-word;
         font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.chip{flex:none; font-size:11px; letter-spacing:.06em; text-transform:uppercase;
      padding:3px 9px; border-radius:999px; border:1px solid currentColor; font-weight:600}
.chip.match{color:var(--match)} .chip.close{color:var(--close)}
.chip.differs{color:var(--differs)} .chip.blank{color:var(--blank)}
.meta{margin:0; display:grid; grid-template-columns:repeat(3,1fr); gap:10px;
      font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-variant-numeric:tabular-nums}
.meta dt{font-size:10px; letter-spacing:.04em; color:var(--muted); text-transform:uppercase}
.meta dd{margin:2px 0 0; font-size:12.5px}
.meta .big{font-size:17px; font-weight:600; letter-spacing:-.02em}
figure{margin:0; display:flex; flex-direction:column; gap:5px}
figcaption{display:flex; justify-content:space-between; gap:10px; font-size:11px;
           color:var(--muted); font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
img{width:100%; height:auto; display:block; border-radius:4px; background:#000;
    image-rendering:pixelated; aspect-ratio:16/5; object-fit:contain}
footer{color:var(--muted); font-size:13px; border-top:1px solid var(--line); padding-top:18px}
.card[hidden]{display:none}
'''

JS = '''
const btns=[...document.querySelectorAll('.tally button')];
const cards=[...document.querySelectorAll('.card')];
btns.forEach(b=>b.addEventListener('click',()=>{
  btns.forEach(o=>o.setAttribute('aria-pressed',String(o===b)));
  const k=b.dataset.f;
  cards.forEach(c=>{c.hidden = k!=='all' && c.dataset.k!==k;});
}));
'''


def card_html(c):
    return f'''<article class="card" data-k="{c['klass']}">
  <header class="card-h">
    <h2>{html.escape(c['name'])}</h2>
    <span class="chip {c['klass']}">{c['verdict']}</span>
  </header>
  <dl class="meta">
    <div><dt>pixels agreeing</dt><dd class="big">{c['match']:.1f}%</dd></div>
    <div><dt>mode</dt><dd>{c['mode']}</dd></div>
    <div><dt>main / sub per frame</dt><dd>{c['main']} / {c['sub']}</dd></div>
  </dl>
  <figure>
    <figcaption>this core <span>{c['ocov']:.0f}% covered · {c['ocol']} colours</span></figcaption>
    <img alt="this core rendering {html.escape(c['name'])}" src="data:image/png;base64,{c['ours']}">
  </figure>
  <figure>
    <figcaption>77AVEMU <span>{c['rcov']:.0f}% covered · {c['rcol']} colours</span></figcaption>
    <img alt="77AVEMU rendering {html.escape(c['name'])}" src="data:image/png;base64,{c['ref']}">
  </figure>
</article>'''


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    out = sys.argv[1]
    cards, order = collect(out)
    if not cards:
        print(f"no paired shots under {out}/shots and {out}/ref-shots", file=sys.stderr)
        return 1
    counts = {k: sum(1 for c in cards if c['klass'] == k) for k in order}

    labels = [('all', 'all titles', len(cards)), ('differs', 'differs', counts['differs']),
              ('close', 'close', counts['close']), ('match', 'match', counts['match']),
              ('blank', 'blank on both', counts['blank'])]
    tally = '\n'.join(
        f'<button data-f="{k}" aria-pressed="{"true" if k == "all" else "false"}">'
        f'{l} <b>{n}</b></button>' for k, l, n in labels)
    rail = '\n'.join(f'<i style="flex:{max(counts[k], 1)};background:var(--{k})"></i>'
                     for k in ('differs', 'close', 'match', 'blank'))

    page = f'''<title>FM77AV Render Diff</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>{CSS}</style>
<div class="wrap">
  <header class="masthead">
    <h1>FM77AV renders, this core against 77AVEMU</h1>
    <p class="sub">Every FM77AV title in the collection, rendered by this core at 2000 frames and
    by 77AVEMU at 20 M instructions, paired so the two can be compared directly.</p>
    <div class="rail">{rail}</div>
  </header>
  <nav class="tally">{tally}</nav>
  <p class="note"><strong>Read “pixels agreeing” with care.</strong> It compares the two images in
  palette-nibble space, which cancels the two emulators’ different 4-bit-to-8-bit DAC expansions.
  A low figure means the two pictures differ — it does <em>not</em> by itself mean this core is
  wrong, because the machines are stopped at points chosen independently and a title part-way
  through an attract sequence or a palette fade will legitimately differ from one further along.
  Confirm on the same screen before calling anything a fault.</p>
  <div class="grid">
{chr(10).join(card_html(c) for c in cards)}
  </div>
  <footer>{len(cards)} titles paired · this core at 2000 frames · 77AVEMU at 20,000,000
  instructions · sorted least-agreeing first</footer>
</div>
<script>{JS}</script>'''

    dest = os.path.join(out, 'gallery.html')
    open(dest, 'w').write(page)
    print(f"{len(cards)} titles -> {dest} "
          f"({os.path.getsize(dest) // 1024} KB): "
          + ', '.join(f"{k} {counts[k]}" for k in order))
    return 0


if __name__ == '__main__':
    sys.exit(main())
