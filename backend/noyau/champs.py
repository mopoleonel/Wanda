from django.db import models


def _sqlite_sans_json(connection):
    return connection.vendor == "sqlite" and not connection.features.supports_json_field


class ChampJSON(models.JSONField):
    """JSONField utilisable aussi avec un SQLite sans extension JSON1 (celui
    de Python 3.8 sous Windows, en développement).

    Les valeurs sont enregistrées et relues normalement ; seules les
    recherches à l'intérieur du JSON (clés, contenu) demandent PostgreSQL ou
    JSON1, et le code n'en fait pas : les filtres sur ces champs se font en
    Python. En production (PostgreSQL), c'est un vrai « jsonb ».
    """

    def _check_supported(self, databases):
        return []

    def db_check(self, connection):
        # La contrainte JSON_VALID de SQLite n'existe pas sans JSON1.
        if _sqlite_sans_json(connection):
            return None
        return super().db_check(connection)
