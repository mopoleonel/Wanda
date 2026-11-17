"""Configuration du back-end WANDA.

Tout ce qui change d'un environnement à l'autre vient des variables
d'environnement (ou du fichier « .env », voir .env.exemple).
"""
import os
from datetime import timedelta
from pathlib import Path

import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent


def _charger_env(fichier):
    """Lit un fichier « CLE=valeur » sans écraser l'environnement réel."""
    if not fichier.exists():
        return
    for ligne in fichier.read_text(encoding="utf8").splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, valeur = ligne.split("=", 1)
        os.environ.setdefault(cle.strip(), valeur.strip().strip('"'))


_charger_env(BASE_DIR / ".env")


def _liste(nom, defaut=""):
    return [v.strip() for v in os.environ.get(nom, defaut).split(",") if v.strip()]


DEBUG = os.environ.get("DJANGO_DEBUG", "0") == "1"
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if not SECRET_KEY:
    if not DEBUG:
        raise RuntimeError("DJANGO_SECRET_KEY manquante (voir .env.exemple).")
    SECRET_KEY = "developpement-seulement-ne-pas-utiliser-en-production"

ALLOWED_HOSTS = _liste("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "noyau",
    "comptes",
    "tarification",
    "demandes",
    "verifications",
    "signalements",
    "notifications",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {
    "default": dj_database_url.config(
        default="sqlite:///" + str(BASE_DIR / "db.sqlite3"), conn_max_age=600
    )
}

AUTH_USER_MODEL = "comptes.Utilisateur"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
]

LANGUAGE_CODE = "fr"
TIME_ZONE = "Africa/Douala"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedStaticFilesStorage"},
}

# Fichiers privés (photos des demandes, pièces d'identité) : jamais servis
# directement ; l'API délivre des liens signés de courte durée.
MEDIA_ROOT = Path(os.environ.get("WANDA_MEDIA_ROOT", BASE_DIR / "media"))
PHOTO_TAILLE_MAX = 5 * 1024 * 1024
LIEN_PHOTO_DUREE = 600  # secondes

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 50,
    "EXCEPTION_HANDLER": "noyau.erreurs.gestionnaire_erreurs",
    # Codes de connexion : par numéro (voir comptes/limites.py) et, plus
    # largement, par adresse IP.
    "DEFAULT_THROTTLE_RATES": {
        "otp_numero": "5/hour",
        "otp_verif_numero": "15/hour",
        "otp_ip": "300/hour",
    },
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=1),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=60),
    "ROTATE_REFRESH_TOKENS": True,
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "sub",
}

CORS_ALLOWED_ORIGINS = _liste("CORS_ALLOWED_ORIGINS")

# Codes de connexion (voir comptes/otp.py)
OTP_FOURNISSEUR = os.environ.get("OTP_FOURNISSEUR", "console")
OTP_NUMEROS_TEST = dict(
    paire.split("=", 1) for paire in _liste("OTP_NUMEROS_TEST") if "=" in paire
)
OTP_DUREE = 300  # secondes
OTP_ESSAIS_MAX = 5
TWILIO_ACCOUNT_SID = os.environ.get("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "")
TWILIO_WHATSAPP_FROM = os.environ.get("TWILIO_WHATSAPP_FROM", "")

FCM_COMPTE_SERVICE = os.environ.get("FCM_COMPTE_SERVICE", "")

if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "loggers": {"wanda": {"handlers": ["console"], "level": "INFO"}},
}
