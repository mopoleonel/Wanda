# Image de production du back-end WANDA.
#   docker build -t wanda-backend .
#   docker run --env-file .env -p 8000:8000 -v wanda-media:/app/media wanda-backend
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WANDA_MEDIA_ROOT=/app/media

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
# Les fichiers de l'administration sont préparés une fois pour toutes.
RUN DJANGO_SECRET_KEY=construction python manage.py collectstatic --noinput

# Utilisateur sans droits particuliers.
RUN useradd --create-home wanda && mkdir -p /app/media && chown -R wanda /app/media
USER wanda

EXPOSE 8000
# Migrations au démarrage, puis le serveur.
CMD ["sh", "-c", "python manage.py migrate --noinput && gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3 --timeout 60"]
