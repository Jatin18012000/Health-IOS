#!/usr/bin/env python3
"""Validate the character rig against the app that has to load it.

Run after any change to the model, and before trusting a delivery:

    python3 tools/check_character.py

The Cubism Core is not available here, so this checks everything that is
checkable from the files alone: that the references resolve, that the declared
counts match the arrays they describe, that every parameter the physics and the
manifest name actually exists in the compiled `.moc3`, and that the twelve
parameters `Live2DRenderer` drives are all present.

What it cannot check is how any of it *looks* -- whether `ParamMouthOpenY`
deforms smoothly across its range, and whether the physics values are tuned
rather than merely valid. Both need Cubism Viewer or the renderer running. See
`docs/CHARACTER_DELIVERY_REPORT.md`.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARACTER = os.path.join(ROOT, "Resources", "Characters", "aura", "runtime")
SWIFT = os.path.join(ROOT, "Sources", "AURACharacter", "CharacterManifest.swift")

GREEN, RED, DIM, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[0m"


class Checks:
    def __init__(self):
        self.passed = 0
        self.failures = []

    def check(self, label, got, want, why=None):
        if got == want:
            self.passed += 1
            print(f"  {GREEN}pass{RESET}  {label}")
        else:
            self.failures.append(label)
            print(f"  {RED}FAIL{RESET}  {label}")
            print(f"        got {got!r}, want {want!r}")
            if why:
                print(f"        {DIM}{why}{RESET}")


def moc_parameters(path):
    """Parameter IDs embedded in the compiled rig.

    The `.moc3` is a binary with no public schema, but parameter IDs are stored
    as plain ASCII, so pulling printable runs out of it is enough to answer the
    only question asked here: does this ID exist in the rig at all. Done in pure
    Python rather than shelling out to `strings`, so the check runs anywhere.
    """
    with open(path, "rb") as f:
        blob = f.read()
    return {match.decode("ascii")
            for match in re.findall(rb"Param[A-Za-z0-9_]{1,40}", blob)}


def required_parameters():
    """The list `Live2DRenderer` drives, read from the Swift rather than retyped.

    Retyping it here would let the two drift, and a rig missing a parameter
    fails silently -- the renderer sets a value nothing is listening to.
    """
    with open(SWIFT) as f:
        source = f.read()
    block = source.split("public static let required = [", 1)[1].split("]", 1)[0]
    return re.findall(r'"(Param[A-Za-z0-9_]+)"', block)


def main():
    c = Checks()

    manifest_path = os.path.join(CHARACTER, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"{RED}no manifest at {manifest_path}{RESET}")
        return 1
    manifest = json.load(open(manifest_path))

    print("\nManifest")
    c.check("renderer is one the app knows",
            manifest.get("renderer") in ("procedural", "live2d"), True)

    if manifest.get("renderer") == "procedural":
        print(f"\n{DIM}procedural renderer: no rig to check{RESET}")
        return 0 if not c.failures else 1

    assets = os.path.join(CHARACTER, manifest["assetPath"])
    c.check("assetPath exists", os.path.isdir(assets), True,
            "CharacterStageView resolves this relative to the character directory")

    models = [f for f in os.listdir(assets) if f.endswith(".model3.json")]
    c.check("exactly one .model3.json", len(models), 1,
            "the bridge is handed a directory and has to pick one entry point")
    if len(models) != 1:
        return 1
    model = json.load(open(os.path.join(assets, models[0])))

    print("\nFile references")
    refs = model.get("FileReferences", {})
    for key, value in refs.items():
        for rel in ([value] if isinstance(value, str) else value):
            c.check(f"{key} -> {rel}", os.path.exists(os.path.join(assets, rel)), True)

    moc = os.path.join(assets, refs["Moc"])
    with open(moc, "rb") as f:
        c.check("moc3 magic", f.read(4), b"MOC3")
    with open(moc, "rb") as f:
        version = f.read(5)[4]
    print(f"  {DIM}moc3 format version {version}"
          f"{' -- needs Cubism SDK 5.3 or newer' if version >= 6 else ''}{RESET}")

    print("\nParameters the renderer drives")
    present = moc_parameters(moc)
    for param in required_parameters():
        c.check(param, param in present, True,
                "declared in CharacterManifest.required; absent means the "
                "renderer drives a parameter nothing is listening to")

    print("\nManifest parameter list matches the rig")
    declared = set(manifest.get("parameters") or [])
    c.check("no parameter claimed that the rig lacks",
            sorted(declared - present), [],
            "missingParameters() would report a clean rig while the SDK sees "
            "something else")

    print("\nPhysics")
    if "Physics" not in refs:
        c.check("physics file referenced", False, True,
                "no Physics key in model3.json -- the hair will not move; see "
                "docs/CHARACTER_DELIVERY_REPORT.md")
    else:
        physics = json.load(open(os.path.join(assets, refs["Physics"])))
        meta, settings = physics["Meta"], physics["PhysicsSettings"]

        # These counts are what the SDK pre-allocates from. A mismatch is not a
        # cosmetic error.
        c.check("PhysicsSettingCount", meta["PhysicsSettingCount"], len(settings))
        c.check("TotalInputCount", meta["TotalInputCount"],
                sum(len(s["Input"]) for s in settings))
        c.check("TotalOutputCount", meta["TotalOutputCount"],
                sum(len(s["Output"]) for s in settings))
        c.check("VertexCount", meta["VertexCount"],
                sum(len(s["Vertices"]) for s in settings))

        used = set()
        for s in settings:
            used |= {i["Source"]["Id"] for i in s["Input"]}
            used |= {o["Destination"]["Id"] for o in s["Output"]}
        c.check("every parameter physics names exists in the rig",
                sorted(used - present), [])

        for s in settings:
            for o in s["Output"]:
                c.check(f"{s['Id']} VertexIndex in range",
                        0 <= o["VertexIndex"] < len(s["Vertices"]), True)

        driven = [o["Destination"]["Id"] for s in settings for o in s["Output"]]
        c.check("no parameter driven by two physics settings",
                sorted({d for d in driven if driven.count(d) > 1}), [],
                "two settings fighting over one parameter is a jitter that is "
                "very hard to diagnose later")

    total = c.passed + len(c.failures)
    print()
    if c.failures:
        print(f"{RED}{len(c.failures)} of {total} checks failed{RESET}")
        return 1
    print(f"{GREEN}all {total} checks passed{RESET}")
    print(f"{DIM}appearance is not checked here -- drag ParamMouthOpenY slowly "
          f"in Cubism Viewer{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
