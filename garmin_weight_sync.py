#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
import json
from garminconnect import (
    Garmin,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
)

# --- CONFIG ---
EMAIL = os.getenv("GARMIN_EMAIL", "EMAIL")
PASSWORD = os.getenv("GARMIN_PASS", "PASSWORD")
SESSION_FILE = "/app/session/garmin_session.json"


def get_client():
    """Create a Garmin client, reusing cached session if available."""
    client = Garmin(EMAIL, PASSWORD)
    client.login()
    return client


def sync_weight(weight: float):
    try:
        client = get_client()
        client.add_weigh_in(weight=weight,unitKey = "kg")
        print(f"[Garmin] Uploaded weight {weight} kg successfully")
    except (GarminConnectAuthenticationError, GarminConnectConnectionError) as e:
        print(f"[Garmin] ERROR: {e}")
        # Clear bad session file if login fails
        if os.path.exists(SESSION_FILE):
            os.remove(SESSION_FILE)
    except Exception as e:
        print(f"[Garmin] Unexpected ERROR: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: garmin_weight_sync.py <weight>")
        sys.exit(1)

    weight = float(sys.argv[1])
    sync_weight(weight)
