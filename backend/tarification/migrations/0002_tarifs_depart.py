"""Valeurs de départ des tarifs. Relançable : une valeur déjà modifiée par
l'équipe WANDA n'est jamais écrasée."""
from django.db import migrations


def creer(apps, schema_editor):
    from tarification.valeurs_depart import TARIFS_DEPART

    Tarif = apps.get_model("tarification", "Tarif")
    for service, cle, valeur, unite, libelle in TARIFS_DEPART:
        Tarif.objects.get_or_create(
            service=service, cle=cle,
            defaults={"valeur": valeur, "unite": unite, "libelle": libelle},
        )


class Migration(migrations.Migration):
    dependencies = [("tarification", "0001_initial")]
    operations = [migrations.RunPython(creer, migrations.RunPython.noop)]
