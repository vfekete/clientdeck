"""Allows launching the app with `python -m clientdeck`.

Uses an absolute import rather than `from .app import main`: this file is
also Nuitka's compiled entry point (see build.sh/the packaging blueprint),
and Nuitka compiles it as a bare top-level `__main__` module with no parent
package — a relative import there fails with "attempted relative import
with no known parent package" (confirmed by actually building and running
the packaged binary). An absolute import resolves the same way in both
source and packaged mode, since `clientdeck` is always pip/uv-installed.
"""

import sys

from clientdeck.app import main

if __name__ == "__main__":
    sys.exit(main())
