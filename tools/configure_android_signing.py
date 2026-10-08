#!/usr/bin/env python3
"""Inject Alfaeq release signing into the generated Android Gradle config.

`flutter create . --platforms android` regenerates `android/` on every CI run and
the Flutter template signs release builds with the debug key. This script patches
the generated `android/app/build.gradle.kts` so that:

  * when the CI secret ANDROID_KEYSTORE_BASE64 is present, the release build is
    signed with the production keystore, whose passwords are read from the
    environment (never written into the Kotlin source);
  * when it is absent, the build keeps the debug signing and still succeeds.

Environment:
  ANDROID_KEYSTORE_BASE64    base64-encoded .jks contents (optional)
  ANDROID_KEY_ALIAS          key alias (default: alfaeq)
"""
from __future__ import annotations

import base64
import os
import pathlib
import sys

GRADLE = pathlib.Path("android/app/build.gradle.kts")
KEYSTORE = pathlib.Path("android/app/alfaeq-release.jks")
MARKER = "Alfaeq release signing"

SIGNING_BLOCK = (
    "    // Alfaeq release signing: keystore and passwords come from CI secrets.\n"
    '    val alfaeqStoreFile = rootProject.file("app/alfaeq-release.jks")\n'
    '    val alfaeqStorePassword = System.getenv("ALFAEQ_STORE_PASSWORD") ?: ""\n'
    '    val alfaeqKeyAlias = System.getenv("ALFAEQ_KEY_ALIAS") ?: "alfaeq"\n'
    '    val alfaeqKeyPassword = System.getenv("ALFAEQ_KEY_PASSWORD") ?: ""\n'
    "    signingConfigs {\n"
    '        create("release") {\n'
    "            if (alfaeqStoreFile.exists()) {\n"
    "                storeFile = alfaeqStoreFile\n"
    "                storePassword = alfaeqStorePassword\n"
    "                keyAlias = alfaeqKeyAlias\n"
    "                keyPassword = alfaeqKeyPassword\n"
    "            }\n"
    "        }\n"
    "    }\n\n"
)

RELEASE_BLOCK = (
    "        release {\n"
    "            signingConfig = if (alfaeqStoreFile.exists())\n"
    '                signingConfigs.getByName("release")\n'
    "            else\n"
    '                signingConfigs.getByName("debug")\n'
    "        }\n"
)


def configure(gradle: pathlib.Path = GRADLE, keystore: pathlib.Path = KEYSTORE,
              keystore_b64: str | None = None) -> str:
    """Patch the Gradle file and return a short status message."""
    text = gradle.read_text()
    if MARKER in text:
        return "signing already configured"

    if "android {" not in text:
        raise SystemExit("unexpected build.gradle.kts layout")

    keystore_b64 = (keystore_b64 if keystore_b64 is not None
                    else os.environ.get("ANDROID_KEYSTORE_BASE64", "")).strip()
    if not keystore_b64:
        return "no keystore secret - using debug signing"

    keystore.write_bytes(base64.b64decode(keystore_b64))
    text = text.replace("android {", "android {\n" + SIGNING_BLOCK, 1)

    old_release = (
        "        release {\n"
        "            // TODO: Add your own signing config for the release build.\n"
        "            // Signing with the debug keys for now, so `flutter run --release` works.\n"
        '            signingConfig = signingConfigs.getByName("debug")\n'
        "        }\n"
    )
    if old_release in text:
        text = text.replace(old_release, RELEASE_BLOCK, 1)
    else:
        text = text.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            "signingConfig = if (alfaeqStoreFile.exists()) "
            'signingConfigs.getByName("release") else '
            'signingConfigs.getByName("debug")',
            1,
        )
    gradle.write_text(text)
    alias = os.environ.get("ANDROID_KEY_ALIAS", "").strip() or "alfaeq"
    return f"release signing configured for alias {alias}"


if __name__ == "__main__":
    status = configure()
    if status.startswith("no keystore"):
        print("::warning::ANDROID_KEYSTORE_BASE64 not set - building with the debug key.")
    print(status)
    sys.exit(0)
