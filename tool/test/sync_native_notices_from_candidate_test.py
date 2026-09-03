#!/usr/bin/env python3
"""Behavioral tests for the native notice publication helper."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = REPOSITORY_ROOT / ".github/scripts/sync-native-notices-from-candidate.sh"
START_MARKER = "<!-- BEGIN GENERATED NATIVE DEPENDENCIES -->"
END_MARKER = "<!-- END GENERATED NATIVE DEPENDENCIES -->"
NOTICE_PATHS = (
    "THIRD_PARTY_NOTICES.md",
    "packages/simple_torrent_windows/THIRD_PARTY_NOTICES.md",
    "packages/simple_torrent_android/THIRD_PARTY_NOTICES.md",
    "packages/simple_torrent_ios/THIRD_PARTY_NOTICES.md",
    "packages/simple_torrent_macos/THIRD_PARTY_NOTICES.md",
)

OLD_ROOT_BOOST = """When required by the pinned Boost release, the builder applies the reviewed,
repository-tracked Android x86_64 long-double compatibility patch. Applied
patch paths and checksums are recorded in the authenticated source stamp and
artifact provenance, so a dependency version change cannot silently reuse a
patch for a different source release."""
NEW_ROOT_BOOST = """The pinned Boost release contains the Android x86_64 long-double correction
upstream in Boost.Math, so the bundled sources require no repository-maintained
Boost patch. Artifact provenance records an empty source-patch inventory."""
OLD_ANDROID_BOOST = """When required by the pinned Boost release, the maintainer build applies the
reviewed Android x86_64 long-double compatibility patch documented in the root
third-party notices. Its path and checksum are recorded in artifact provenance."""
NEW_ANDROID_BOOST = """The pinned Boost release contains the Android x86_64 long-double correction
upstream in Boost.Math, so this bundle requires no repository-maintained Boost
patch."""


def notice(prose: str, table_version: str, footer: str = "Reviewed footer.") -> str:
    return (
        f"Reviewed heading.\n\n{prose}\n\n{START_MARKER}\n"
        f"| Dependency | Version |\n| --- | --- |\n| Boost | {table_version} |\n"
        f"{END_MARKER}\n\n{footer}\n"
    )


def fixture_text(relative: str, *, candidate: bool) -> str:
    if relative == "THIRD_PARTY_NOTICES.md":
        prose = NEW_ROOT_BOOST if candidate else OLD_ROOT_BOOST
    elif relative == "packages/simple_torrent_android/THIRD_PARTY_NOTICES.md":
        prose = NEW_ANDROID_BOOST if candidate else OLD_ANDROID_BOOST
    else:
        prose = "Platform-specific reviewed notice."
    return notice(prose, "1.92.0" if candidate else "1.91.0")


def prepare_fixture(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    script_copy = root / ".github/scripts/sync-native-notices-from-candidate.sh"
    script_copy.parent.mkdir(parents=True)
    shutil.copyfile(SCRIPT, script_copy)
    candidate = root / "candidate"
    for relative in NOTICE_PATHS:
        destination = root / relative
        source = candidate / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        source.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            fixture_text(relative, candidate=False),
            encoding="utf-8",
        )
        source.write_text(fixture_text(relative, candidate=True), encoding="utf-8")
    return script_copy, candidate


def bash_command(script: pathlib.Path, candidate: pathlib.Path) -> list[str]:
    if os.name != "nt":
        return ["bash", str(script), str(candidate)]

    git = shutil.which("git")
    git_root = pathlib.Path(git).resolve().parent.parent if git else None
    git_bash_candidates = [
        git_root / "bin/bash.exe" if git_root else None,
        pathlib.Path(os.environ.get("ProgramFiles", "C:/Program Files"))
        / "Git/bin/bash.exe",
    ]
    for executable in git_bash_candidates:
        if executable is not None and executable.is_file():
            return [
                str(executable),
                script.resolve().as_posix(),
                candidate.resolve().as_posix(),
            ]

    wsl = shutil.which("wsl.exe") or shutil.which("wsl")
    if wsl:
        return [wsl, "bash", wsl_path(script), wsl_path(candidate)]
    raise AssertionError("The notice synchronization test requires Bash")


def wsl_path(path: pathlib.Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.removesuffix(":").lower()
    if not drive:
        raise AssertionError(f"Cannot map path into WSL: {resolved}")
    relative = resolved.relative_to(resolved.anchor).as_posix()
    return f"/mnt/{drive}/{relative}"


def run_script(
    script: pathlib.Path,
    candidate: pathlib.Path,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        bash_command(script, candidate),
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def require_success(result: subprocess.CompletedProcess[str]) -> None:
    if result.returncode != 0:
        raise AssertionError(
            f"notice synchronization failed ({result.returncode}):\n{result.stderr}"
        )


def test_migration_and_idempotence() -> None:
    with tempfile.TemporaryDirectory(prefix="native-notice-sync-") as temporary:
        root = pathlib.Path(temporary)
        script, candidate = prepare_fixture(root)
        require_success(run_script(script, candidate))
        for relative in NOTICE_PATHS:
            assert (root / relative).read_bytes() == (
                candidate / relative
            ).read_bytes()

        require_success(run_script(script, candidate))
        for relative in NOTICE_PATHS:
            assert (root / relative).read_bytes() == (
                candidate / relative
            ).read_bytes()


def test_unreviewed_prose_is_rejected_without_overwriting() -> None:
    with tempfile.TemporaryDirectory(prefix="native-notice-reject-") as temporary:
        root = pathlib.Path(temporary)
        script, candidate = prepare_fixture(root)
        destination = root / "THIRD_PARTY_NOTICES.md"
        original = destination.read_bytes()
        unsupported = notice(
            NEW_ROOT_BOOST,
            "1.92.0",
            footer="Unreviewed candidate footer.",
        )
        (candidate / "THIRD_PARTY_NOTICES.md").write_text(
            unsupported,
            encoding="utf-8",
        )

        result = run_script(script, candidate)
        assert result.returncode == 65, result
        assert "unsupported changes outside the generated block" in result.stderr
        assert destination.read_bytes() == original


def main() -> None:
    test_migration_and_idempotence()
    test_unreviewed_prose_is_rejected_without_overwriting()
    print(json.dumps({"ok": True, "suite": "native-notice-sync"}))


if __name__ == "__main__":
    main()
