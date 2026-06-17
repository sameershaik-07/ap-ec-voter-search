import sys, sqlite3

db_path  = sys.argv[1]
ref_path = sys.argv[2]

print("Loading reference DB...")
ref = sqlite3.connect(ref_path)
ref_data = {}
for part, serial, name, name_key, rel, rel_name, rel_key in ref.execute(
    "SELECT part, serial, name, name_key, rel, rel_name, rel_key FROM voters"
).fetchall():
    ref_data[(part, serial)] = (name, name_key, rel, rel_name, rel_key)
ref.close()
print("Reference records:", len(ref_data))

our = sqlite3.connect(db_path)
rows = our.execute("SELECT id, part, serial FROM voters").fetchall()
print("Our DB records:", len(rows))

updated = not_found = 0
for row_id, part, serial in rows:
    key = (part, serial)
    if key in ref_data:
        name, name_key, rel, rel_name, rel_key = ref_data[key]
        our.execute(
            "UPDATE voters SET name=?, name_key=?, rel=?, rel_name=?, rel_key=? WHERE id=?",
            (name, name_key, rel, rel_name, rel_key, row_id)
        )
        updated += 1
    else:
        not_found += 1

our.commit()
print("Updated:", updated)
print("Not found:", not_found)

print("\nSample names after merge:")
for r in our.execute("SELECT part, serial, name, name_key FROM voters WHERE part=58 AND serial BETWEEN 105 AND 108").fetchall():
    print(" ", r)

our.close()
print("Done!")
