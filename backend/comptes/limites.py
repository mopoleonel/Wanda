"""Limites d'envoi et de vérification des codes.

Par numéro de téléphone d'abord : au Cameroun, beaucoup d'abonnés mobiles
partagent la même adresse IP (NAT de l'opérateur), une limite par IP seule
bloquerait des clients légitimes. Une limite large par IP reste en plus,
contre les envois en masse.
"""
from rest_framework.throttling import SimpleRateThrottle

from noyau.telephone import normaliser


class _ParNumero(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        telephone = normaliser(str(request.data.get("telephone", "")))
        if telephone is None:
            return None  # refusé ensuite comme numéro invalide
        return self.cache_format % {"scope": self.scope, "ident": telephone}


class CodeParNumero(_ParNumero):
    scope = "otp_numero"


class VerificationParNumero(_ParNumero):
    scope = "otp_verif_numero"


class CodeParIP(SimpleRateThrottle):
    scope = "otp_ip"

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}
