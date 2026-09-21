"""Allows launching the app with `python -m clientdeck`."""

import sys

# Absolute import, not `from .app import main` — see docs/comments-details.md [1].
from clientdeck.app import main

if __name__ == "__main__":
    sys.exit(main())
