"""python manage.py importer_supabase --base postgres://... [--fichiers ...]

Voir noyau/import_supabase.py et le README (« Passer de Supabase à Django »).
"""
import os

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from noyau.import_supabase import Fichiers, Importeur, SourcePostgres


class _Simulation(Exception):
    pass


class Command(BaseCommand):
    help = "Importe comptes, demandes, vérifications et signalements depuis Supabase."

    def add_arguments(self, parser):
        parser.add_argument(
            "--base", default=os.environ.get("SUPABASE_DB_URL"),
            help="URL PostgreSQL de Supabase (Dashboard > Project Settings > Database). "
                 "Par défaut : variable SUPABASE_DB_URL.",
        )
        parser.add_argument(
            "--fichiers", action="store_true",
            help="Copier aussi photos et pièces d'identité depuis Supabase Storage "
                 "(SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY requis).",
        )
        parser.add_argument(
            "--simulation", action="store_true",
            help="Tout lire et tout vérifier, puis annuler : rien n'est enregistré.",
        )

    def handle(self, *args, base=None, fichiers=False, simulation=False, **options):
        if not base:
            raise CommandError("Indiquez --base ou la variable SUPABASE_DB_URL.")
        copie = Fichiers()
        if fichiers:
            copie = Fichiers(os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY"))
            if not copie.actif:
                raise CommandError("--fichiers demande SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY.")
            if simulation:
                raise CommandError("--fichiers et --simulation ne vont pas ensemble.")

        importeur = Importeur(SourcePostgres(base), copie)
        try:
            with transaction.atomic():
                bilan = importeur.tout()
                if simulation:
                    raise _Simulation
        except _Simulation:
            bilan = importeur.bilan
            self.stdout.write(self.style.WARNING("Simulation : rien n'a été enregistré."))

        for cle, n in sorted(bilan.items()):
            self.stdout.write("  {:<48} {}".format(cle, n))
        if copie.echecs:
            self.stdout.write(self.style.WARNING("{} fichier(s) non copié(s) :".format(len(copie.echecs))))
            for e in copie.echecs[:20]:
                self.stdout.write("    " + e)
        if not simulation:
            self.stdout.write(self.style.SUCCESS("Import terminé."))
