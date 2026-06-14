"""
build_db.py - AP Electoral Roll PDF -> SQLite Database

Usage:
    # With name lookup (100% accurate names)
    python build_db.py pdfs output/dhone.db --lookup output/voter_names_lookup.json

    # With CID map (partial names ~37%)
    python build_db.py pdfs output/dhone.db --cid-map output/cid_map.json

    # Basic (partial Telugu names)
    python build_db.py pdfs output/dhone.db
"""

import sys, os, re, sqlite3, time, glob, json
import pdfplumber

# ── Global maps (loaded from files) ──────────────────────────────────────────
CID_MAP    = {}  # cid -> Telugu string
NAME_LOOKUP = {}  # "part_serial" -> {n, nk, r, rn, rk, g}


# ── CID decoding ──────────────────────────────────────────────────────────────
def apply_cid_map(text):
    if not text:
        return ''
    result = text
    for cid, chars in sorted(CID_MAP.items(), key=lambda x: -len(x[1])):
        result = result.replace('(cid:' + cid + ')', chars)
    result = re.sub(r'\(cid:\d+\)', '', result)
    result = result.replace('\uffff', '').replace('\ufffe', '')
    result = result.replace('\u0C46\u0C56', '\u0C48')
    return re.sub(r'\s+', ' ', result).strip()


# ── House normalization ───────────────────────────────────────────────────────
def norm_house(house):
    h = house.strip()
    if re.match(r'^-+$', h):
        return ''
    h = h.replace('/', '-').lstrip('-').strip().lower()
    return ('-' + h + '-') if h else ''


# ── Part number ───────────────────────────────────────────────────────────────
def extract_part_number(filename):
    m = re.search(r'_(\d+)\.pdf$', filename, re.IGNORECASE)
    return int(m.group(1)) if m else 0


# ── Gender ────────────────────────────────────────────────────────────────────
FEMALE_PARTS = {55, 58, 59, 61, 63, 65, 69, 72, 73, 76, 77}
MALE_PARTS   = {54, 56, 57, 60, 62, 64, 68, 70, 71, 74, 75}

def get_gender(part_num, cell_text):
    if part_num in FEMALE_PARTS:
        return 'స్త్రీ'
    if part_num in MALE_PARTS:
        return 'పు'
    t = re.sub(r'\(cid:\d+\)', '', str(cell_text or '')).strip()
    if 'మ' in t:
        return 'స్త్రీ'
    return 'పు'


# ── Page extraction ───────────────────────────────────────────────────────────
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


# ── PDF processing ────────────────────────────────────────────────────────────
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
                        if sum(1 for c in line if '\u0C00' <= c <= '\u0C7F') > 3:
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


# ── Name resolution ───────────────────────────────────────────────────────────
def resolve_name(voter):
    """
    Get name for voter using best available method:
    1. Lookup from reference DB (100% accurate)
    2. CID map decoding (partial)
    3. Raw PDF text (fallback)
    """
    key = str(voter['part']) + '_' + str(voter['serial'])
    
    if NAME_LOOKUP and key in NAME_LOOKUP:
        ref = NAME_LOOKUP[key]
        return {
            'name':     ref['n'],
            'name_key': ref['nk'],
            'rel':      ref.get('r', voter['rel']),
            'rel_name': ref['rn'],
            'rel_key':  ref['rk'],
            'gender':   ref.get('g', voter['gender']),
        }
    
    # Fall back to CID map
    name     = apply_cid_map(voter['name'])
    rel_name = apply_cid_map(voter['rel_name'])
    rel      = apply_cid_map(voter['rel'])
    
    return {
        'name':     name,
        'name_key': name.lower(),
        'rel':      rel,
        'rel_name': rel_name,
        'rel_key':  rel_name.lower(),
        'gender':   voter['gender'],
    }


# ── Database ──────────────────────────────────────────────────────────────────
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
        house_norm = norm_house(v['house'])
        resolved   = resolve_name(v)
        conn.execute('''
            INSERT INTO voters
            (part, serial, page, house, house_norm,
             name, name_key, rel, rel_name, rel_key,
             gender, age, epic)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        ''', (
            v['part'], v['serial'], v['page'],
            v['house'], house_norm,
            resolved['name'],     resolved['name_key'],
            resolved['rel'],
            resolved['rel_name'], resolved['rel_key'],
            resolved['gender'],   v['age'], v['epic'],
        ))


# ── Test ──────────────────────────────────────────────────────────────────────
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
        "SELECT COUNT(*) FROM voters WHERE epic!='' "
        "AND epic!='00000000000000' AND epic NOT LIKE '%000000'"
    ).fetchone()[0]
    print(f'Total  : {total}')
    print(f'Male   : {male}')
    print(f'Female : {female}')
    print(f'Parts  : {parts}')
    print(f'EPICs  : {epic}')

    print('\n--- House search: 22-42 ---')
    rows = conn.execute(
        "SELECT serial, part, house, name FROM voters "
        "WHERE house_norm LIKE '%-22-42-%' "
        "ORDER BY house_norm, serial LIMIT 6"
    ).fetchall()
    print(f'Results: {len(rows)}')
    for r in rows:
        print(f'  serial={r[0]:4d} part={r[1]} house={r[2]!r:15} name={r[3]!r}')

    print('\n--- Sample names ---')
    rows2 = conn.execute(
        "SELECT name, name_key FROM voters WHERE name!='' LIMIT 8"
    ).fetchall()
    for r in rows2:
        print(f'  name={r[0]!r:35} key={r[1]!r}')
    print('='*55)
    conn.close()


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    args          = sys.argv[1:]
    lookup_file   = None
    cid_map_file  = None

    if '--lookup' in args:
        idx          = args.index('--lookup')
        lookup_file  = args[idx+1]
        args         = args[:idx] + args[idx+2:]

    if '--cid-map' in args:
        idx          = args.index('--cid-map')
        cid_map_file = args[idx+1]
        args         = args[:idx] + args[idx+2:]

    input_path = args[0] if args else 'pdfs'
    db_path    = args[1] if len(args) > 1 else 'voters.db'

    # Load name lookup
    if lookup_file and os.path.exists(lookup_file):
        print('Loading name lookup: ' + lookup_file)
        with open(lookup_file, encoding='utf-8') as f:
            NAME_LOOKUP.update(json.load(f))
        print(f'Loaded {len(NAME_LOOKUP)} name records -> 100% accurate names!')
    elif cid_map_file and os.path.exists(cid_map_file):
        with open(cid_map_file, encoding='utf-8') as f:
            CID_MAP.update(json.load(f))
        print(f'Loaded CID map: {len(CID_MAP)} entries (~37% name accuracy)')
    else:
        print('No name source provided - names will be partial Telugu')
        print('Tip: use --lookup voter_names_lookup.json for 100% names')

    # Find PDFs
    pdfs = sorted(glob.glob(os.path.join(input_path, '**/*.pdf'), recursive=True))
    if not pdfs:
        pdfs = sorted(glob.glob(os.path.join(input_path, '*.pdf')))
    if not pdfs:
        print('No PDFs found in ' + input_path)
        sys.exit(1)

    if os.path.exists(db_path):
        os.remove(db_path)
        print('Removed old ' + db_path)

    print(f'Found {len(pdfs)} PDFs -> {db_path}')
    conn  = create_db(db_path)
    total = 0
    start = time.time()

    for i, pdf_path in enumerate(pdfs, 1):
        fname = os.path.basename(pdf_path)
        print(f'[{i}/{len(pdfs)}] {fname} ... ', end='', flush=True)
        part_num, voters, part_info = process_pdf(pdf_path)
        insert_part(conn, part_info)
        insert_voters(conn, voters)
        conn.commit()
        total += len(voters)
        m = part_info['male']
        f = part_info['female']

        # Check how many got names from lookup
        if NAME_LOOKUP:
            matched = sum(1 for v in voters 
                         if str(v['part'])+'_'+str(v['serial']) in NAME_LOOKUP)
            print(f'{len(voters)} voters (M:{m} F:{f}) names:{matched}/{len(voters)}')
        else:
            print(f'{len(voters)} voters (M:{m} F:{f})')

    elapsed = time.time() - start
    print(f'\nDone in {round(elapsed,1)}s | Total: {total} | DB: {db_path}')
    conn.close()
    test_db(db_path)


if __name__ == '__main__':
    main()