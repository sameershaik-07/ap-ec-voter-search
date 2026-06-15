"""
build_db.py - AP Electoral Roll PDF → SQLite Database
======================================================
Works with SINGLE merged PDF or MULTIPLE PDFs per constituency.
No reference APK needed. Uses CID map for Telugu name decoding.

Usage:
    # Single merged PDF
    python build_db.py path/to/constituency.pdf output/voters.db

    # Multiple PDFs in folder
    python build_db.py pdfs/ output/voters.db

    # With CID map for better names
    python build_db.py pdfs/ output/voters.db --cid-map output/cid_map.json
"""

import sys, os, re, sqlite3, time, glob, json, unicodedata
import pdfplumber

# ── CID Map (seed - covers all Telugu chars) ──────────────────────────────────
SEED_CID_MAP = {
    # Base consonants (low CID from font)
    '67':'క','68':'ఖ','69':'గ','70':'ఘ','72':'చ','74':'జ',
    '77':'ట','79':'డ','81':'ణ','82':'త','83':'థ','84':'ద',
    '85':'ధ','86':'న','87':'ప','88':'ఫ','89':'బ','90':'భ',
    '91':'మ','92':'య','93':'ర','95':'ల','96':'ళ','97':'వ',
    '98':'శ','99':'ష','100':'స','101':'హ',
    # Vowels
    '51':'ం','53':'అ','54':'ఆ','55':'ఇ','56':'ఈ','57':'ఉ',
    '61':'ఎ','62':'ఏ','63':'ఐ','65':'ఓ',
    # Matras
    '102':'ా','103':'ి','104':'ీ','105':'ు','106':'ూ',
    '107':'ృ','109':'ె','110':'ే','112':'ొ','113':'ో','115':'్',
    # Common high CIDs (from font + reference training)
    '130':'ా','131':'ా','132':'ా','133':'ా','135':'ా',
    '143':'ి','144':'ి','146':'ం','149':'ీ','150':'ీ',
    '158':'ు','159':'ు','160':'ు','161':'ు','162':'ూ',
    '164':'ూ','165':'ూ','166':'ు','167':'ు','170':'ూ','173':'ు','174':'ూ',
    '178':'ె','182':'ె','183':'ె','187':'ె','189':'్టె',
    '192':'ై','195':'ే','196':'ే','200':'ే','204':'ే','206':'ే',
    '243':'ొ','245':'ొ','253':'ొ',
    '271':'ో','272':'ో','275':'ో','278':'ౌ','279':'ౌ','286':'ౌ',
    '293':'కె','294':'గౌ','296':'చా','297':'ఛో','299':'ఠ',
    '300':'డి','302':'త','303':'థ','304':'ద','305':'ధా',
    '306':'నా','307':'ప','308':'ఫ','309':'భా','310':'మే',
    '311':'యి','312':'ర','313':'ళా','314':'వె','315':'శే',
    '316':'షేక్','317':'స','318':'హే',
    '336':'్క','338':'న్','339':'్గ','342':'్చ','344':'్జ',
    '347':'్ట','349':'్డ','351':'్ణ','352':'్త','353':'్థ',
    '354':'్ద','355':'్ధ','356':'్న','357':'్ప','358':'్ఫ',
    '359':'్బ','361':'్మ','362':'్య','364':'్రి','370':'్ఱ',
    '371':'్ల','372':'్ళ','373':'్వ','374':'్శ','375':'్ష',
    '376':'్స','377':'్హ','404':'్ర','408':'్ర',
    '470':'క్ష్','472':'క్ష్','489':'చి','493':'జి','494':'జీ',
    '495':'జు','496':'జూ','499':'తి','500':'తీ','501':'ని',
    '502':'నీ','503':'ప','504':'ఫ','505':'బి','506':'బీ',
    '507':'భి','508':'భీ','509':'మి','510':'మీ','511':'మొ',
    '512':'మో','513':'యొ','514':'యో','515':'లి','516':'లీ',
    '517':'ళి','518':'ళీ','519':'వి','520':'వీ','523':'శి',
    '524':'శీ','525':'ష','526':'స','527':'హా',
    '540':'క్షు','545':'క్','547':'గ్','549':'ఙ్','550':'చ్',
    '552':'జ్','555':'ట్','557':'డ్','559':'ణ్','560':'త్',
    '562':'ద్','564':'న్','565':'ప్','566':'ఫ్','567':'బ్',
    '569':'మ్','570':'య్','571':'ర్','573':'ల్','575':'వ్',
    '576':'శ్','577':'ష్','578':'స్','589':'క్ష్',
}

CID_MAP = dict(SEED_CID_MAP)

# ── Telugu name key generation ────────────────────────────────────────────────
def to_key(name):
    """Convert Telugu name to phonetic English search key"""
    if not name or not name.strip():
        return ''
    # If already English
    if all(ord(c) < 128 for c in name.strip()):
        return name.lower().strip()
    try:
        from indic_transliteration import sanscript
        from indic_transliteration.sanscript import transliterate
        IAST_MAP = [
            ('ā','a'),('ī','i'),('ū','u'),('ṭ','t'),('ḍ','d'),
            ('ṇ','n'),('ś','s'),('ṣ','s'),('ṁ','n'),('ṃ','n'),
            ('ḥ','h'),('ṛ','r'),('ñ','n'),('è','e'),('ò','o'),
        ]
        result = transliterate(name.strip(), sanscript.TELUGU, sanscript.IAST)
        for src, dst in IAST_MAP:
            result = result.replace(src, dst)
        result = result.lower()
        result = re.sub(r'[^a-z0-9 .]', '', result)
        return re.sub(r'\s+', ' ', result).strip()
    except Exception:
        return name.lower().strip()

# ── CID decoding ──────────────────────────────────────────────────────────────
def decode_cid(text):
    """Decode CID-encoded Telugu font text to Unicode"""
    if not text:
        return ''
    result = text
    for cid, char in sorted(CID_MAP.items(), key=lambda x: -len(x[1])):
        result = result.replace(f'(cid:{cid})', char)
    result = re.sub(r'\(cid:\d+\)', '', result)
    result = result.replace('\uffff', '').replace('\ufffe', '')
    result = result.replace('\u0C46\u0C56', '\u0C48')
    return re.sub(r'\s+', ' ', result).strip()

# ── House normalization ───────────────────────────────────────────────────────
def norm_house(house):
    h = house.strip()
    if not h or re.match(r'^[-]+$', h):
        return ''
    h = h.replace('/', '-').lstrip('-').strip().lower()
    return f'-{h}-' if h else ''

# ── Part/village detection from header page ───────────────────────────────────
def extract_header_info(page_text):
    """Extract part number and village name from PDF header.
    Village name sits between 'పేరు :' and 'పోలింగ్ కేంద్రం వర్గకరణ' in decoded text.
    Works for ALL AP 2002 ECI constituency PDFs.
    """
    part_num = None
    village  = ''

    raw_lines = [l.strip() for l in page_text.split('\n') if l.strip()]

    for line in raw_lines:
        decoded = decode_cid(line)

        # Extract part number - standalone digit line
        if re.match(r'^\d{1,3}$', decoded.strip()) and not part_num:
            n = int(decoded.strip())
            if 1 <= n <= 500:
                part_num = n

        # Village extraction - line contains polling center name
        # Pattern: '... పేరు : <VILLAGE> పోలింగ్ కేంద్రం వర్గకరణ ...'
        # After decode: '... పరు : <VILLAGE> పలిం కేంద్రం వర్గకరణ ...'
        # Use raw CID pattern to find village reliably
        if '(cid:307)(cid:208)ర' in line or 'పేరు' in decoded or 'పరు' in decoded:
            # Split on పేరు : or పరు :
            for sep in ['పేరు :', 'పేరు:', 'పరు :', 'పరు:']:
                if sep in decoded:
                    after = decoded.split(sep, 1)[1].strip()
                    # Village ends at next known keyword
                    for stop in ['పోలింగ్', 'పలిం', 'వర్గకరణ', 'వర్గ', 'రిజర్వేషన్']:
                        if stop in after:
                            v = after.split(stop)[0].strip()
                            if v and len(v) > 1:
                                village = v
                                break
                    if village:
                        break

    # Clean up village name - remove extra spaces around Telugu conjuncts
    if village:
        village = re.sub(r'\s+్', '్', village)   # remove space before halant
        village = re.sub(r'్\s+', '్', village)   # remove space after halant
        village = re.sub(r'\s+', ' ', village).strip()
    return part_num, village


# ── Gender determination ──────────────────────────────────────────────────────
def get_gender(part_num, gender_cell):
    """Detect gender from cell text.
    Male cell:   'ప(cid:173)'              -> starts with ప
    Female cell: '(cid:317)ీ(cid:352)(cid:364)' -> contains ీ (ord 3136)
    """
    raw = str(gender_cell or '')
    # Female: contains ీ character (ord 3136) which is part of స్త్రీ
    if '\u0C40' in raw:  # ీ
        return 'స్త్రీ'
    # Male: contains ప
    if '\u0C2A' in raw:  # ప
        return 'పు'
    # Fallback
    return 'పు'


# ── Extract part number from filename ────────────────────────────────────────
def part_from_filename(filename):
    m = re.search(r'_(\d+)\.pdf$', filename, re.IGNORECASE)
    return int(m.group(1)) if m else None

# ── Process a single PDF file ─────────────────────────────────────────────────
def process_pdf(pdf_path, verbose=True):
    """
    Process a PDF file — works for both:
    - Single-part PDFs (one part per file)
    - Merged PDFs (multiple parts in one file)
    Returns: list of (part_info_dict, [voter_dicts])
    """
    filename = os.path.basename(pdf_path)
    results  = []

    # Try to get part from filename first
    file_part = part_from_filename(filename)

    current_part    = file_part
    current_village = ''
    current_voters  = []
    current_page    = 0

    try:
        with pdfplumber.open(pdf_path) as pdf:
            total_pages = len(pdf.pages)
            if verbose:
                print(f'  Pages: {total_pages}')

            for page_num, page in enumerate(pdf.pages):
                table = page.extract_table()

                # Check if this is a header page (no data table)
                is_header = (table is None or len(table) < 3 or
                             not any(row and row[0] and
                                     str(row[0]).strip().isdigit()
                                     for row in table))

                if is_header:
                    # Save previous part if exists
                    if current_voters and current_part:
                        results.append(_make_part_result(
                            current_part, current_village, current_voters))
                        current_voters = []
                        current_page   = 0

                    # Extract part info from header
                    page_text = page.extract_text() or ''
                    pnum, village = extract_header_info(page_text)
                    if pnum:
                        current_part    = pnum
                        current_village = village
                    elif file_part and not current_part:
                        current_part = file_part
                    continue

                # Data page
                current_page += 1

                for row in (table or []):
                    if not row or not row[0]:
                        continue
                    serial_str = str(row[0]).strip()
                    if not serial_str.isdigit():
                        continue
                    try:
                        cols    = list(row) + [''] * 10
                        serial  = int(serial_str)
                        house   = str(cols[1] or '').strip().replace('\n', ' ')
                        name    = str(cols[2] or '').strip().replace('\n', ' ')
                        rel     = str(cols[3] or '').strip()
                        rel_name= str(cols[4] or '').strip().replace('\n', ' ')
                        gender_c= str(cols[5] or '').strip()
                        age     = str(cols[6] or '').strip()
                        epic    = str(cols[7] or '').strip()

                        current_voters.append({
                            'serial':   serial,
                            'page':     current_page,
                            'part':     current_part or 0,
                            'house':    house,
                            'name':     name,
                            'rel':      rel,
                            'rel_name': rel_name,
                            'gender_c': gender_c,
                            'age':      age,
                            'epic':     epic,
                        })
                    except Exception:
                        pass

        # Save last part
        if current_voters and current_part:
            results.append(_make_part_result(
                current_part, current_village, current_voters))

    except Exception as e:
        print(f'  ERROR: {e}')

    return results

def _make_part_result(part_num, village, voters):
    male   = 0
    female = 0
    processed = []

    for v in voters:
        gender  = get_gender(part_num, v['gender_c'])
        d_name  = decode_cid(v['name'])
        d_rel   = decode_cid(v['rel'])
        d_relname = decode_cid(v['rel_name'])
        house   = v['house']

        if gender == 'పు':
            male += 1
        else:
            female += 1

        processed.append({
            'part':      part_num,
            'serial':    v['serial'],
            'page':      v['page'],
            'house':     house,
            'house_norm':norm_house(house),
            'name':      d_name,
            'name_key':  to_key(d_name),
            'rel':       d_rel,
            'rel_name':  d_relname,
            'rel_key':   to_key(d_relname),
            'gender':    gender,
            'age':       v['age'],
            'epic':      v['epic'],
        })

    part_info = {
        'part':    part_num,
        'village': village or f'Part {part_num}',
        'male':    male,
        'female':  female,
        'total':   male + female,
    }
    return part_info, processed

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
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            part       INTEGER NOT NULL,
            serial     INTEGER NOT NULL,
            page       INTEGER NOT NULL,
            house      TEXT NOT NULL DEFAULT "",
            house_norm TEXT NOT NULL DEFAULT "",
            name       TEXT NOT NULL DEFAULT "",
            name_key   TEXT NOT NULL DEFAULT "",
            rel        TEXT NOT NULL DEFAULT "",
            rel_name   TEXT NOT NULL DEFAULT "",
            rel_key    TEXT NOT NULL DEFAULT "",
            gender     TEXT NOT NULL DEFAULT "",
            age        TEXT NOT NULL DEFAULT "",
            epic       TEXT NOT NULL DEFAULT ""
        );
        CREATE INDEX IF NOT EXISTS idx_house    ON voters(house_norm);
        CREATE INDEX IF NOT EXISTS idx_part_ser ON voters(part, serial);
        CREATE INDEX IF NOT EXISTS idx_name_key ON voters(name_key);
        CREATE INDEX IF NOT EXISTS idx_name     ON voters(name);
        CREATE INDEX IF NOT EXISTS idx_rel_key  ON voters(rel_key);
        CREATE INDEX IF NOT EXISTS idx_rel_name ON voters(rel_name);
        CREATE INDEX IF NOT EXISTS idx_epic     ON voters(epic);
        CREATE INDEX IF NOT EXISTS idx_gender   ON voters(gender);
        CREATE TABLE IF NOT EXISTS config (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
    ''')
    conn.commit()
    return conn

# ── Test ──────────────────────────────────────────────────────────────────────
def test_db(db_path):
    conn = sqlite3.connect(db_path)
    print('\n' + '='*60)
    print('DATABASE VERIFICATION')
    print('='*60)

    total   = conn.execute('SELECT COUNT(*) FROM voters').fetchone()[0]
    male    = conn.execute("SELECT COUNT(*) FROM voters WHERE gender='పు'").fetchone()[0]
    female  = conn.execute("SELECT COUNT(*) FROM voters WHERE gender='స్త్రీ'").fetchone()[0]
    parts   = conn.execute('SELECT COUNT(*) FROM parts').fetchone()[0]
    villages= conn.execute('SELECT COUNT(DISTINCT village) FROM parts').fetchone()[0]
    epic    = conn.execute(
        "SELECT COUNT(*) FROM voters WHERE epic!='' "
        "AND epic!='00000000000000' AND epic NOT LIKE '%000000'"
    ).fetchone()[0]

    print(f'Total voters : {total:,}')
    print(f'Male         : {male:,}')
    print(f'Female       : {female:,}')
    print(f'Parts        : {parts}')
    print(f'Villages     : {villages}')
    print(f'Valid EPICs  : {epic:,}')

    print('\n--- Sample names ---')
    for name, key in conn.execute(
            "SELECT name, name_key FROM voters WHERE name!='' LIMIT 8").fetchall():
        print(f'  {name!r:30} -> {key!r}')

    print('\n--- House search test: 7-2 ---')
    rows = conn.execute(
        "SELECT serial, part, house, name FROM voters "
        "WHERE house_norm LIKE '%-7-2-%' LIMIT 5"
    ).fetchall()
    print(f'  Results: {len(rows)}')
    for r in rows:
        print(f'  serial={r[0]} part={r[1]} house={r[2]!r} name={r[3]!r}')

    print('='*60)
    conn.close()

# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    args         = sys.argv[1:]
    cid_map_file = None

    if '--cid-map' in args:
        idx          = args.index('--cid-map')
        cid_map_file = args[idx+1]
        args         = args[:idx] + args[idx+2:]

    if len(args) < 2:
        print('Usage: python build_db.py <pdf_or_folder> <output.db> [--cid-map map.json]')
        sys.exit(1)

    input_path = args[0]
    db_path    = args[1]

    # Load CID map
    if cid_map_file and os.path.exists(cid_map_file):
        with open(cid_map_file, encoding='utf-8') as f:
            CID_MAP.update(json.load(f))
        print(f'CID map loaded: {len(CID_MAP)} entries')
    else:
        print(f'Using seed CID map: {len(CID_MAP)} entries')

    # Find PDFs
    if os.path.isfile(input_path) and input_path.lower().endswith('.pdf'):
        pdfs = [input_path]
    else:
        pdfs = sorted(glob.glob(os.path.join(input_path, '*.pdf')))
        if not pdfs:
            pdfs = sorted(glob.glob(os.path.join(input_path, '**/*.pdf'), recursive=True))

    if not pdfs:
        print(f'No PDFs found at: {input_path}')
        sys.exit(1)

    print(f'Found {len(pdfs)} PDF(s) -> {db_path}')

    if os.path.exists(db_path):
        os.remove(db_path)

    conn  = create_db(db_path)
    total = 0
    start = time.time()
    parts_seen = {}

    for i, pdf_path in enumerate(pdfs, 1):
        fname = os.path.basename(pdf_path)
        print(f'\n[{i}/{len(pdfs)}] {fname}')

        part_results = process_pdf(pdf_path, verbose=True)

        for part_info, voters in part_results:
            pnum = part_info['part']
            if pnum in parts_seen:
                print(f'  WARNING: Part {pnum} already seen! Skipping duplicate.')
                continue
            parts_seen[pnum] = True

            conn.execute('''
                INSERT OR REPLACE INTO parts (part, village, male, female, total)
                VALUES (:part, :village, :male, :female, :total)
            ''', part_info)

            for v in voters:
                conn.execute('''
                    INSERT INTO voters
                    (part, serial, page, house, house_norm,
                     name, name_key, rel, rel_name, rel_key,
                     gender, age, epic)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                ''', (v['part'], v['serial'], v['page'],
                      v['house'], v['house_norm'],
                      v['name'], v['name_key'],
                      v['rel'], v['rel_name'], v['rel_key'],
                      v['gender'], v['age'], v['epic']))

            conn.commit()
            total += len(voters)
            print(f'  Part {pnum}: {len(voters)} voters | '
                  f'M:{part_info["male"]} F:{part_info["female"]} | '
                  f'Village: {part_info["village"]!r}')

    # Save constituency config to DB
    # Extract AC number from PDF filename e.g. S01_181_1.pdf -> 181
    ac_num = '???'
    if pdfs:
        m = re.search(r'S\d+_(\d+)_', os.path.basename(pdfs[0]))
        if m:
            ac_num = m.group(1)

    # Get constituency name from DB parts
    conn2 = sqlite3.connect(db_path)
    # Most common village = constituency headquarters
    const_name = conn2.execute(
        'SELECT village, COUNT(*) as c FROM parts GROUP BY village ORDER BY c DESC LIMIT 1'
    ).fetchone()
    const_name = const_name[0] if const_name else 'Unknown'

    conn2.executemany('INSERT OR REPLACE INTO config (key, value) VALUES (?,?)', [
        ('ac_number',   ac_num),
        ('const_name',  const_name),
        ('year',        '2002'),
        ('total_parts', str(len(parts_seen))),
    ])
    conn2.commit()
    conn2.close()

    print(f'Constituency : {const_name} AC-{ac_num}')

    elapsed = time.time() - start
    print(f'\n{"="*60}')
    print(f'Done in      : {elapsed:.1f}s')
    print(f'Total voters : {total:,}')
    print(f'Parts        : {len(parts_seen)}')
    print(f'DB size      : {os.path.getsize(db_path)/1024/1024:.1f} MB')
    print(f'Database     : {db_path}')
    conn.close()

    test_db(db_path)

if __name__ == '__main__':
    main()
