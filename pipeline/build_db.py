"""
build_db.py - AP Electoral Roll PDF -> SQLite Database
Run: python build_db.py <pdf_folder> <output.db>
Example: python build_db.py pdfs output/dhone.db
"""

import sys, os, re, sqlite3, time, glob
import pdfplumber


def strip_cids(text):
    """Remove (cid:XXX) tags, keep real Unicode chars"""
    if not text:
        return ''
    text = re.sub(r'\(cid:\d+\)', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()


def norm_house(house):
    """
    Normalize house number with boundary markers.
    Store as '-7-2-' so searching '-7-2-' finds:
      7-2, 7-2/3, 7-2-1, 20-63-7-2
    But NOT: 6-57-2, 6-97-2

    Examples:
      22/44/1  -> -22-44-1-
      7-2      -> -7-2-
      ----     -> empty
    """
    h = house.strip()
    if re.match(r'^-+$', h):
        return ''
    h = h.replace('/', '-')
    h = h.lstrip('-').strip().lower()
    if not h:
        return ''
    return '-' + h + '-'


def extract_part_number(filename):
    m = re.search(r'_(\d+)\.pdf$', filename, re.IGNORECASE)
    return int(m.group(1)) if m else 0


# AP 2002 Dhone AC-181 gender-segregated parts
FEMALE_PARTS = {55, 58, 59, 61, 63, 65, 69, 72, 73, 76, 77}
MALE_PARTS   = {54, 56, 57, 60, 62, 64, 68, 70, 71, 74, 75}

def get_gender(part_num, cell_text):
    if part_num in FEMALE_PARTS:
        return 'స్త్రీ'
    if part_num in MALE_PARTS:
        return 'పు'
    t = strip_cids(str(cell_text or ''))
    if 'మ' in t:
        return 'స్త్రీ'
    return 'పు'


def extract_page(pdf_page, part_num):
    rows  = []
    table = pdf_page.extract_table()
    if not table:
        return rows
    for row in table:
        if not row or not row[0]:
            continue
        serial_str = str(row[0]).strip()
        if not serial_str.isdigit():
            continue
        try:
            rows.append({
                'serial':   int(serial_str),
                'house':    str(row[1] or '').strip().replace('\n', ' '),
                'name':     str(row[2] or '').strip().replace('\n', ' '),
                'rel':      str(row[3] or '').strip(),
                'rel_name': str(row[4] or '').strip().replace('\n', ' '),
                'gender':   get_gender(part_num, row[5]),
                'age':      str(row[6] or '').strip(),
                'epic':     str(row[7] or '').strip(),
            })
        except Exception:
            pass
    return rows


def process_pdf(pdf_path):
    filename = os.path.basename(pdf_path)
    part_num = extract_part_number(filename)
    voters   = []
    village  = ''
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page_num, page in enumerate(pdf.pages):
                if page_num == 0:
                    text = page.extract_text() or ''
                    for line in text.split('\n'):
                        line = line.strip()
                        telugu = sum(1 for c in line if '\u0C00' <= c <= '\u0C7F')
                        if telugu > 3:
                            village = line
                            break
                    continue
                rows = extract_page(page, part_num)
                for r in rows:
                    r['page'] = page_num + 1
                    r['part'] = part_num
                    voters.append(r)
    except Exception as e:
        print('  Error: ' + str(e))

    male   = sum(1 for v in voters if v['gender'] == 'పు')
    female = sum(1 for v in voters if v['gender'] == 'స్త్రీ')
    return part_num, voters, {
        'part':    part_num,
        'village': village or ('Part ' + str(part_num)),
        'male':    male,
        'female':  female,
        'total':   male + female,
    }


def create_db(db_path):
    conn = sqlite3.connect(db_path)
    conn.executescript('''
        CREATE TABLE IF NOT EXISTS parts (
            part    INTEGER PRIMARY KEY,
            village TEXT NOT NULL,
            male    INTEGER DEFAULT 0,
            female  INTEGER DEFAULT 0,
            total   INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS voters (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            part        INTEGER NOT NULL,
            serial      INTEGER NOT NULL,
            page        INTEGER NOT NULL,
            house       TEXT NOT NULL DEFAULT "",
            house_norm  TEXT NOT NULL DEFAULT "",
            name        TEXT NOT NULL DEFAULT "",
            name_key    TEXT NOT NULL DEFAULT "",
            rel         TEXT NOT NULL DEFAULT "",
            rel_name    TEXT NOT NULL DEFAULT "",
            rel_key     TEXT NOT NULL DEFAULT "",
            gender      TEXT NOT NULL DEFAULT "",
            age         TEXT NOT NULL DEFAULT "",
            epic        TEXT NOT NULL DEFAULT ""
        );
        CREATE INDEX IF NOT EXISTS idx_house    ON voters(house_norm);
        CREATE INDEX IF NOT EXISTS idx_part_ser ON voters(part, serial);
        CREATE INDEX IF NOT EXISTS idx_name_key ON voters(name_key);
        CREATE INDEX IF NOT EXISTS idx_rel_key  ON voters(rel_key);
        CREATE INDEX IF NOT EXISTS idx_epic     ON voters(epic);
        CREATE INDEX IF NOT EXISTS idx_gender   ON voters(gender);
    ''')
    conn.commit()
    return conn


def insert_part(conn, info):
    conn.execute('''
        INSERT OR REPLACE INTO parts (part, village, male, female, total)
        VALUES (:part, :village, :male, :female, :total)
    ''', info)


def insert_voters(conn, voters):
    for v in voters:
        house_norm    = norm_house(v['house'])
        clean_name    = strip_cids(v['name'])
        clean_relname = strip_cids(v['rel_name'])
        conn.execute('''
            INSERT INTO voters
            (part, serial, page, house, house_norm,
             name, name_key, rel, rel_name, rel_key,
             gender, age, epic)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        ''', (
            v['part'], v['serial'], v['page'],
            v['house'], house_norm,
            clean_name, clean_name.lower(),
            strip_cids(v['rel']),
            clean_relname, clean_relname.lower(),
            v['gender'], v['age'], v['epic'],
        ))


def test_db(db_path):
    conn = sqlite3.connect(db_path)
    print('\n' + '='*55)
    print('LOCAL TEST RESULTS')
    print('='*55)

    total  = conn.execute('SELECT COUNT(*) FROM voters').fetchone()[0]
    male   = conn.execute("SELECT COUNT(*) FROM voters WHERE gender='పు'").fetchone()[0]
    female = conn.execute("SELECT COUNT(*) FROM voters WHERE gender='స్త్రీ'").fetchone()[0]
    parts  = conn.execute('SELECT COUNT(*) FROM parts').fetchone()[0]
    epic   = conn.execute(
        "SELECT COUNT(*) FROM voters WHERE epic != '' "
        "AND epic != '00000000000000' AND epic NOT LIKE '%000000'"
    ).fetchone()[0]
    print(f'Total voters : {total}')
    print(f'Male         : {male}')
    print(f'Female       : {female}')
    print(f'Parts        : {parts}')
    print(f'Valid EPICs  : {epic}')

    def house_search(q):
        norm = '-' + q.replace('/', '-').lower() + '-'
        return conn.execute(
            "SELECT serial, part, house, name FROM voters "
            "WHERE house_norm LIKE ? "
            "ORDER BY house_norm, serial LIMIT 8",
            ['%' + norm + '%']
        ).fetchall()

    print('\n--- House search: 7-2 (should NOT show 6-57-2) ---')
    rows = house_search('7-2')
    print(f'Results: {len(rows)}')
    for r in rows:
        print(f'  serial={r[0]:4d} part={r[1]} house={r[2]!r:18} name={r[3]!r}')

    print('\n--- House search: 22-42 ---')
    rows2 = house_search('22-42')
    print(f'Results: {len(rows2)}')
    for r in rows2:
        print(f'  serial={r[0]:4d} part={r[1]} house={r[2]!r:18} name={r[3]!r}')

    print('\n--- House search: 22/44 ---')
    rows3 = house_search('22/44')
    print(f'Results: {len(rows3)}')
    for r in rows3:
        print(f'  serial={r[0]:4d} part={r[1]} house={r[2]!r:18} name={r[3]!r}')

    print('\n--- Sample name_keys ---')
    rows4 = conn.execute(
        "SELECT name, name_key FROM voters WHERE name_key != '' LIMIT 8"
    ).fetchall()
    for r in rows4:
        print(f'  {r[0]!r:30} -> {r[1]!r}')

    print('='*55)
    conn.close()


def main():
    input_path = sys.argv[1] if len(sys.argv) > 1 else 'pdfs'
    db_path    = sys.argv[2] if len(sys.argv) > 2 else 'voters.db'

    pdfs = sorted(glob.glob(os.path.join(input_path, '**/*.pdf'), recursive=True))
    if not pdfs:
        pdfs = sorted(glob.glob(os.path.join(input_path, '*.pdf')))
    if not pdfs:
        print('No PDFs found in ' + input_path)
        sys.exit(1)

    if os.path.exists(db_path):
        os.remove(db_path)
        print('Removed old ' + db_path)

    print('Found ' + str(len(pdfs)) + ' PDFs -> ' + db_path)
    conn  = create_db(db_path)
    total = 0
    start = time.time()

    for i, pdf_path in enumerate(pdfs, 1):
        fname = os.path.basename(pdf_path)
        print('[' + str(i) + '/' + str(len(pdfs)) + '] ' + fname + ' ... ',
              end='', flush=True)
        part_num, voters, part_info = process_pdf(pdf_path)
        insert_part(conn, part_info)
        insert_voters(conn, voters)
        conn.commit()
        total += len(voters)
        m = part_info['male']
        f = part_info['female']
        print(str(len(voters)) + ' voters  (M:' + str(m) + '  F:' + str(f) + ')')

    elapsed = time.time() - start
    print('\n' + '='*55)
    print('Done in      : ' + str(round(elapsed, 1)) + 's')
    print('Total voters : ' + str(total))
    print('Database     : ' + db_path)
    print('Size         : ' + str(round(os.path.getsize(db_path)/1024/1024, 1)) + ' MB')
    conn.close()
    test_db(db_path)


if __name__ == '__main__':
    main()