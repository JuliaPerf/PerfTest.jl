#!/usr/bin/env python3
"""
Parse piped input of the form:

[header lines]
--
Metric: [Metric name] [Units]
   = [Float]
--
Metric: [Metric name] [Units]
   = [Float]
--
...

and emit:

name = "..."
units = "..."
values = [...]
"""
import sys
import re

METRIC_RE = re.compile(r'Metric:\s*(.+?)\s*\[([^\]]*)\]')
VALUE_RE  = re.compile(r'=\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)')

def main():
    data = sys.stdin.read()
    blocks = data.split('--')

    name = None
    units = None
    values = []

    for block in blocks:
        m = METRIC_RE.search(block)
        if m and name is None:
            name = m.group(1).strip()
            units = m.group(2).strip()

        v = VALUE_RE.search(block)
        if v:
            values.append(float(v.group(1)))

    if name is None:
        print("# No metric found in input", file=sys.stderr)
        sys.exit(1)

    print(f'name = "{name}"')
    print(f'units = "{units}"')
    print(f'values = {values}')

if __name__ == '__main__':
    main()
