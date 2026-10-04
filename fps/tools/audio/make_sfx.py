"""Istanbul-Z ses paketi uretici (GELISTIRME ARACI; yalniz numpy).

    python fps/tools/audio/make_sfx.py            # fps/assets/audio/<kimlik>[_n].wav yazar

Oyun calisirken sentez yapilmaz: bu arac bir kez calisir, 44.1 kHz 16 bit
mono WAV dosyalari uretir (3B konumlandirma icin mono). Sfx, <kimlik>.wav ya
da <kimlik>_1.wav, _2.wav... varyantlarini bulur ve her calista rastgele
birini secer (ayni ses art arda ayni duyulmaz).

Teknikler: katmanli sentez (gecis darbesi + govde + kuyruk), frekans
alaninda suzgec, modal rezonator (malzeme tinisi), formant sentezi (zombi
sesleri: girtlak darbe dizisi + zamanla degisen gircak formantlari + vokal
kizarma), sokak/oda yankisi (sentetik darbe yaniti ile evrisim), yumusak
doyum (tanh). Tohum sabit: ayni surum ayni sesleri uretir.
"""
from __future__ import annotations

import os
import struct
import zlib

import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio"))
RNG = np.random.default_rng(20260930)


# ---------------------------------------------------------------------------
# Temel yapi taslari
# ---------------------------------------------------------------------------
def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return RNG.uniform(-1.0, 1.0, int(sec * SR))


def fft_filter(x, gain_fn):
    n = len(x)
    size = 1 << int(np.ceil(np.log2(max(2, n))))
    spec = np.fft.rfft(x, size)
    freqs = np.fft.rfftfreq(size, 1.0 / SR)
    return np.fft.irfft(spec * gain_fn(freqs), size)[:n]


def lowpass(x, fc, order=2):
    return fft_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return fft_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, fc, q=2.0):
    bw = fc / q
    return fft_filter(x, lambda f: np.exp(-0.5 * ((f - fc) / bw) ** 2))


def env_exp(sec, decay, attack=0.001):
    t = t_axis(sec)
    a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    return a * np.exp(-t / decay)


def pad(x, sec):
    n = int(sec * SR)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def reverb(x, decay=0.9, wet=0.25, tone=4000.0, predelay=0.012, size=1.0):
    """Sentetik darbe yaniti: erken yansimalar + ustel sonumlu suzulmus gurultu."""
    length = decay * 1.6
    ir = noise(length) * np.exp(-t_axis(length) / (decay / 6.9))
    ir = lowpass(ir, tone, 1)
    for k in range(6):
        d = int((predelay + 0.006 * k * size + RNG.uniform(0, 0.01)) * SR)
        if d < len(ir):
            ir[d] += RNG.uniform(0.3, 0.8) * (0.8 ** k)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + len(ir)
    size_fft = 1 << int(np.ceil(np.log2(n)))
    wet_sig = np.fft.irfft(np.fft.rfft(x, size_fft) * np.fft.rfft(ir, size_fft), size_fft)[:n]
    out = np.zeros(n)
    out[:len(x)] += x * (1.0 - wet * 0.5)
    out += wet_sig * wet
    return out


def modal(sec, modes, strike=0.002):
    """Modal rezonator: [(hz, sonum sn, genlik)] -- metal, tahta, cam tinisi."""
    t = t_axis(sec)
    out = np.zeros_like(t)
    for hz, decay, amp in modes:
        ph = RNG.uniform(0, 2 * np.pi)
        out += amp * np.sin(2 * np.pi * hz * t + ph) * np.exp(-t / decay)
    return out * np.clip(t / strike, 0, 1)


def glide(sec, f0, f1, curve=3.0):
    t = t_axis(sec)
    f = f1 + (f0 - f1) * np.exp(-t * curve / max(sec, 1e-3))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def saturate(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def fade_out(x, sec=0.02):
    n = min(len(x), int(sec * SR))
    if n > 0:
        x = x.copy()
        x[-n:] *= np.linspace(1, 0, n)
    return x


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def trim_silence(x, thresh=0.0015):
    idx = np.flatnonzero(np.abs(x) > thresh * np.max(np.abs(x) + 1e-9))
    if idx.size == 0:
        return x
    return x[: min(len(x), idx[-1] + int(0.01 * SR))]


def write_wav(name, x, peak=0.89):
    x = fade_out(trim_silence(normalize(x, peak)))
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    path = os.path.join(OUT, name + ".wav")
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(data)) + data)


# ---------------------------------------------------------------------------
# Silahlar
# ---------------------------------------------------------------------------
def gunshot(body_hz, body_decay, crack_fc, tail, weight, mech=True, suppressed=False):
    sec = tail + 0.5
    # 1) Namlu agzi catlamasi: cok kisa, genis bantli, yuksek gecis.
    crack = highpass(noise(0.03), crack_fc) * env_exp(0.03, 0.004, 0.0002)
    # 2) Govde: frekansi dusen alcak "gum" (barut gazi genlesmesi).
    boom = glide(0.5, body_hz * 2.4, body_hz, 6.0) * env_exp(0.5, body_decay, 0.0008)
    thump = lowpass(noise(0.5), body_hz * 6) * env_exp(0.5, body_decay * 0.6, 0.0005)
    # 3) Orta bant patlama.
    blast = bandpass(noise(0.25), 900 + crack_fc * 0.1, 1.2) * env_exp(0.25, 0.025, 0.0003)
    parts = [crack * 1.4, boom * 0.9 * weight, thump * 1.1 * weight, blast * 0.8]
    if mech:
        # 4) Surgu/mekanizma tikirtisi (birkac ms sonra).
        clack = modal(0.08, [(2100, 0.012, 0.6), (3500, 0.008, 0.4), (5200, 0.005, 0.3)])
        parts.append(np.concatenate([np.zeros(int(0.035 * SR)), clack * 0.25]))
    dry = mix(*parts)
    if suppressed:
        dry = mix(lowpass(dry, 2200, 2) * 0.6, highpass(noise(0.05), 3000) * env_exp(0.05, 0.006) * 0.2)
    dry = saturate(dry, 2.2)
    # 5) Sokak yankisi: binalardan geri donen uzun kuyruk.
    wet = reverb(pad(dry, sec), decay=tail, wet=0.55 if not suppressed else 0.25, tone=3200, predelay=0.02, size=2.0)
    return wet


def shell_eject():
    t = 0.35
    x = np.zeros(int(t * SR))
    for k, (dt, amp) in enumerate([(0.0, 1.0), (0.09, 0.5), (0.16, 0.3), (0.21, 0.15)]):
        ping = modal(0.1, [(4800 + RNG.uniform(-300, 300), 0.03, 0.6), (7200, 0.02, 0.4), (9800, 0.012, 0.3)])
        s = int(dt * SR)
        x[s:s + len(ping)] += ping[: len(x) - s] * amp
    return x


# ---------------------------------------------------------------------------
# Zombi sesleri (formant sentezi)
# ---------------------------------------------------------------------------
VOWELS = {  # (F1, F2, F3) Hz -- bogazdan gelen "a/o/u/e" renkleri
    "a": (750, 1150, 2500), "o": (520, 900, 2400), "u": (380, 850, 2300), "e": (520, 1700, 2500),
    "ae": (660, 1500, 2450),
}


def voice(sec, f0_curve, vowel_seq, fry=0.6, breath=0.35, rough=0.25):
    """Gircak sentezi: jitter'li testere girtlak kaynagi -> zamanla degisen
    formantlar (STFT kare kare), vokal kizarma (dusuk frekans AM), nefes gurultusu."""
    t = t_axis(sec)
    n = len(t)
    f0 = f0_curve(t)
    f0 = f0 * (1.0 + rough * 0.03 * np.cumsum(RNG.normal(0, 1, n)) / np.sqrt(SR) * 40)
    phase = np.cumsum(f0) / SR
    saw = 2.0 * (phase % 1.0) - 1.0
    source = saw * (1.0 + fry * np.sin(2 * np.pi * 38 * t + np.sin(2 * np.pi * 7 * t)))
    source += breath * noise(sec)
    # STFT ile zamanla degisen formant suzgeci
    frame = 1024
    hop = 256
    win = np.hanning(frame)
    out = np.zeros(n + frame)
    norm = np.zeros(n + frame)
    freqs = np.fft.rfftfreq(frame, 1.0 / SR)
    keys = list(vowel_seq)
    for start in range(0, n, hop):
        seg = source[start:start + frame]
        if len(seg) < frame:
            seg = np.pad(seg, (0, frame - len(seg)))
        pos = start / max(1, n - 1) * (len(keys) - 1)
        i0 = int(np.floor(pos))
        i1 = min(len(keys) - 1, i0 + 1)
        w = pos - i0
        fa = np.array(VOWELS[keys[i0]])
        fb = np.array(VOWELS[keys[i1]])
        fm = fa * (1 - w) + fb * w
        gain = np.zeros_like(freqs)
        for k, (fc, bw, amp) in enumerate(zip(fm, (90, 130, 180), (1.0, 0.6, 0.3))):
            gain += amp * np.exp(-0.5 * ((freqs - fc) / bw) ** 2)
        gain += 0.04
        spec = np.fft.rfft(seg * win) * gain
        out[start:start + frame] += np.fft.irfft(spec, frame) * win
        norm[start:start + frame] += win ** 2
    out = out[:n] / np.maximum(norm[:n], 1e-3)
    e = np.sin(np.pi * np.clip(t / sec, 0, 1)) ** 0.6
    return saturate(out * e, 1.8)


def zombie(kind, variant):
    r = RNG.uniform(0.85, 1.15)
    if kind == "groan":
        sec = RNG.uniform(1.1, 1.7)
        f = lambda t: (78 + 18 * np.sin(2 * np.pi * 0.8 * t)) * r
        seq = RNG.choice(["uo", "ou", "ua", "aou"])
        x = voice(sec, f, seq, fry=0.9, breath=0.3)
        return reverb(x, 0.7, 0.3, 3000)
    if kind == "alert":
        sec = RNG.uniform(0.6, 0.9)
        f = lambda t: (120 + 90 * np.exp(-((t - 0.15) / 0.12) ** 2)) * r
        x = voice(sec, f, RNG.choice(["ae", "ea", "oa"]), fry=0.7, breath=0.45, rough=0.5)
        return reverb(x, 0.8, 0.3, 3500)
    if kind == "attack":
        sec = RNG.uniform(0.3, 0.45)
        f = lambda t: (170 - 60 * t / sec) * r
        x = voice(sec, f, RNG.choice(["ae", "a"]), fry=1.0, breath=0.6, rough=0.8)
        snap = highpass(noise(0.05), 1500) * env_exp(0.05, 0.01) * 0.6
        return reverb(mix(x, snap), 0.5, 0.2, 4000)
    if kind == "death":
        sec = RNG.uniform(0.9, 1.3)
        f = lambda t: (110 * np.exp(-t * 1.4) + 45) * r
        x = voice(sec, f, RNG.choice(["ou", "au", "ao"]), fry=1.2, breath=0.5)
        fall = lowpass(noise(0.3), 400) * env_exp(0.3, 0.06) * 0.8
        fall = np.concatenate([np.zeros(int(sec * 0.75 * SR)), fall])
        return reverb(mix(x, fall), 0.8, 0.3, 3000)
    if kind == "scream":
        sec = RNG.uniform(1.1, 1.5)
        f = lambda t: (330 + 120 * np.sin(2 * np.pi * 1.3 * t) + 60 * np.sin(2 * np.pi * 9 * t)) * r
        x = voice(sec, f, RNG.choice(["ae", "aea", "e"]), fry=0.35, breath=0.5, rough=1.0)
        return reverb(x, 1.6, 0.45, 4500, size=2.5)
    raise ValueError(kind)


# ---------------------------------------------------------------------------
# Darbeler, adimlar, yikim
# ---------------------------------------------------------------------------
def impact(material):
    if material == "wood":
        m = modal(0.25, [(RNG.uniform(180, 240), 0.05, 1.0), (RNG.uniform(420, 520), 0.035, 0.6),
                         (RNG.uniform(900, 1100), 0.02, 0.35)])
        n = bandpass(noise(0.12), 1200, 1.0) * env_exp(0.12, 0.012)
        return reverb(mix(m, n * 0.6), 0.35, 0.15, 3000)
    if material == "stone":
        n = bandpass(noise(0.2), RNG.uniform(1500, 2400), 0.8) * env_exp(0.2, 0.02, 0.0003)
        grit = highpass(noise(0.15), 3000) * env_exp(0.15, 0.04) * (RNG.random(int(0.15 * SR)) < 0.06)
        body = lowpass(noise(0.2), 300) * env_exp(0.2, 0.03)
        return reverb(mix(n, grit * 0.8, body * 0.7), 0.4, 0.18, 3500)
    if material == "metal":
        base = RNG.uniform(700, 1100)
        m = modal(0.9, [(base, 0.35, 1.0), (base * 2.76, 0.22, 0.6), (base * 5.4, 0.12, 0.4), (base * 8.9, 0.06, 0.25)])
        clank = highpass(noise(0.03), 2000) * env_exp(0.03, 0.004)
        return reverb(mix(m * 0.7, clank), 0.5, 0.2, 5000)
    if material == "glass":
        pings = np.zeros(int(0.4 * SR))
        for _ in range(8):
            p = modal(0.2, [(RNG.uniform(3000, 7000), RNG.uniform(0.02, 0.07), 1.0)])
            s = int(RNG.uniform(0, 0.15) * SR)
            pings[s:s + len(p)] += p[: len(pings) - s] * RNG.uniform(0.2, 0.6)
        hit = highpass(noise(0.05), 2500) * env_exp(0.05, 0.008)
        return reverb(mix(hit, pings), 0.4, 0.2, 7000)
    if material == "dirt":
        return lowpass(noise(0.15), 500) * env_exp(0.15, 0.025) + lowpass(noise(0.15), 2500) * env_exp(0.15, 0.01) * 0.3
    if material == "flesh":
        thud = lowpass(noise(0.15), 350) * env_exp(0.15, 0.03, 0.001)
        squelch = bandpass(noise(0.12), 700, 1.5) * env_exp(0.12, 0.03) * (0.5 + 0.5 * np.sin(2 * np.pi * 30 * t_axis(0.12)))
        return mix(thud * 1.2, squelch * 0.6)
    if material == "leaves":
        return highpass(noise(0.25), 1800) * env_exp(0.25, 0.06, 0.01) * (0.4 + 0.6 * RNG.random(int(0.25 * SR)))
    if material == "water":
        t = t_axis(0.4)
        bubble = np.sin(2 * np.pi * np.cumsum(600 + 900 * np.exp(-t * 25)) / SR) * env_exp(0.4, 0.06)
        splash = bandpass(noise(0.4), 1800, 0.7) * env_exp(0.4, 0.08, 0.003)
        return mix(splash, bubble * 0.4)
    raise ValueError(material)


def footstep(surface):
    if surface == "hard":
        heel = bandpass(noise(0.08), RNG.uniform(900, 1400), 1.2) * env_exp(0.08, 0.01, 0.0005)
        body = lowpass(noise(0.1), 250) * env_exp(0.1, 0.02)
        scuff = highpass(noise(0.12), 3000) * env_exp(0.12, 0.03, 0.01) * 0.15
        return reverb(mix(heel, body * 0.8, np.concatenate([np.zeros(int(0.03 * SR)), scuff])), 0.25, 0.1, 3000)
    # yumusak: toprak/cim
    crunch = highpass(noise(0.14), 1500) * env_exp(0.14, 0.03, 0.004) * (RNG.random(int(0.14 * SR)) < 0.3)
    body = lowpass(noise(0.12), 300) * env_exp(0.12, 0.025)
    return mix(crunch * 0.6, body)


def break_block():
    sec = 0.9
    chunks = np.zeros(int(sec * SR))
    for _ in range(14):
        c = impact("stone")
        s = int(RNG.uniform(0, 0.5) * SR)
        chunks[s:s + len(c)] += c[: len(chunks) - s] * RNG.uniform(0.2, 0.7)
    rumble = lowpass(noise(sec), 180) * env_exp(sec, 0.25, 0.01)
    return reverb(mix(chunks, rumble * 1.2), 0.9, 0.3, 3000)


def break_glass():
    sec = 1.1
    out = np.zeros(int(sec * SR))
    first = impact("glass") * 1.3
    out[:len(first)] += first[:len(out)]
    for _ in range(26):
        p = modal(0.25, [(RNG.uniform(2500, 9000), RNG.uniform(0.02, 0.1), 1.0)])
        s = int(RNG.uniform(0.02, 0.7) * SR)
        out[s:s + len(p)] += p[: len(out) - s] * RNG.uniform(0.1, 0.4) * (1 - s / len(out))
    return reverb(out, 0.6, 0.2, 7000)


# ---------------------------------------------------------------------------
# Mekanik ve arayuz
# ---------------------------------------------------------------------------
def click(hz, dec=0.012):
    return mix(modal(0.06, [(hz, dec, 1.0), (hz * 1.7, dec * 0.6, 0.5)]),
               highpass(noise(0.01), 3000) * env_exp(0.01, 0.002) * 0.4)


def reload_out():
    slide = highpass(noise(0.12), 1500) * env_exp(0.12, 0.05, 0.02) * 0.3
    return mix(slide, np.concatenate([np.zeros(int(0.08 * SR)), click(1900) * 0.9]))


def reload_in():
    a = click(2300) * 0.8
    b = click(1600, 0.02)
    gap = np.zeros(int(0.14 * SR))
    return mix(np.concatenate([a, gap, b]), highpass(noise(0.2), 2000) * env_exp(0.2, 0.05, 0.03) * 0.15)


def equip():
    rattle = np.zeros(int(0.3 * SR))
    for k in range(5):
        c = click(RNG.uniform(1500, 3000), 0.008) * RNG.uniform(0.3, 0.8)
        s = int((0.02 + k * 0.045 + RNG.uniform(0, 0.015)) * SR)
        rattle[s:s + len(c)] += c[: len(rattle) - s]
    cloth = bandpass(noise(0.3), 1200, 0.7) * env_exp(0.3, 0.1, 0.05) * 0.25
    return mix(rattle, cloth)


def whoosh(sec=0.26, fc=900):
    t = t_axis(sec)
    shape = np.sin(np.pi * t / sec) ** 2
    return bandpass(noise(sec), fc, 0.6) * shape


def ui_tone(freqs, sec=0.14, dec=0.08, bright=0.2):
    out = np.zeros(int(sec * SR))
    for k, f in enumerate(freqs):
        s = int(k * 0.06 * SR)
        t = t_axis(sec - k * 0.06)
        tone = (np.sin(2 * np.pi * f * t) + bright * np.sin(2 * np.pi * f * 2 * t)) * env_exp(sec - k * 0.06, dec, 0.004)
        out[s:s + len(tone)] += tone
    return reverb(out, 0.4, 0.15, 6000)


def rustle(sec=1.2):
    t = t_axis(sec)
    bursts = np.zeros_like(t)
    for _ in range(int(sec * 9)):
        c = RNG.uniform(0, sec)
        w = RNG.uniform(0.02, 0.08)
        bursts += np.exp(-((t - c) / w) ** 2) * RNG.uniform(0.3, 1.0)
    cloth = bandpass(noise(sec), 2200, 0.6) * bursts
    wood = np.zeros_like(t)
    for _ in range(3):
        c = impact("wood") * 0.2
        s = int(RNG.uniform(0, sec - 0.3) * SR)
        wood[s:s + len(c)] += c[: len(wood) - s]
    return mix(cloth, wood)


def static(sec=0.9):
    x = bandpass(noise(sec), 2000, 0.5) * (0.6 + 0.4 * (RNG.random(int(sec * SR)) < 0.2))
    return x * np.sin(np.pi * t_axis(sec) / sec) ** 0.3


def build_place():
    thunk = mix(modal(0.3, [(160, 0.06, 1.0), (340, 0.04, 0.5)]), lowpass(noise(0.2), 400) * env_exp(0.2, 0.03))
    return reverb(mix(thunk, np.concatenate([np.zeros(int(0.05 * SR)), click(2200) * 0.3])), 0.35, 0.15, 3500)


def player_hurt():
    thud = lowpass(noise(0.2), 250) * env_exp(0.2, 0.05, 0.001)
    grunt = voice(0.28, lambda t: 150 - 60 * t, "ae", fry=0.5, breath=0.4)
    return mix(thud, grunt * 0.7)


# ---------------------------------------------------------------------------
# Paket
# ---------------------------------------------------------------------------
def build():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".wav"):
            os.remove(os.path.join(OUT, f))
    guns = {
        "shot_pistol": (115, 0.06, 2500, 0.9, 0.9),
        "shot_revolver": (95, 0.09, 2000, 1.2, 1.1),
        "shot_shotgun": (70, 0.14, 1400, 1.5, 1.5),
        "shot_smg": (125, 0.045, 2800, 0.7, 0.8),
        "shot_rifle": (85, 0.1, 1800, 1.6, 1.3),
    }
    for gid, args in guns.items():
        for v in range(1, 4):
            write_wav(f"{gid}_{v}", gunshot(*args))
    for v in range(1, 4):
        write_wav(f"shot_suppressed_{v}", gunshot(160, 0.03, 4000, 0.4, 0.4, suppressed=True))
    write_wav("shell_eject", shell_eject(), 0.5)
    for kind in ("groan", "alert", "attack", "death", "scream"):
        for v in range(1, 5):
            write_wav(f"zombie_{kind}_{v}", zombie(kind, v), 0.85)
    mats = {"impact_wood": "wood", "impact_stone": "stone", "impact_concrete": "stone", "impact_brick": "stone",
            "impact_metal": "metal", "impact_glass": "glass", "impact_dirt": "dirt", "impact_flesh": "flesh",
            "impact_leaves": "leaves", "impact_water": "water"}
    for sid, mat in mats.items():
        for v in range(1, 4):
            write_wav(f"{sid}_{v}", impact(mat), 0.8)
    for surf in ("hard", "soft"):
        for v in range(1, 6):
            write_wav(f"footstep_{surf}_{v}", footstep(surf), 0.6)
    for v in range(1, 3):
        write_wav(f"break_block_{v}", break_block())
        write_wav(f"break_glass_{v}", break_glass())
        write_wav(f"melee_swing_{v}", whoosh(RNG.uniform(0.22, 0.3), RNG.uniform(700, 1100)), 0.7)
        write_wav(f"melee_hit_{v}", mix(impact("flesh"), impact("wood") * 0.4), 0.85)
    write_wav("dry_fire", click(3100, 0.006), 0.6)
    write_wav("reload_out", reload_out(), 0.7)
    write_wav("reload_in", reload_in(), 0.7)
    write_wav("equip", equip(), 0.6)
    write_wav("search_rustle", rustle(), 0.55)
    write_wav("radio_static", static(), 0.4)
    write_wav("build_place", build_place(), 0.8)
    write_wav("player_hurt", player_hurt(), 0.85)
    write_wav("pickup", ui_tone([880, 1320], 0.18, 0.06), 0.45)
    write_wav("craft_done", ui_tone([660, 880, 1320], 0.4, 0.12), 0.45)
    write_wav("ui_click", click(2600, 0.004), 0.35)
    write_wav("ui_error", ui_tone([330, 247], 0.3, 0.1, 0.5), 0.45)
    print("yazildi:", len([f for f in os.listdir(OUT) if f.endswith(".wav")]), "dosya ->", OUT)


if __name__ == "__main__":
    build()
