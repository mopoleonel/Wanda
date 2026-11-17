from rest_framework import generics, serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["id", "titre", "corps", "donnees", "lue", "cree_le"]


class MesNotifications(generics.ListAPIView):
    """GET : notifications reçues, des plus récentes aux plus anciennes."""

    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(destinataire=self.request.user)


class MarquerLues(APIView):
    """POST {ids?} : marque comme lues (toutes si ids est absent)."""

    def post(self, request):
        qs = Notification.objects.filter(destinataire=request.user, lue=False)
        ids = request.data.get("ids")
        if isinstance(ids, list):
            qs = qs.filter(pk__in=[i for i in ids if isinstance(i, int)])
        return Response({"lues": qs.update(lue=True)})
