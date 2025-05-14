#!/usr/bin/env python3
"""
Command-line interface for converting DOCX to RenPy script.
"""
import sys
import os
from renpy_doc_convert.api import convert


def main():
    if len(sys.argv) != 3:
        print("Usage: converter_cli.py <input.docx> <output.rpy>")
        sys.exit(1)
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    if not os.path.isfile(input_path):
        print(f"Error: Input file '{input_path}' does not exist.")
        sys.exit(1)
    try:
        convert(input_path, output_path)
        print(f"Conversion successful: {output_path}")
    except Exception as e:
        print(f"Conversion failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
