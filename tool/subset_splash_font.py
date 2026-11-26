#!/usr/bin/env python3
"""Generate the bundled splash font subset.

The full Huiwen Mincho face is about 24 MB. Keep only the default splash
poem and let all other text fall back to the platform font.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_SPLASH_TEXT = "欲买桂花同载酒终不似少年游"

def build_charset(splash_text: str) -> str:
    codepoints = {0x20}
    codepoints.update(ord(char) for char in splash_text if not char.isspace())
    return "".join(chr(codepoint) for codepoint in sorted(codepoints))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Subset the full Huiwen Mincho TTF for the splash screen."
    )
    parser.add_argument(
        "--source",
        required=True,
        type=Path,
        help="Full Huiwen Mincho TTF downloaded from bosswnx/huiwenmincho-improved.",
    )
    parser.add_argument(
        "--output",
        default=Path("assets/fonts/HuiwenMincho.ttf"),
        type=Path,
        help="Subset output path.",
    )
    parser.add_argument(
        "--splash-text",
        default=DEFAULT_SPLASH_TEXT,
        help="Extra splash text that must always be covered.",
    )
    args = parser.parse_args()

    charset = build_charset(args.splash_text)
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".txt", delete=False
    ) as text_file:
        text_file.write(charset)
        text_path = Path(text_file.name)

    try:
        subprocess.run(
            [
                sys.executable,
                "-m",
                "fontTools.subset",
                str(args.source),
                f"--output-file={args.output}",
                "--layout-features=*",
                f"--text-file={text_path}",
            ],
            check=True,
        )
    finally:
        text_path.unlink(missing_ok=True)

    print(
        f"Wrote {args.output} ({args.output.stat().st_size:,} bytes, "
        f"{len(charset):,} characters)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
