# Synthetic check of the corrector: ports Autocorrect.swift's scoring and the key geometry,
# types 1500 one-key slips per language and reports fixes / wrong fixes / false positives.
# Usage: python3 autocorrect-sim.py ru 0.25 0.20   (language, thumb scatter x/y in key pitches)
import math, random, struct, sys, collections
random.seed(7)
import os
RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Keyboard", "Resources") + "/"
LANG = sys.argv[1] if len(sys.argv) > 1 else "ru"

# ---------- dictionary (port of Autocorrect.Dictionary) ----------
words, freq = [], {}
for line in open(RES + f"freq_{LANG}.txt", encoding="utf8"):
    p = line.rstrip("\n").split(" ", 1)
    if len(p) == 2 and p[1].isdigit():
        words.append(p[0]); freq[p[0]] = int(p[1])
ids = {w: i for i, w in enumerate(words)}
total = float(sum(freq.values()))
sorted_words = sorted(freq)
data = open(RES + f"bigrams_{LANG}.bin", "rb").read()
assert data[:4] == b"SKBG"
v, n = struct.unpack_from("<II", data, 4)
assert v == len(words)
prevTotals = list(struct.unpack_from(f"<{v}I", data, 12))
bigrams = {}
o = 12 + v * 4
for _ in range(n):
    p, w, c = struct.unpack_from("<III", data, o); o += 12
    bigrams[(p, w)] = c

def pUni(w): return freq.get(w, 0) / total
def prob(w, prev):
    uni = pUni(w)
    if prev is None: return uni
    pi = ids.get(prev.lower()); wi = ids.get(w)
    if pi is None or wi is None or prevTotals[pi] < 20: return uni
    return 0.75 * bigrams.get((pi, wi), 0) / prevTotals[pi] + 0.25 * uni

# ---------- layout & geometry (KeyboardMetrics.portrait, iPhone 17 Pro 402pt) ----------
LAYOUTS = {
 "ru": [list("йцукенгшщзх"), list("фывапролджэ"), list("ячсмитьбю")],
 "uk": [list("йцукенгшщзхї"), list("фівапролджє'"), list("ячсмитьбюґ")],
 "en": [list("qwertyuiop"), list("asdfghjkl"), list("zxcvbnm")],
}
rows = LAYOUTS[LANG]
GAP, ROWGAP, H, SIDE, W_SCREEN = 7, 12, 42, 6, 402
width = W_SCREEN - 2 * SIDE
widest = max(len(r) for r in rows)
u = (width - GAP * (widest - 1)) / widest
frames = {}
for r, row in enumerate(rows):
    nchars = len(row)
    if r == 2:  # shift + chars + backspace
        specials = 2
        minSpecial = u * (1.25 if widest <= 10 else 1.0)
        gaps = GAP * (nchars + specials - 1)
        leftover = (width - nchars * u - gaps) / specials
        sw = max(minSpecial, leftover)
        cw = min(u, (width - specials * sw - gaps) / nchars)
        x = SIDE + sw + GAP
    else:
        cw = u; x = SIDE
    y = r * (H + ROWGAP)
    for ch in row:
        frames[ch] = (x, y, cw, H); x += cw + GAP
KW = u
PITCH_X, PITCH_Y = u + GAP, H + ROWGAP

def center(ch):
    x, y, w, h = frames[ch]; return (x + w / 2, y + h / 2)
def contains(f, p):
    x, y, w, h = f; return x <= p[0] <= x + w and y <= p[1] <= y + h

# port of KeyTouchUIView.proximity(at:)
def proximity(p):
    out = {}
    for ch, (x, y, w, h) in frames.items():
        dx = (p[0] - (x + w / 2)) / KW; dy = (p[1] - (y + h / 2)) / (h * 1.15)
        d = math.hypot(dx, dy)
        if d < 1.4: out[ch] = max(0.0, 1 - d / 1.4)
    return out

# port of KeyTouchUIView.key(at:)
def key_at(p, bias=None):
    expanded = None
    if bias:
        for ch, f in frames.items():
            b = bias.get(ch, 0)
            if b <= 0.15: continue
            x, y, w, h = f
            grown = (x - 6 * b, y - 4 * b, w + 12 * b, h + 8 * b)
            if contains(grown, p) and (expanded is None or b > expanded[1]): expanded = (ch, b)
    exact = next((ch for ch, f in frames.items() if contains(f, p)), None)
    if expanded:
        k, b = expanded
        if exact and exact != k:
            x, y, w, h = frames[exact]
            if contains((x + 6 * b, y + 4 * b, w - 12 * b, h - 8 * b), p): return exact
        return k
    if exact: return exact
    best = None
    for ch, (x, y, w, h) in frames.items():
        dx = max(x - p[0], 0, p[0] - (x + w)); dy = max(y - p[1], 0, p[1] - (y + h))
        d = dx * dx + dy * dy
        if d <= 64 and (best is None or d < best[1]): best = (ch, d)
    return best[0] if best else None

# ---------- adjacency & alphabet (port) ----------
adj = {}
for r, row in enumerate(rows):
    for c, ch in enumerate(row):
        s = set()
        for dc in (-1, 1):
            if 0 <= c + dc < len(row): s.add(row[c + dc])
        for dr in (-1, 1):
            if 0 <= r + dr < len(rows):
                other = rows[r + dr]; shift = -1 if len(other) < len(row) else 0
                for dc in (0, 1):
                    j = c + dc + shift
                    if 0 <= j < len(other): s.add(other[j])
        adj[ch] = s
alphabet = sorted(set(ch for row in rows for ch in row) | {"'"} | ({"ё", "ъ"} if LANG == "ru" else set()))

# ---------- edits1 (port) + an alternative error model ----------
def edits1(w, narrow=False, touches=None, model="current"):
    chars = list(w); out = []
    for i in range(len(chars) + 1):
        if i < len(chars):
            d = chars[:i] + chars[i + 1:]
            out.append(("".join(d), 1.0 if model == "current" else 0.12))
        if i < len(chars) - 1:
            t = chars[:]; t[i], t[i + 1] = t[i + 1], t[i]
            out.append(("".join(t), 2.0 if model == "current" else 0.05))
        if narrow:
            letters = set()
            if i < len(chars): letters |= adj.get(chars[i], set())
            if i > 0: letters |= adj.get(chars[i - 1], set())
        else:
            letters = alphabet
        for c in letters:
            if i < len(chars) and c != chars[i]:
                s = chars[:]; s[i] = c
                if model == "current":
                    if touches is not None and i < len(touches):
                        wgt = 0.3 + 2.7 * touches[i].get(c, 0)
                    else:
                        wgt = 3.0 if c in adj.get(chars[i], set()) else 0.7
                else:
                    # Gaussian touch likelihood ratio: P(point | c) / P(point | typed)
                    if touches is not None and i < len(touches) and touches[i]:
                        pt = touches[i]["_pt"]
                        def g(ch):
                            if ch not in frames: return 1e-6
                            cx, cy = center(ch)
                            dx = (pt[0] - cx) / PITCH_X; dy = (pt[1] - cy) / PITCH_Y
                            return math.exp(-(dx * dx + dy * dy) / (2 * 0.45 ** 2))
                        wgt = max(1e-3, min(1.0, g(c) / max(g(chars[i]), 1e-9)))
                    else:
                        wgt = 0.5 if c in adj.get(chars[i], set()) else 0.01
                out.append(("".join(s), wgt))
            ins = chars[:i] + [c] + chars[i:]
            if model == "current":
                out.append(("".join(ins), 1.0))
            else:
                near = (i < len(chars) and c in adj.get(chars[i], set())) or (i > 0 and c in adj.get(chars[i - 1], set()))
                out.append(("".join(ins), 0.12 if near else 0.02))
    return out

# ---------- correction (port of Autocorrect.correction, minus UITextChecker) ----------
def correction(word, prev, touches=None, model="current"):
    lower = word.lower()
    if len(word) < 3: return None
    known = lower in freq
    if model == "current":
        if known and (freq[lower] >= 300 or len(word) < 4): return None
    else:
        # shipped rules: corpus-relative thresholds; a known word is only touched when rare
        # (the system checker's verdict is not modelled here — it would protect more words)
        if known and (pUni(lower) >= 2.1e-6 or len(word) < 4): return None
    best = None
    def consider(cand, wgt):
        nonlocal best
        if cand not in freq: return
        s = prob(cand, prev) * wgt
        if best is None or s > best[1]: best = (cand, s)
    tm = touches if (touches is not None and len(touches) == len(lower)) else None
    for cand, wgt in edits1(lower, touches=tm, model=model): consider(cand, wgt)
    if best is None and not known and len(lower) >= 5:
        seen = set()
        for e1, w1 in edits1(lower, touches=tm, model=model):
            for e2, w2 in edits1(e1, narrow=True, model=model):
                if e2 in seen: continue
                seen.add(e2); consider(e2, w1 * w2 * 0.05)
    if best is None or best[0] == lower: return None
    if model == "current":
        if freq[best[0]] < 30: return None
        if known and not best[1] > prob(lower, prev) * 40: return None
    else:
        if pUni(best[0]) < 2.1e-7: return None
        if known and not best[1] > prob(lower, prev) * 10: return None
    return best[0]

# ---------- nextLetterDistribution (port) ----------
import bisect
def next_letter_distribution(prefix, prev):
    acc = collections.Counter()
    lower = prefix.lower()
    if not lower:
        return {}  # start of word without prev: nothing (prev case handled separately)
    i = bisect.bisect_left(sorted_words, lower); scanned = 0
    while i < len(sorted_words) and sorted_words[i].startswith(lower) and scanned < 600:
        w = sorted_words[i]
        if len(w) > len(lower): acc[w[len(lower)]] += freq.get(w, 0)
        i += 1; scanned += 1
    if not acc: return {}
    top = max(acc.values())
    return {c: v / top for c, v in acc.items()}

EX_A, EX_D = [], []
# ---------- simulation ----------
SIG_X, SIG_Y = float(sys.argv[2]) * PITCH_X, float(sys.argv[3]) * PITCH_Y   # thumb scatter (guess, documented in report)
def tap(ch):
    cx, cy = center(ch)
    return (random.gauss(cx, SIG_X), random.gauss(cy, SIG_Y))

letters_ok = set(ch for row in rows for ch in row)
cands = [w for w in words[300:30000] if 4 <= len(w) <= 10 and set(w) <= letters_ok]
random.shuffle(cands)

def simulate_word(w, force_error=True):
    """Type w with scattered taps. Returns (typed, touches, err_pos) or None."""
    for _ in range(50):
        typed, touches, errs = [], [], []
        for i, ch in enumerate(w):
            p = tap(ch); k = key_at(p)
            if k is None: k = ch  # off-keyboard tap: assume it registered on the key
            typed.append(k); pr = proximity(p); pr["_pt"] = p; touches.append(pr)
            if k != ch: errs.append(i)
        if force_error and len(errs) == 1: return "".join(typed), touches, errs
        if not force_error and len(errs) == 0: return "".join(typed), touches, errs
    return None

def prev_for(w):
    # a plausible previous word: a random frequent word that actually has bigram context
    return random.choice(words[:2000])

def run_A(model, N=1500, use_prev=False):
    res = collections.Counter()
    for w in cands[:N]:
        s = simulate_word(w, True)
        if s is None: continue
        typed, touches, errs = s
        if typed in freq and freq[typed] >= 300: res["typo is a common word"] += 1; continue
        prev = prev_for(w) if use_prev else None
        c = correction(typed, prev, touches, model)
        if c == w: res["fixed"] += 1
        elif c is None: res["left as typed"] += 1
        else:
            res["WRONG fix"] += 1
            if len(EX_A) < 8 and model == "current" and not use_prev: EX_A.append(f"{w} → typed {typed} → fixed to {c}")
    return res

def run_D(model, N=1500, use_prev=False):
    """Correctly typed rare-ish words (count < 300): how often are they replaced?"""
    rare = [w for w in words[30000:] if 4 <= len(w) <= 10 and set(w) <= letters_ok and freq[w] < 300]
    random.shuffle(rare)
    res = collections.Counter()
    for w in rare[:N]:
        s = simulate_word(w, False)
        if s is None: continue
        typed, touches, _ = s
        prev = prev_for(w) if use_prev else None
        c = correction(typed, prev, touches, model)
        res["replaced (false positive)" if c else "kept"] += 1
        if c and len(EX_D) < 8 and model == "current" and not use_prev: EX_D.append(f"{w} (count {freq[w]}) → replaced by {c} (count {freq[c]})")
    return res

def run_C(N=20000):
    """Taps that land inside the intended key: how often does the dynamic hit target steal them?"""
    stolen = inside = 0; stolen_nobias = 0
    for w in cands[:4000]:
        for i in range(1, len(w)):
            bias = next_letter_distribution(w[:i], None)
            p = tap(w[i])
            if not contains(frames[w[i]], p): continue
            inside += 1
            if key_at(p, bias) != w[i]: stolen += 1
            if inside >= N: break
        if inside >= N: break
    # gap taps: nearest-key rule vs biased rule
    gap_total = gap_changed = gap_worse = 0
    for w in cands[4000:8000]:
        for i in range(1, len(w)):
            bias = next_letter_distribution(w[:i], None)
            p = tap(w[i])
            k0 = key_at(p); k1 = key_at(p, bias)
            if k0 is None or contains(frames[w[i]], p): continue
            gap_total += 1
            if k0 != k1:
                gap_changed += 1
                if k0 == w[i] and k1 != w[i]: gap_worse += 1
                if k1 == w[i] and k0 != w[i]: gap_worse -= 1
    return inside, stolen, gap_total, gap_changed, gap_worse

# proximity numbers for the report
K1, K2 = ("н","г") if LANG != "en" else ("h","j")
c_n = center(K1); c_g = center(K2)
print(f"[{LANG}] key width {KW:.1f}pt, pitch x {PITCH_X:.1f} y {PITCH_Y:.1f}")
pr = proximity(c_n)
print("finger at centre of н: prox(г, right neighbour) = %.2f -> weight %.2f; prox(р, below) = %.2f -> weight %.2f" %
      (pr.get(K2, 0), 0.3 + 2.7 * pr.get(K2, 0), pr.get("р" if LANG != "en" else "n", 0), 0.3 + 2.7 * pr.get("р" if LANG != "en" else "n", 0)))
mid = ((c_n[0] + c_g[0]) / 2, c_n[1])
pr = proximity(mid)
print("finger on the н|г boundary: prox(г) = %.2f -> weight %.2f   (deletion 1.0, insertion of ANY letter 1.0, transposition 2.0)" %
      (pr.get(K2, 0), 0.3 + 2.7 * pr.get(K2, 0)))

# natural per-key error rate with this scatter
errs = keys = 0
for w in cands[:2000]:
    for ch in w:
        keys += 1
        if key_at(tap(ch)) != ch: errs += 1
print(f"simulated per-key miss rate with this scatter: {100*errs/keys:.1f}%")

for model in ("current", "gaussian"):
    for use_prev in (False, True):
        a = run_A(model, use_prev=use_prev)
        tot = sum(a.values())
        print(f"A  {model:8s} prev={'yes' if use_prev else 'no '}  one fat-finger sub, N={tot}: " +
              ", ".join(f"{k} {100*v/tot:.0f}%" for k, v in sorted(a.items())))
for model in ("current", "gaussian"):
    for use_prev in (False, True):
        d = run_D(model, use_prev=use_prev)
        tot = sum(d.values())
        print(f"D  {model:8s} prev={'yes' if use_prev else 'no '}  correctly typed rare word, N={tot}: " +
              ", ".join(f"{k} {100*v/tot:.1f}%" for k, v in sorted(d.items())))
inside, stolen, gt, gc, gw = run_C()
print(f"C  dynamic hit targets: taps inside intended key {inside}, stolen by bias {stolen} ({100*stolen/inside:.2f}%); "
      f"gap taps {gt}, reassigned {gc}, net worse {gw}")

print("examples of WRONG fixes (current):"); [print("   ", e) for e in EX_A]
print("examples of false positives (current):"); [print("   ", e) for e in EX_D]
for rank in (300, 1000, 3000, 8000, 20000, 30000, 49000):
    if rank < len(words): print(f"   rank {rank}: {words[rank]} count {freq[words[rank]]}")
n300 = sum(1 for w in words if freq[w] >= 300)
print(f"   words with count >= 300 (treated as 'known, leave alone'): {n300} of {len(words)}")

print(f"   total tokens in list: {total:,.0f}; count>=30 covers ranks up to {sum(1 for w in words if freq[w] >= 30)}")
if LANG == "uk":
    ru_only = sum(1 for w in words[:5000] if set(w) & set("ыэъё"))
    print(f"   uk list: {ru_only} of the top 5000 entries contain Russian-only letters (ы э ъ ё)")
    # D on the mid band: ranks 1564..30000 (eligible for override in uk, not in ru)
    mid = [w for w in words[1600:30000] if 4 <= len(w) <= 10 and set(w) <= letters_ok and freq[w] < 300]
    random.shuffle(mid); res = collections.Counter(); ex = []
    for w in mid[:1500]:
        sres = simulate_word(w, False)
        if sres is None: continue
        typed, touches, _ = sres
        c = correction(typed, prev_for(w), touches, "current")
        res["replaced" if c else "kept"] += 1
        if c and len(ex) < 6: ex.append(f"{w} ({freq[w]}) → {c} ({freq[c]})")
    tot = sum(res.values())
    print(f"   D-mid uk (ranks 1600-30000, correctly typed, with prev): replaced {100*res['replaced']/tot:.1f}%  e.g. " + "; ".join(ex))
    # why 'left as typed': is it the f>=30 gate?
    left = gate = 0
    for w in cands[:800]:
        sres = simulate_word(w, True)
        if sres is None: continue
        typed, touches, _ = sres
        if correction(typed, None, touches, "current") is None:
            left += 1
            if freq[w] < 30: gate += 1
    print(f"   uk 'left as typed' {left}: target word had count < 30 in {gate} cases")
