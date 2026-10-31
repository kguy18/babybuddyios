#!/usr/bin/env python3
"""Convert the six unmodified WHO expanded XLSX tables into the bundled daily data.

Usage: python3 scripts/import-who-growth.py /path/to/downloaded/tables
No dependencies; does not download anything or contact a server.
"""
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
BASE = "https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/"
SOURCES = [
    ("weight", "wfa", "weight-for-age/expanded-tables", "boys", "c2f79259_11"),
    ("weight", "wfa", "weight-for-age/expanded-tables", "girls", "54cfa5e8_9"),
    ("height", "lhfa", "length-height-for-age/expandable-tables", "boys", "bc36d818_9"),
    ("height", "lhfa", "length-height-for-age/expandable-tables", "girls", "478569a5_9"),
    ("headCircumference", "hcfa", "head-circumference-for-age/expanded-tables", "boys", "c266c88f_7"),
    ("headCircumference", "hcfa", "head-circumference-for-age/expanded-tables", "girls", "71b282d1_13"),
]


def read_table(path):
    with zipfile.ZipFile(path) as archive:
        strings = ["".join(x.itertext()) for x in ET.fromstring(
            archive.read("xl/sharedStrings.xml")).findall("s:si", NS)]
        rows = []
        for row in ET.fromstring(archive.read("xl/worksheets/sheet1.xml")).findall(".//s:row", NS):
            cells = {}
            for cell in row:
                value = cell.find("s:v", NS)
                if value is not None:
                    cells[''.join(c for c in cell.attrib['r'] if c.isalpha())] = (
                        strings[int(value.text)] if cell.attrib.get("t") == "s" else value.text)
            rows.append(cells)
        headers = rows[0]
        headers = {k: ("Age" if v == "Day" else v) for k, v in headers.items()}
        columns = [next(k for k, v in headers.items() if v == name)
                   for name in ["Age", "L", "M", "S", "P3", "P15", "P50", "P85", "P97"]]
        data = [[float(row[c]) for c in columns] for row in rows[1:] if columns[0] in row]
        assert len(data) == 1857
        assert [row[0] for row in data] == list(range(1857))
        return [[int(row[0])] + [round(v, 8) for v in row[1:]] for row in data]


def main():
    folder = Path(sys.argv[1])
    tables = []
    for metric, prefix, directory, sex, version in SOURCES:
        name = f"{prefix}-{sex}-percentiles-expanded-tables.xlsx"
        path = folder / name
        tables.append({"metric": metric, "sex": sex,
                       "source": f"{BASE}{directory}/{name}?sfvrsn={version}",
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                       "rows": read_table(path)})
    output = Path(__file__).resolve().parents[1] / "Sources/Resources/who-growth-reference.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"columns": ["day", "L", "M", "S", "P3", "P15", "P50", "P85", "P97"],
                                  "tables": tables}, separators=(",", ":")) + "\n")
    print(f"Wrote {len(tables)} tables, 11142 daily rows to {output.name}")


if __name__ == "__main__":
    main()
