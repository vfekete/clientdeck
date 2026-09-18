"""Shared username/group existence check.

Used both by the QML live-validation input on the "add client" dialog and by
`src/scripts/create_user.py`'s own safety check, so the two can never
disagree about what counts as an already-taken name.
"""

from __future__ import annotations

import grp
import pwd


def username_or_group_exists(name: str) -> bool:
    """True if a Linux user or group named `name` already exists."""
    if not name:
        return False
    try:
        pwd.getpwnam(name)
        return True
    except KeyError:
        pass
    try:
        grp.getgrnam(name)
        return True
    except KeyError:
        pass
    return False
