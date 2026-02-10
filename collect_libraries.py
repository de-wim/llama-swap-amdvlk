#!/usr/bin/env python3
"""
Recursively collect all required libraries for a binary using ldd.
Collects them into a single directory.
"""

import os
import shutil
import subprocess
import sys
from typing import List, Set

VDSOS = ["linux-vdso.so.1"]


def run_ldd(binary_path: str) -> List[str]:
    """Run ldd on a binary and return list of library paths."""
    try:
        result = subprocess.run(
            ["ldd", binary_path], capture_output=True, text=True, check=True
        )
        return result.stdout.strip().split("\n")
    except subprocess.CalledProcessError as e:
        print(f"Error running ldd on {binary_path}: {e}")
        return []
    except FileNotFoundError:
        print("ldd command not found. Please ensure it's installed.")
        return []


def parse_ldd_output(ldd_output: List[str]) -> List[str]:
    """Parse ldd output to extract library paths."""
    libraries = []
    for line in ldd_output:
        if "=>" in line:
            # Format: libname.so => /path/to/libname.so (0x...)
            parts = line.split("=>")
            if len(parts) >= 2:
                lib_path = parts[1].split()[0].strip()
                if lib_path and lib_path != "not" and lib_path != "found":
                    libraries.append(lib_path)
        elif line.strip() and not line.startswith("\t"):
            # Direct library reference (no =>)
            lib_path = line.split()[0].strip()
            libraries.append(lib_path)
    return libraries


def collect_libraries_recursive(
    binary_path: str,
    output_dir: str,
    collected: Set[str] = None,
    processed: Set[str] = None,
) -> None:
    """Recursively collect all libraries required by a binary."""
    if collected is None:
        collected = set()
    if processed is None:
        processed = set()

    # Skip if already processed
    if binary_path in processed:
        return

    processed.add(binary_path)

    # Get libraries for this binary
    ldd_output = run_ldd(binary_path)
    libraries = parse_ldd_output(ldd_output)

    for lib_path in libraries:
        if lib_path in VDSOS:
            # VDSO is a virtual dynamic shared object, not a real file
            continue

        if not os.path.exists(lib_path):
            print(f"Warning: library not found: '{lib_path}'")
            continue

        if lib_path in collected:
            continue

        # Copy library to output directory
        try:
            lib_name = os.path.basename(lib_path)
            dest_path = os.path.join(output_dir, lib_name)

            # Handle name conflicts by adding suffix
            if os.path.exists(dest_path):
                continue

            shutil.copy2(lib_path, dest_path)
            print(f"Collected {lib_path}")
            collected.add(lib_path)

            # Recursively process this library's dependencies
            collect_libraries_recursive(dest_path, output_dir, collected, processed)

        except Exception as e:
            print(f"Error copying {lib_path}: {e}")


def main():
    if len(sys.argv) != 3:
        print("Usage: python collect_libraries.py <binary_path> <output_directory>")
        sys.exit(1)

    binary_path = sys.argv[1]
    output_dir = sys.argv[2]

    # Validate inputs
    if not os.path.isfile(binary_path):
        print(f"Error: Binary not found: {binary_path}")
        sys.exit(1)

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    print(f"Collecting libraries for {binary_path} into {output_dir}")

    # Start collection
    collect_libraries_recursive(binary_path, output_dir)


if __name__ == "__main__":
    main()
