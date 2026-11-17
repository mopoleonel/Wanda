from django.contrib import admin

from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "destinataire", "titre", "lue", "push_envoyes"]
    list_filter = ["lue"]
    search_fields = ["destinataire__telephone", "titre", "corps"]
    readonly_fields = [f.name for f in Notification._meta.fields]

    def has_add_permission(self, request):
        return False
