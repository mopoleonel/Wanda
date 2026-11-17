"""Icône WANDA en relief : disque vert bombé, oeil, nom, sur fond blanc.

Dessinée en grand (N px) puis réduite, pour des bords nets.
Usage (Pillow et numpy requis) :
  python outils/icone3d.py <dossier> final   -> icone_app*.png à copier dans assets/images
  python outils/icone3d.py <dossier>         -> 3 propositions à comparer
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

N = 4096
POLICE = "C:/Windows/Fonts/seguibl.ttf"  # Segoe UI Black

VERT_CLAIR = np.array([46, 140, 88])
VERT = np.array([21, 83, 58])
VERT_FONCE = np.array([9, 48, 32])
LIME_CLAIR = np.array([178, 240, 120])
LIME = np.array([124, 205, 66])
LIME_FONCE = np.array([70, 150, 40])


def grille():
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    return x, y


X, Y = grille()


def radial(cx, cy, r, c0, c1, c2=None):
    """Dégradé radial c0 (centre) -> c1 (r) [-> c2 (1.4 r)]."""
    d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / r
    if c2 is None:
        t = np.clip(d, 0, 1)[..., None]
        rgb = c0 * (1 - t) + c1 * t
    else:
        t1 = np.clip(d, 0, 1)[..., None]
        t2 = np.clip((d - 1) / 0.4, 0, 1)[..., None]
        rgb = (c0 * (1 - t1) + c1 * t1) * (1 - t2) + c2 * t2
    return Image.fromarray(rgb.astype(np.uint8), "RGB")


def masque_disque(cx, cy, r):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return m


def masque_amande(cx, cy, w, h):
    """Forme d'oeil : intersection de deux disques."""
    R = ((w / 2) ** 2 + (h / 2) ** 2) / h
    haut = masque_disque(cx, cy + R - h / 2, R)
    bas = masque_disque(cx, cy - R + h / 2, R)
    return ImageChops.multiply(haut, bas)


def poser(fond, couleur, masque):
    """Pose une couleur (tuple) ou une image RGB à travers un masque L."""
    if isinstance(couleur, tuple):
        couche = Image.new("RGB", (N, N), couleur)
    else:
        couche = couleur
    fond.paste(couche, (0, 0), masque)


def ombre(fond, masque, dx, dy, flou, opacite):
    m = masque.filter(ImageFilter.GaussianBlur(flou))
    m = ImageChops.offset(m, int(dx), int(dy))
    m = m.point(lambda v: int(v * opacite))
    poser(fond, (6, 30, 20), m)


def degrade_vertical(masque, haut, bas, alpha_haut, alpha_bas, y0, y1):
    """Voile coloré dégradé verticalement, limité au masque."""
    t = np.clip((Y - y0) / max(1, (y1 - y0)), 0, 1)
    a = (alpha_haut * (1 - t) + alpha_bas * t) * 255
    a = Image.fromarray(a.astype(np.uint8), "L")
    return ImageChops.multiply(a, masque)


def oeil(img, cx, cy, w):
    """Oeil WANDA en relief, centré en (cx, cy), largeur w."""
    h = w * 0.56
    contour = masque_amande(cx, cy, w, h)
    ombre(img, contour, 0, w * 0.025, w * 0.03, 0.55)
    # Contour vert lime bombé.
    poser(img, radial(cx - w * 0.15, cy - h * 0.5, w * 0.75, LIME_CLAIR, LIME, LIME_FONCE), contour)
    # Intérieur sombre (blanc de l'oeil inversé, comme le logo).
    interieur = masque_amande(cx, cy, w * 0.84, h * 0.66)
    poser(img, radial(cx, cy - h * 0.2, w * 0.5, np.array([40, 46, 44]), np.array([12, 16, 15])), interieur)
    # Ombre portée du contour sur l'intérieur (creux).
    creux = ImageChops.subtract(interieur, masque_amande(cx, cy + h * 0.06, w * 0.80, h * 0.56).filter(ImageFilter.GaussianBlur(w * 0.02)))
    poser(img, (0, 0, 0), creux.point(lambda v: int(v * 0.5)))

    # Iris lime bombé.
    ri = h * 0.47
    iris = masque_disque(cx, cy, ri)
    ombre(img, iris, 0, ri * 0.06, ri * 0.08, 0.6)
    poser(img, radial(cx - ri * 0.3, cy - ri * 0.35, ri * 1.25, LIME_CLAIR, LIME, LIME_FONCE), iris)
    # Anneau plus foncé au bord de l'iris.
    anneau = ImageChops.subtract(iris, masque_disque(cx, cy, ri * 0.9).filter(ImageFilter.GaussianBlur(ri * 0.05)))
    poser(img, tuple(int(v) for v in LIME_FONCE), anneau.point(lambda v: int(v * 0.6)))

    # Pupille noire avec le signal (ondes).
    rp = ri * 0.56
    pupille = masque_disque(cx, cy, rp)
    poser(img, radial(cx - rp * 0.2, cy - rp * 0.3, rp * 1.2, np.array([45, 50, 50]), np.array([5, 7, 7])), pupille)
    ondes = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(ondes)
    ox, oy = cx - rp * 0.32, cy + rp * 0.30
    d.ellipse((ox - rp * 0.09, oy - rp * 0.09, ox + rp * 0.09, oy + rp * 0.09), fill=255)
    for k, rr in enumerate((0.30, 0.50, 0.70)):
        r_ = rp * rr
        d.arc((ox - r_, oy - r_, ox + r_, oy + r_), start=-90, end=0, fill=255, width=int(rp * 0.085))
    poser(img, (190, 200, 195), ImageChops.multiply(ondes, pupille))

    # Reflet blanc (petit disque) et éclat doux.
    rr = rp * 0.42
    reflet = masque_disque(cx + rp * 0.62, cy - rp * 0.62, rr)
    poser(img, (255, 255, 255), reflet)
    eclat = masque_disque(cx - ri * 0.35, cy - ri * 0.45, ri * 0.35).filter(ImageFilter.GaussianBlur(ri * 0.18))
    poser(img, (255, 255, 255), ImageChops.multiply(eclat, iris).point(lambda v: int(v * 0.45)))


def texte(img, chaine, cx, cy, taille):
    police = ImageFont.truetype(POLICE, int(taille))
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    bb = d.textbbox((0, 0), chaine, font=police)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    d.text((cx - w / 2 - bb[0], cy - h / 2 - bb[1]), chaine, font=police, fill=255)
    ombre(img, m, 0, taille * 0.05, taille * 0.04, 0.6)
    poser(img, (255, 255, 255), m)
    # Léger dégradé gris en bas des lettres : effet gravé / relief.
    voile = degrade_vertical(m, None, None, 0.0, 0.18, cy - h / 2, cy + h / 2)
    poser(img, (20, 70, 45), voile)


def disque(img, cx, cy, r):
    m = masque_disque(cx, cy, r)
    # Ombre portée douce sous le disque (il « flotte » sur le blanc).
    ombre(img, m, 0, r * 0.06, r * 0.07, 0.45)
    ombre(img, m, 0, r * 0.015, r * 0.015, 0.35)
    # Corps bombé : lumière en haut à gauche.
    poser(img, radial(cx - r * 0.35, cy - r * 0.45, r * 1.55, VERT_CLAIR, VERT, VERT_FONCE), m)
    # Biseau : liseré clair en haut, sombre en bas.
    bord = ImageChops.subtract(m, masque_disque(cx, cy, r * 0.965).filter(ImageFilter.GaussianBlur(r * 0.01)))
    poser(img, (120, 200, 150), degrade_vertical(bord, None, None, 0.9, 0.0, cy - r, cy + r * 0.2))
    poser(img, (4, 25, 16), degrade_vertical(bord, None, None, 0.0, 0.8, cy - r * 0.2, cy + r))
    return m


def reflet_vitre(img, masque_disque_, cx, cy, r):
    """Reflet brillant en haut du disque (effet verre bombé)."""
    e = Image.new("L", (N, N), 0)
    ImageDraw.Draw(e).ellipse((cx - r * 0.82, cy - r * 0.93, cx + r * 0.82, cy - r * 0.05), fill=255)
    e = ImageChops.multiply(e, masque_disque_).filter(ImageFilter.GaussianBlur(r * 0.02))
    poser(img, (255, 255, 255), degrade_vertical(e, None, None, 0.30, 0.0, cy - r, cy - r * 0.05))


FOND_UNI = None  # (r, g, b) pour un fond uni (calcul de la transparence)


def fond_blanc():
    if FOND_UNI is not None:
        return Image.new("RGB", (N, N), FOND_UNI)
    # Blanc légèrement dégradé vers le gris-vert très clair : donne du volume.
    t = np.clip(Y / N, 0, 1)[..., None]
    rgb = np.array([255, 255, 255]) * (1 - t) + np.array([234, 241, 236]) * t
    return Image.fromarray(rgb.astype(np.uint8), "RGB")


def variante_complete(rayon=0.40):
    """Comme l'accueil : disque, oeil, WANDA (sans le slogan, illisible en petit)."""
    img = fond_blanc()
    c, r = N / 2, N * rayon
    m = disque(img, c, c, r)
    oeil(img, c, c - r * 0.20, r * 1.25)
    texte(img, "WANDA", c, c + r * 0.52, r * 0.36)
    reflet_vitre(img, m, c, c, r)
    return img


def variante_oeil(rayon=0.40):
    """Oeil seul, plus grand : le plus lisible en tout petit."""
    img = fond_blanc()
    c, r = N / 2, N * rayon
    m = disque(img, c, c, r)
    oeil(img, c, c, r * 1.52)
    reflet_vitre(img, m, c, c, r)
    return img


def variante_sans_disque():
    """Oeil vert directement sur le blanc, nom en vert dessous."""
    img = fond_blanc()
    c = N / 2
    oeil(img, c, c - N * 0.08, N * 0.62)
    police_m = Image.new("L", (N, N), 0)
    police = ImageFont.truetype(POLICE, int(N * 0.15))
    d = ImageDraw.Draw(police_m)
    bb = d.textbbox((0, 0), "WANDA", font=police)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    ty = c + N * 0.22
    d.text((c - w / 2 - bb[0], ty - h / 2 - bb[1]), "WANDA", font=police, fill=255)
    ombre(img, police_m, 0, N * 0.008, N * 0.006, 0.35)
    poser(img, radial(c, ty - h, w * 0.8, VERT_CLAIR, VERT, VERT_FONCE), police_m)
    return img


def reduire(img, taille=1024):
    return img.resize((taille, taille), Image.LANCZOS)


def avant_plan(fonction):
    """Avant-plan d'icône adaptative Android : le dessin dans la zone sûre,
    fond transparent (le fond blanc est fourni à part)."""
    img = fonction()
    # On rend le fond transparent en recalculant sans fond : plus simple,
    # on garde l'image entière et on réduit le dessin à 66 % au centre.
    petit = img.resize((int(N * 0.70), int(N * 0.70)), Image.LANCZOS)
    toile = Image.new("RGB", (N, N), (255, 255, 255))
    toile.paste(petit, ((N - petit.width) // 2, (N - petit.height) // 2))
    return toile


def transparent(fonction):
    """Rend le dessin sur blanc puis sur noir : la différence donne la
    transparence exacte (ombre douce comprise)."""
    global FOND_UNI
    FOND_UNI = (255, 255, 255)
    blanc = np.asarray(fonction(), dtype=np.float32)
    FOND_UNI = (0, 0, 0)
    noir = np.asarray(fonction(), dtype=np.float32)
    FOND_UNI = None
    alpha = 1 - (blanc - noir).mean(axis=2) / 255
    alpha = np.clip(alpha, 0, 1)
    couleur = np.where(alpha[..., None] > 1e-3, noir / np.maximum(alpha[..., None], 1e-3), 0)
    rgba = np.dstack([np.clip(couleur, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[2] == "final":
    sortie = Path(sys.argv[1])
    sortie.mkdir(parents=True, exist_ok=True)
    # Icône complète (iOS, anciens Android) : le disque remplit bien le carré.
    reduire(variante_complete(rayon=0.43)).save(sortie / "icone_app.png")
    # Android 8+ : flutter_launcher_icons ajoute une marge de 16 % autour de
    # ce calque ; le disque y est donc dessiné grand (0,41 x 0,68 ≈ 0,28 du
    # carré final), le fond blanc reste visible autour.
    reduire(transparent(lambda: variante_complete(rayon=0.41))).save(sortie / "icone_app_avant_plan.png")
    reduire(fond_blanc()).save(sortie / "icone_app_fond.png")
    print("ok final")
elif __name__ == "__main__":
    sortie = Path(sys.argv[1])
    sortie.mkdir(parents=True, exist_ok=True)
    variantes = {
        "A_complete": variante_complete,
        "B_oeil": variante_oeil,
        "C_sans_disque": variante_sans_disque,
    }
    for nom, f in variantes.items():
        reduire(f()).save(sortie / f"{nom}.png")
        print("ok", nom)
