import sys, os, re, sqlite3, time, glob
import pdfplumber

try:
    from indic_transliteration import sanscript
    from indic_transliteration.sanscript import transliterate
    def to_key(text):
        if not text: return ''
        try:
            result = transliterate(text, sanscript.TELUGU, sanscript.IAST)
            result = result.lower()
            result = re.sub(r'[^\x00-\x7F]', '', result)
            result = re.sub(r'[^a-z0-9 .]', '', result)
            return result.strip()
        except:
            return text.lower().strip()
except ImportError:
    def to_key(text):
        return text.strip().lower()

def norm_house(house):
    return house.strip().lstrip('-').strip()

def extract_part_number(filename):
    m = re.search(r'_(\d+)\.pdf$', filename, re.IGNORECASE)
    return int(m.group(1)) if m else 0

def extract_page(pdf_page):
    rows = []
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
                'house':    str(row[1] or '').strip().replace('\n',' '),
                'name':     str(row[2] or '').strip().replace('\n',' '),
                'rel':      str(row[3] or '').strip(),
                'rel_name': str(row[4] or '').strip().replace('\n',' '),
                'gender':   str(row[5] or '').strip().replace('\n',''),
                'age':      str(row[6] or '').strip(),
                'epic':     str(row[7] or '').strip(),
            })
        except:
            pass
    return rows

def process_pdf(pdf_path):
    filename = os.path.basename(pdf_path)
    part_num = extract_part_number(filename)
    voters = []
    village = ''
    male = 0
    female = 0
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page_num, page in enumerate(pdf.pages):
                if page_num == 0:
                    text = page.extract_text() or ''
                    for line in text.split('\n'):
                        line = line.strip()
                        if len(line) > 3:
                            village = line
                            break
                    continue
                rows = extract_page(page)
                for r in rows:
                    r['page'] = page_num + 1
                    r['part'] = part_num
                    voters.append(r)
    except Exception as e:
        print('  Error: ' + str(e))
    for v in voters:
        g = v.get('gender','')
        if 'స్త్రీ' in g:
            female += 1
        else:
            male += 1
    part_info = {
        'part':    part_num,
        'village': village or ('Part ' + str(part_num)),
        'male':    male,
        'female':  female,
        'total':   male + female,
    }
    return part_num, voters, part_info

def create_db(db_path):
    conn = sqlite3.connect(db_path)
    conn.executescript('''
        CREATE TABLE IF NOT EXISTS parts (
            part    INTEGER PRIMARY KEY,
            village TEXT NOT NULL,
            male    INTEGER,
            female  INTEGER,
            total   INTEGER
        );
        CREATE TABLE IF NOT EXISTS voters (
            id          INTEGER PRIMARY KEY,
            part        INTEGER NOT NULL,
            serial      INTEGER NOT NULL,
            page        INTEGER NOT NULL,
            house       TEXT NOT NULL,
            house_norm  TEXT NOT NULL,
            name        TEXT NOT NULL,
            name_key    TEXT NOT NULL,
            rel         TEXT NOT NULL,
            rel_name    TEXT NOT NULL,
            rel_key     TEXT NOT NULL,
            gender      TEXT NOT NULL,
            age         TEXT NOT NULL,
            epic        TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_house ON voters(house_norm);
        CREATE INDEX IF NOT EXISTS idx_part_serial ON voters(part, serial);
        CREATE INDEX IF NOT EXISTS idx_name_key ON voters(name_key);
        CREATE INDEX IF NOT EXISTS idx_epic ON voters(epic);
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
        name_key   = to_key(v['name'])
        rel_key    = to_key(v['rel_name'])
        gender     = 'స్త్రీ' if 'స్త్రీ' in v.get('gender','') else 'పు'
        conn.execute('''
            INSERT INTO voters
            (part, serial, page, house, house_norm, name, name_key,
             rel, rel_name, rel_key, gender, age, epic)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        ''', (
            v['part'], v['serial'], v['page'],
            v['house'], house_norm,
            v['name'], name_key,
            v['rel'], v['rel_name'], rel_key,
            gender, v['age'], v['epic'],
        ))

def main():
    input_path = sys.argv[1] if len(sys.argv) > 1 else 'pdfs'
    db_path    = sys.argv[2] if len(sys.argv) > 2 else 'voters.db'
    pdfs = sorted(glob.glob(os.path.join(input_path,'**/*.pdf'), recursive=True))
    if not pdfs:
        pdfs = sorted(glob.glob(os.path.join(input_path,'*.pdf')))
    if not pdfs:
        print('No PDFs found in ' + input_path)
        sys.exit(1)
    print('Found ' + str(len(pdfs)) + ' PDFs -> ' + db_path)
    conn = create_db(db_path)
    total = 0
    start = time.time()
    for i, pdf_path in enumerate(pdfs, 1):
        fname = os.path.basename(pdf_path)
        print('[' + str(i) + '/' + str(len(pdfs)) + '] ' + fname + ' ... ', end='', flush=True)
        part_num, voters, part_info = process_pdf(pdf_path)
        insert_part(conn, part_info)
        insert_voters(conn, voters)
        conn.commit()
        total += len(voters)
        village = part_info['village']
        print(str(len(voters)) + ' voters | ' + village)
    elapsed = time.time() - start
    print('Done in ' + str(round(elapsed,1)) + 's | Total: ' + str(total) + ' voters | DB: ' + db_path)
    conn.close()

if __name__ == '__main__':
    main()
