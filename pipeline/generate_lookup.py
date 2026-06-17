"""
generate_lookup.py
Generates voter_names_lookup.json from reference.db
Run: python pipeline/generate_lookup.py reference.db output/voter_names_lookup.json
"""
import sys, sqlite3, json, os

def main():
    ref_db   = sys.argv[1] if len(sys.argv) > 1 else 'reference.db'
    out_path = sys.argv[2] if len(sys.argv) > 2 else 'output/voter_names_lookup.json'

    print(f"Loading: {ref_db}")
    conn = sqlite3.connect(ref_db)

    rows = conn.execute(
        "SELECT part, serial, name, name_key, rel, rel_name, rel_key, gender "
        "FROM voters"
    ).fetchall()
    conn.close()

    print(f"Records: {len(rows)}")

    lookup = {}
    for part, serial, name, name_key, rel, rel_name, rel_key, gender in rows:
        key = str(part) + '_' + str(serial)
        lookup[key] = {
            "n":  name,
            "nk": name_key,
            "r":  rel,
            "rn": rel_name,
            "rk": rel_key,
            "g":  gender,
        }

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(lookup, f, ensure_ascii=False, separators=(',', ':'))

    size = os.path.getsize(out_path) / 1024 / 1024
    print(f"Saved: {out_path} ({size:.1f} MB)")
    print(f"Entries: {len(lookup)}")
    print("Done!")

if __name__ == '__main__':
    main()