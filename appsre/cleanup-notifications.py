import os
import sys

import django

# add the parent directory to the path so we can import the glitchtip module(s)
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Set up Django environment. Must be done before importing any Django DB models.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")
django.setup()

from apps.alerts.models import Notification  # isort:skip

Notification.objects.all().delete()
