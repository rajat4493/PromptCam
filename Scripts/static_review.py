#!/usr/bin/env python3
"""
PromptCam static review.

This is NOT a compiler and makes no claim to be one. It checks the invariants
that this project's architecture depends on, all of which are decidable by
reading the source:

  1. PromptCamCore imports no platform framework.
  2. Unverified iPhone Duo symbols appear only in PromptCamiOS/Platform.
  3. No model-name or fixed-dimension device detection anywhere.
  4. No UIScreen.main.
  5. Every unverified symbol site carries a REQUIRES_MAC_VALIDATION marker.
  6. Brackets, braces and parentheses balance in every Swift file.
  7. No file claims a capability the verification ledger does not grant.

Run:  python3 Scripts/static_review.py
Exit: 0 = all checks pass, 1 = at least one failure.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "Sources" / "PromptCamCore"
IOS = ROOT / "Sources" / "PromptCamiOS"
PLATFORM = IOS / "Platform"
TESTS = ROOT / "Tests"

FORBIDDEN_CORE_IMPORTS = [
    "SwiftUI", "UIKit", "AVFoundation", "AVKit", "SwiftData",
    "Photos", "PhotosUI", "StoreKit", "CoreMedia", "Observation",
]

# Symbols supplied by the product owner but never confirmed by a compiler.
UNVERIFIED_DUO_SYMBOLS = [
    "CameraCaptureAccessory",
    "ExternalNonInteractiveAccessory",
    "sceneAccessory",
    "onAvailabilityChange",
    "onHingeChange",
    "UIHingeInteraction",
    "reservedRegions",
    "ArrangementView",
    "arrangementViewStyle",
    "AVCaptureDeviceDirectionCoordinator",
    "builtInOuterUltraWideCamera",
    "builtInInnerUltraWideCamera",
]

# Patterns that would mean the app is guessing at the device.
DEVICE_DETECTION_PATTERNS = [
    (r"\butsname\b", "utsname model-name detection"),
    (r"\bUIDevice\s*\.\s*current\s*\.\s*model\b", "UIDevice.current.model detection"),
    (r"\bUIScreen\s*\.\s*main\b", "UIScreen.main (forbidden on a two-display device)"),
    (r"\bsysctlbyname\b", "sysctlbyname model detection"),
    (r'"iPhone1[0-9]', "hardware model string literal"),
    (r"\bmodelIdentifier\b", "model identifier detection"),
]

failures: list[str] = []
notes: list[str] = []


def swift_files(base: Path) -> list[Path]:
    return sorted(base.rglob("*.swift")) if base.exists() else []


def check_core_imports() -> None:
    for path in swift_files(CORE):
        text = path.read_text()
        for module in FORBIDDEN_CORE_IMPORTS:
            if re.search(rf"^\s*import\s+{re.escape(module)}\s*$", text, re.MULTILINE):
                failures.append(
                    f"[core-purity] {path.relative_to(ROOT)} imports {module}; "
                    "PromptCamCore must stay platform-independent"
                )


def check_duo_symbol_isolation() -> None:
    searchable = swift_files(IOS) + swift_files(CORE) + swift_files(TESTS)
    for path in searchable:
        if PLATFORM in path.parents:
            continue
        text = path.read_text()
        for symbol in UNVERIFIED_DUO_SYMBOLS:
            # Match real uses, not the word inside a longer identifier, and skip
            # comment lines so documentation may discuss the API freely.
            for line_number, line in enumerate(text.splitlines(), start=1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("///") or stripped.startswith("*"):
                    continue
                if re.search(rf"\b{re.escape(symbol)}\b", line):
                    failures.append(
                        f"[duo-isolation] {path.relative_to(ROOT)}:{line_number} "
                        f"uses unverified symbol '{symbol}' outside Platform/"
                    )


def check_device_detection() -> None:
    for path in swift_files(CORE) + swift_files(IOS):
        text = path.read_text()
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for pattern, description in DEVICE_DETECTION_PATTERNS:
                if re.search(pattern, line):
                    failures.append(
                        f"[device-detection] {path.relative_to(ROOT)}:{line_number} {description}"
                    )


def check_validation_markers() -> None:
    """Every Platform file touching an unverified symbol must say so."""
    for path in swift_files(PLATFORM):
        text = path.read_text()
        uses_unverified = any(
            re.search(rf"\b{re.escape(symbol)}\b", text) for symbol in UNVERIFIED_DUO_SYMBOLS
        )
        if uses_unverified and "REQUIRES_MAC_VALIDATION" not in text:
            failures.append(
                f"[marker] {path.relative_to(ROOT)} uses an unverified symbol "
                "but carries no REQUIRES_MAC_VALIDATION comment"
            )


def check_bracket_balance() -> None:
    """
    Balance check that skips string literals, character escapes and comments.

    Not a parser: it cannot detect a misplaced brace that still balances. It
    does reliably catch the most common hand-authoring error.
    """
    pairs = {"}": "{", ")": "(", "]": "["}
    openers = set(pairs.values())

    for path in swift_files(CORE) + swift_files(IOS) + swift_files(TESTS):
        text = path.read_text()
        stack: list[tuple[str, int]] = []
        line = 1
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\n":
                line += 1
                i += 1
                continue
            # Line comment
            if ch == "/" and i + 1 < n and text[i + 1] == "/":
                while i < n and text[i] != "\n":
                    i += 1
                continue
            # Block comment (Swift allows nesting)
            if ch == "/" and i + 1 < n and text[i + 1] == "*":
                depth = 1
                i += 2
                while i < n and depth:
                    if text[i] == "\n":
                        line += 1
                    elif text[i] == "/" and i + 1 < n and text[i + 1] == "*":
                        depth += 1
                        i += 1
                    elif text[i] == "*" and i + 1 < n and text[i + 1] == "/":
                        depth -= 1
                        i += 1
                    i += 1
                continue
            # Raw string #"..."#
            if ch == "#" and i + 1 < n and text[i + 1] == '"':
                i += 2
                while i < n and not (text[i] == '"' and i + 1 < n and text[i + 1] == "#"):
                    if text[i] == "\n":
                        line += 1
                    i += 1
                i += 2
                continue
            # Ordinary / multiline string
            if ch == '"':
                if text.startswith('"""', i):
                    i += 3
                    while i < n and not text.startswith('"""', i):
                        if text[i] == "\n":
                            line += 1
                        i += 1
                    i += 3
                    continue
                i += 1
                while i < n and text[i] != '"':
                    if text[i] == "\\":
                        i += 1
                    elif text[i] == "\n":
                        line += 1
                    i += 1
                i += 1
                continue
            if ch in openers:
                stack.append((ch, line))
            elif ch in pairs:
                if not stack:
                    failures.append(
                        f"[balance] {path.relative_to(ROOT)}:{line} unmatched closing '{ch}'"
                    )
                    break
                opener, opened_at = stack.pop()
                if opener != pairs[ch]:
                    failures.append(
                        f"[balance] {path.relative_to(ROOT)}:{line} '{ch}' closes "
                        f"'{opener}' opened on line {opened_at}"
                    )
                    break
            i += 1
        else:
            if stack:
                opener, opened_at = stack[-1]
                failures.append(
                    f"[balance] {path.relative_to(ROOT)} unclosed '{opener}' "
                    f"opened on line {opened_at}"
                )


def check_no_false_verification_claims() -> None:
    """
    Guards the project's central honesty rule: no source file may describe
    itself as verified, working or production-ready.
    """
    # Only the uppercase status token counts as a claim. Lower-case prose such
    # as "not yet verified" or "until the capability is verified" is a
    # disclaimer, which is exactly what this project wants in the source.
    negating = re.compile(
        r"\b(not|never|unless|until|no|requires?|pending|awaiting)\b|REQUIRES_|_LINUX|VERIFICATION_LEDGER",
        re.IGNORECASE,
    )
    for path in swift_files(CORE) + swift_files(IOS):
        for line_number, line in enumerate(path.read_text().splitlines(), start=1):
            if re.search(r"\bVERIFIED\b", line) and not negating.search(line):
                failures.append(
                    f"[honesty] {path.relative_to(ROOT)}:{line_number} "
                    "asserts VERIFIED status in source; verification belongs in the ledger"
                )
            if re.search(r"\bproduction[- ]ready\b", line, re.IGNORECASE):
                failures.append(
                    f"[honesty] {path.relative_to(ROOT)}:{line_number} claims production-ready"
                )


def summarise() -> None:
    core = swift_files(CORE)
    ios = swift_files(IOS)
    tests = swift_files(TESTS)
    notes.append(f"PromptCamCore:  {len(core)} files, {sum(len(p.read_text().splitlines()) for p in core)} lines")
    notes.append(f"PromptCamiOS:   {len(ios)} files, {sum(len(p.read_text().splitlines()) for p in ios)} lines")
    notes.append(f"Tests:          {len(tests)} files, {sum(len(p.read_text().splitlines()) for p in tests)} lines")
    platform = swift_files(PLATFORM)
    notes.append(f"Platform/ (unverified API surface): {len(platform)} files")
    test_count = 0
    for path in tests:
        test_count += len(re.findall(r"^\s*@Test", path.read_text(), re.MULTILINE))
    notes.append(f"Declared test cases: {test_count}")


def main() -> int:
    check_core_imports()
    check_duo_symbol_isolation()
    check_device_detection()
    check_validation_markers()
    check_bracket_balance()
    check_no_false_verification_claims()
    summarise()

    print("PromptCam static review")
    print("=" * 60)
    for note in notes:
        print(f"  {note}")
    print("-" * 60)

    if failures:
        print(f"FAILED — {len(failures)} issue(s):\n")
        for failure in failures:
            print(f"  ✗ {failure}")
        print(
            "\nNote: passing this review does NOT mean the code compiles. "
            "It means the architectural invariants hold. Compilation is REQUIRES_MAC."
        )
        return 1

    print("PASSED — all architectural invariants hold.")
    print(
        "\nThis proves structure, not correctness. The code has never been "
        "compiled against an Apple SDK. Compilation is REQUIRES_MAC."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
