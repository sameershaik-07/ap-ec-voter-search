"""
build_cid_from_reference.py
===========================
Builds a CONTEXT-AWARE CID->Telugu map by aligning:
  - Raw PDF text (CID encoded) from our PDFs  
  - Perfect Telugu names from reference DB (his APK)

The more PDFs you provide, the better the accuracy.
This map works for ALL 2002 AP ECI PDFs (same Gautami font).

Usage:
    python build_cid_from_reference.py <pdf_folder> <reference.db> <output_folder>

Example:
    python pipeline/build_cid_from_reference.py pdfs reference.db output
"""

import sys, os, re, json, glob, sqlite3
import pdfplumber
from collections import Counter, defaultdict


def tokenize(text):
    tokens = []
    i = 0
    while i < len(text):
        m = re.match(r'\(cid:(\d+)\)', text[i:])
        if m:
            tokens.append(('CID', m.group(1)))
            i += len(m.group(0))
        elif text[i] == ' ':
            tokens.append(('SP', ' '))
            i += 1
        else:
            tokens.append(('CH', text[i]))
            i += 1
    return tokens


def build_context_votes(pdf_text, clean_text, simple_votes, context_votes):
    """Build both simple and context-aware votes"""
    if not pdf_text or not clean_text:
        return
    tokens = tokenize(pdf_text)
    clean  = clean_text
    ci     = 0
    prev_ch = ''

    for idx, (tok_type, tok_val) in enumerate(tokens):
        if ci >= len(clean):
            break
        if tok_type in ('CH', 'SP'):
            if ci < len(clean) and tok_val == clean[ci]:
                prev_ch = tok_val
                ci += 1
        elif tok_type == 'CID':
            # Find next known char
            next_ch = ''
            for ft, fv in tokens[idx+1:]:
                if ft in ('CH', 'SP'):
                    next_ch = fv
                    break

            if next_ch:
                pos = clean.find(next_ch, ci)
                if pos >= ci and (pos - ci) <= 5:
                    chunk = clean[ci:pos]
                    if chunk and any('\u0C00' <= c <= '\u0C7F' for c in chunk):
                        simple_votes[tok_val][chunk] += 1
                        ctx_key = f"{prev_ch}|{next_ch}"
                        context_votes[(tok_val, ctx_key)][chunk] += 1
                    ci = pos
                    prev_ch = next_ch
            else:
                chunk = clean[ci:]
                if chunk and len(chunk) <= 5 and any('\u0C00' <= c <= '\u0C7F' for c in chunk):
                    simple_votes[tok_val][chunk] += 1
                    ctx_key = f"{prev_ch}|"
                    context_votes[(tok_val, ctx_key)][chunk] += 1
                ci = len(clean)


def apply_context_map(text, cmap):
    """Apply context-aware CID mapping"""
    tokens  = tokenize(text)
    result  = ''
    prev_ch = ''
    for idx, (tok_type, tok_val) in enumerate(tokens):
        if tok_type in ('CH', 'SP'):
            result  += tok_val
            prev_ch  = tok_val
        elif tok_type == 'CID':
            if tok_val not in cmap:
                continue
            next_ch = ''
            for ft, fv in tokens[idx+1:]:
                if ft in ('CH', 'SP'):
                    next_ch = fv
                    break
            data     = cmap[tok_val]
            default  = data['default']
            contexts = data.get('contexts', {})
            ctx_key  = f"{prev_ch}|{next_ch}"
            chosen   = contexts.get(ctx_key, default)
            result  += chosen
            prev_ch  = chosen[-1] if chosen else prev_ch
    result = result.replace('\uffff', '').replace('\ufffe', '')
    result = result.replace('\u0C46\u0C56', '\u0C48')
    return re.sub(r'\s+', ' ', result).strip()


def extract_part_number(filename):
    m = re.search(r'_(\d+)\.pdf$', filename, re.IGNORECASE)
    return int(m.group(1)) if m else 0


def load_reference(ref_db_path):
    conn = sqlite3.connect(ref_db_path)
    ref  = {}
    for part, serial, name, rel_name in conn.execute(
        "SELECT part, serial, name, rel_name FROM voters"
    ).fetchall():
        ref[(part, serial)] = (name, rel_name)
    conn.close()
    print(f"Reference records loaded: {len(ref)}")
    return ref


def process_pdf(pdf_path, ref, simple_votes, context_votes):
    part  = extract_part_number(os.path.basename(pdf_path))
    count = 0
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages[1:]:
                table = page.extract_table()
                if not table:
                    continue
                for row in table:
                    if not row or not row[0] or not str(row[0]).strip().isdigit():
                        continue
                    serial = int(str(row[0]).strip())
                    key    = (part, serial)
                    if key not in ref:
                        continue
                    pdf_name    = str(row[2] or '').strip().replace('\n', ' ')
                    pdf_relname = str(row[4] or '').strip().replace('\n', ' ')
                    his_name, his_rel = ref[key]
                    build_context_votes(pdf_name,    his_name, simple_votes, context_votes)
                    build_context_votes(pdf_relname, his_rel,  simple_votes, context_votes)
                    count += 1
    except Exception as e:
        print(f"  Error: {e}")
    return count


def build_final_map(simple_votes, context_votes, min_votes=2):
    """Build context-aware map"""
    cid_map = {}

    # Build default from most common simple vote
    for cid, votes in simple_votes.items():
        best, count = votes.most_common(1)[0]
        if count >= min_votes and best and any('\u0C00' <= c <= '\u0C7F' for c in best):
            cid_map[cid] = {'default': best, 'contexts': {}}

    # Add context overrides
    for (cid, ctx_key), votes in context_votes.items():
        if cid not in cid_map:
            continue
        best, count = votes.most_common(1)[0]
        if count < min_votes:
            continue
        if not any('\u0C00' <= c <= '\u0C7F' for c in best):
            continue
        default = cid_map[cid]['default']
        if best != default:
            cid_map[cid]['contexts'][ctx_key] = best

    return cid_map


def main():
    if len(sys.argv) < 4:
        print("Usage: python build_cid_from_reference.py <pdf_folder> <reference.db> <output_folder>")
        sys.exit(1)

    pdf_folder = sys.argv[1]
    ref_db     = sys.argv[2]
    out_folder = sys.argv[3]
    map_path   = os.path.join(out_folder, 'context_cid_map.json')

    # Find PDFs
    pdfs = sorted(glob.glob(os.path.join(pdf_folder, '*.pdf')))
    if not pdfs:
        pdfs = sorted(glob.glob(os.path.join(pdf_folder, '**/*.pdf'), recursive=True))
    print(f"Found {len(pdfs)} PDFs")

    # Load reference
    ref = load_reference(ref_db)

    # Process all PDFs
    print("\nBuilding context-aware CID map from all PDFs...")
    simple_votes  = defaultdict(Counter)
    context_votes = defaultdict(Counter)
    total_aligned = 0

    for pdf_path in pdfs:
        fname = os.path.basename(pdf_path)
        count = process_pdf(pdf_path, ref, simple_votes, context_votes)
        total_aligned += count
        print(f"  {fname}: {count} aligned records")

    print(f"\nTotal aligned: {total_aligned}")
    print(f"Unique CIDs found: {len(simple_votes)}")

    # Build map
    cid_map = build_final_map(simple_votes, context_votes, min_votes=2)
    print(f"Context CID map entries: {len(cid_map)}")

    # Count entries with context overrides
    with_ctx = sum(1 for v in cid_map.values() if v.get('contexts'))
    print(f"CIDs with context overrides: {with_ctx}")

    # Save
    with open(map_path, 'w', encoding='utf-8') as f:
        json.dump(cid_map, f, ensure_ascii=False, indent=2)
    print(f"\nSaved: {map_path}")

    # Test on first PDF
    if pdfs:
        part     = extract_part_number(os.path.basename(pdfs[0]))
        exact    = 0
        total    = 0
        try:
            with pdfplumber.open(pdfs[0]) as pdf:
                for page in pdf.pages[1:]:
                    table = page.extract_table()
                    if not table: continue
                    for row in table:
                        if not row or not row[0] or not str(row[0]).strip().isdigit(): continue
                        serial = int(str(row[0]).strip())
                        key    = (part, serial)
                        if key not in ref: continue
                        raw  = str(row[2] or '').strip()
                        got  = apply_context_map(raw, cid_map)
                        want = ref[key][0]
                        if got == want: exact += 1
                        total += 1
        except Exception:
            pass
        if total > 0:
            print(f"Accuracy on {os.path.basename(pdfs[0])}: {exact}/{total} = {100*exact/total:.1f}%")

    print(f"\nUse this map for ALL 2002 AP ECI constituencies:")
    print(f"  python pipeline/build_db.py <pdf_folder> <output.db> --cid-map {map_path}")


if __name__ == '__main__':
    main()