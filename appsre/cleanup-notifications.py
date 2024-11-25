import os
import sys
from pathlib import Path

import django

# add the parent directory to the path so we can import the glitchtip module(s)
sys.path.append(str(Path(__file__).resolve().parent.parent))
# Set up Django environment. Must be done before importing any Django DB models.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")
django.setup()

from apps.alerts.models import Notification  # isort:skip

Notification.objects.all().delete()
