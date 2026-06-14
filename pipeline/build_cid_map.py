"""
build_cid_map.py
================
Generates cid_map.json using the FIXED CID->Telugu mapping
defined by the voter roll PDF font encoding.

CID table (hardcoded, verified):
  1-13  : Telugu vowels (అ ఆ ఇ ఈ ఉ ఊ ఋ ఎ ఏ ఐ ఒ ఓ ఔ)
  14-50 : Telugu consonants (క ఖ గ ... హ క్ష జ్ఞ)
  51-65 : Telugu signs/matras (ా ి ీ ు ూ ృ ె ే ై ొ ో ౌ ్ ం ః)
  66-75 : Telugu digits (౦ ౧ ౨ ౩ ౪ ౫ ౬ ౭ ౮ ౯)

Run:
    python pipeline/build_cid_map.py <pdf_folder> <output_db>

Output:
    <output_dir>/cid_map.json

Then rebuild DB:
    python pipeline/build_db.py <pdf_folder> <output_db> --cid-map output/cid_map.json
"""

import sys, os, re, json, glob
import pdfplumber

# ── Fixed CID -> Telugu mapping ───────────────────────────────────────────────

CID_MAP = {
    # Vowels
    1:  'అ',   2:  'ఆ',   3:  'ఇ',   4:  'ఈ',   5:  'ఉ',
    6:  'ఊ',   7:  'ఋ',   8:  'ఎ',   9:  'ఏ',   10: 'ఐ',
    11: 'ఒ',   12: 'ఓ',   13: 'ఔ',
    # Consonants
    14: 'క',   15: 'ఖ',   16: 'గ',   17: 'ఘ',   18: 'ఙ',
    19: 'చ',   20: 'ఛ',   21: 'జ',   22: 'ఝ',   23: 'ఞ',
    24: 'ట',   25: 'ఠ',   26: 'డ',   27: 'ఢ',   28: 'ణ',
    29: 'త',   30: 'థ',   31: 'ద',   32: 'ధ',   33: 'న',
    34: 'ప',   35: 'ఫ',   36: 'బ',   37: 'భ',   38: 'మ',
    39: 'య',   40: 'ర',   41: 'ఱ',   42: 'ల',   43: 'ళ',
    44: 'వ',   45: 'శ',   46: 'ష',   47: 'స',   48: 'హ',
    49: 'క్ష', 50: 'జ్ఞ',
    # Signs / Matras
    51: 'ా',   52: 'ి',   53: 'ీ',   54: 'ు',   55: 'ూ',
    56: 'ృ',   57: 'ె',   58: 'ే',   59: 'ై',   60: 'ొ',
    61: 'ో',   62: 'ౌ',   63: '్',   64: 'ం',   65: 'ః',
    # Digits
    66: '౦',   67: '౧',   68: '౨',   69: '౩',   70: '౪',
    71: '౫',   72: '౬',   73: '౭',   74: '౮',   75: '౯',
}

# String-keyed version for JSON and replace operations
CID_MAP_STR = {str(k): v for k, v in CID_MAP.items()}


# ── Text decode ───────────────────────────────────────────────────────────────

def decode_telugu(text):
    """
    Replace all (cid:N) tokens in text with Telugu characters.
    Unknown CIDs are left as-is so you can spot gaps.
    """
    def replace(m):
        n = int(m.group(1))
        return CID_MAP.get(n, m.group(0))   # keep original if not in table
    return re.sub(r'\(cid:(\d+)\)', replace, text)


def decode_clean(text):
    """Decode and strip residual whitespace."""
    return re.sub(r'\s+', ' ', decode_telugu(text)).strip()


# ── Verification: extract sample rows from PDFs ───────────────────────────────

def verify_on_pdfs(pdfs, max_rows=10):
    """Print sample decoded names to visually verify the mapping."""
    print("\n── Sample decoded names ─────────────────────────────────────────")
    shown = 0
    for pdf_path in pdfs:
        if shown >= max_rows:
            break
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages[1:]:
                    table = page.extract_table()
                    if not table:
                        continue
                    for row in table:
                        if not row or not row[0] or not str(row[0]).strip().isdigit():
                            continue
                        serial   = str(row[0]).strip()
                        raw_name = str(row[2] or '').strip().replace('\n', ' ')
                        raw_rel  = str(row[4] or '').strip().replace('\n', ' ')
                        dec_name = decode_clean(raw_name)
                        dec_rel  = decode_clean(raw_rel)

                        # Count residual CIDs (not in table)
                        missing = re.findall(r'\(cid:(\d+)\)', dec_name)

                        print(f"  Serial {serial:>4} | {dec_name}")
                        print(f"           rel | {dec_rel}")
                        if missing:
                            print(f"           *** missing CIDs: {missing}")
                        print()
                        shown += 1
                        if shown >= max_rows:
                            break
                    if shown >= max_rows:
                        break
        except Exception as e:
            print(f"  Error: {pdf_path}: {e}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print("Usage: python build_cid_map.py <pdf_folder> <output_db>")
        sys.exit(1)

    pdf_folder = sys.argv[1]
    db_path    = sys.argv[2]
    map_path   = os.path.join(os.path.dirname(db_path), 'cid_map.json')

    # Save JSON map (string keys for JSON compatibility)
    with open(map_path, 'w', encoding='utf-8') as f:
        json.dump(CID_MAP_STR, f, ensure_ascii=False, indent=2, sort_keys=False)

    print(f"Saved CID map: {map_path}  ({len(CID_MAP_STR)} entries)")
    print()
    print("Map contents:")
    print(f"  {'CID':<6} {'Telugu':<10} {'Unicode'}")
    print(f"  {'---':<6} {'------':<10} {'-------'}")
    for cid, ch in CID_MAP.items():
        uni = ' '.join(f'U+{ord(c):04X}' for c in ch)
        print(f"  {cid:<6} {ch:<10} {uni}")

    # Find PDFs and verify
    pdfs = sorted(glob.glob(os.path.join(pdf_folder, '*.pdf')))
    if not pdfs:
        pdfs = sorted(glob.glob(os.path.join(pdf_folder, '**/*.pdf'), recursive=True))
    print(f"\nFound {len(pdfs)} PDFs  →  verifying decode on samples...")
    verify_on_pdfs(pdfs)

    print(f"\nNext step:")
    print(f"  python pipeline/build_db.py {pdf_folder} {db_path} --cid-map {map_path}")


if __name__ == '__main__':
    main()