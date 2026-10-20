"""Mocked vs. real execution of the privileged helper scripts.

The packaged binary (`build.sh`) is always real. From a source checkout,
`CLIENTDECK_MODE=real` (set by `run-real.sh`) is real; anything else,
including unset, keeps the scripts in their default mock mode. Real mode
makes the app pass `--real` to `src/scripts/*`, so user creation/deletion
and `su`/`xhost` launches actually happen. See docs/comments-details.md
[138].
"""

from __future__ import annotations

import os
from collections.abc import Mapping

ENV_VAR = "CLIENTDECK_MODE"
REAL = "real"


def is_real_mode(packaged: bool, environ: Mapping[str, str] | None = None) -> bool:
    """`packaged`: running as the built binary (`paths.is_packaged_build()`)."""
    if packaged:
        return True
    env = os.environ if environ is None else environ
    return env.get(ENV_VAR, "").strip().lower() == REAL


def script_mode_args(real: bool) -> list[str]:
    """Extra argv for a `src/scripts/*` call."""
    return ["--real"] if real else []
