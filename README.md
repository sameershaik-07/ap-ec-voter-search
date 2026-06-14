# 🗳️ AP Electoral Roll Voter Search App

Search the 2002 Special Intensive Revision (SIR) voter list of Andhra Pradesh — offline, on your Android phone.

Built for **Dhone AC-181** with support for expanding to all AP constituencies.

---

## 📱 App Features

- 🔍 **Search by Name** — Telugu or English phonetic (e.g. రెడ్డి or "reddy")
- 🏠 **Search by House Number** — partial search supported (e.g. 7-2 finds 7-2, 7-2/3, 7-2-1)
- 🪪 **Search by EPIC Card Number**
- 🔽 **Filter by Part** (polling booth)
- 📤 **Share voter details** via WhatsApp
- 📊 **Dashboard** — total voters, male/female, valid EPICs
- ✅ **100% Offline** — no internet needed after install

---

## 🗂️ Project Structure

```
ap-ec-voter-search/
│
├── pipeline/                          ← Python scripts
│   ├── build_db.py                    ← Main: PDF → SQLite DB
│   ├── build_cid_from_reference.py    ← Build CID map from reference APK + PDFs
│   ├── build_cid_map.py               ← Iterative CID map builder
│   ├── generate_lookup.py             ← Generate name lookup from reference DB
│   └── merge_names.py                 ← Merge Telugu names from reference DB
│
├── flutter_app/                       ← Android app
│   ├── lib/main.dart                  ← Complete app code
│   ├── pubspec.yaml                   ← Dependencies
│   └── assets/voters.db              ← Database (you generate this)
│
├── pdfs/                              ← Put ECI PDF files here
├── output/                            ← Generated files go here
└── README.md
```

---

## ⚙️ Prerequisites

All required on your **Windows VM**:

| Tool | Version | Status |
|---|---|---|
| Python | 3.11+ | Required |
| Flutter | Latest stable | Required |
| Android SDK | API 24+ | Required |
| Java | OpenJDK 17 | Required |
| Git | Any | Required |

Install Python libraries:
```powershell
pip install pdfplumber indic-transliteration
```

---

## 🚀 Quick Start — Dhone AC-181

### Step 1 — Download PDFs from ECI

Go to [voters.eci.gov.in](https://voters.eci.gov.in) → Search in last SIR E-Roll → Select **Andhra Pradesh → Dhone AC-181** → Download all part PDFs.

Save them to `C:\voter_project\pdfs\`

### Step 2 — Extract reference DB from My_Dhone.apk

```powershell
cd C:\voter_project
copy "My Dhone.apk" reference.zip
Expand-Archive -Path reference.zip -DestinationPath ref_extract -Force
copy "ref_extract\assets\flutter_assets\assets\voters.db" reference.db
```

### Step 3 — Generate name lookup

```powershell
python pipeline\generate_lookup.py reference.db output\voter_names_lookup.json
```

### Step 4 — Build database

```powershell
python pipeline\build_db.py pdfs output\dhone.db --lookup output\voter_names_lookup.json
```

Expected output:
```
[1/22] S01_181_54.pdf ... 1059 voters  (M:1059  F:0)
[2/22] S01_181_55.pdf ... 1084 voters  (M:0  F:1084)
...
Total voters : 24812 | Male: 11867 | Female: 12945
```

### Step 5 — Build APK

```powershell
copy output\dhone.db flutter_app\assets\voters.db
cd flutter_app
flutter pub get
flutter build apk --release
copy build\app\outputs\flutter-apk\app-release.apk ..\output\MyDhone_final.apk
```

### Step 6 — Install on phone

Transfer `MyDhone_final.apk` to phone via USB/WhatsApp and install.

> ⚠️ Enable **Settings → Security → Install from Unknown Sources** before installing.

---

## 🔄 Adding Another Constituency

### If you have a reference APK for that constituency

```powershell
# 1. Extract reference DB from that APK
copy "My_OtherConstituency.apk" other_ref.zip
Expand-Archive -Path other_ref.zip -DestinationPath other_ref_extract -Force
copy "other_ref_extract\assets\flutter_assets\assets\voters.db" other_reference.db

# 2. Generate lookup
python pipeline\generate_lookup.py other_reference.db output\other_lookup.json

# 3. Build DB with 100% Telugu names
python pipeline\build_db.py pdfs_other output\other.db --lookup output\other_lookup.json
```

### If you don't have a reference APK

```powershell
# Build CID map from your PDFs (one-time, works for ALL constituencies)
python pipeline\build_cid_from_reference.py pdfs reference.db output

# Build DB using CID map (~60% name accuracy)
python pipeline\build_db.py pdfs_other output\other.db --cid-map output\context_cid_map.json
```

### Update app name for new constituency

Open `flutter_app\lib\main.dart` and change these 4 lines:

```dart
const kAppName   = 'My Dhone';     // ← Change to 'My Kurnool'
const kConstName = 'Dhone';        // ← Change to 'Kurnool'
const kAcNumber  = '181';          // ← Change to correct AC number
const kYear      = '2002';
```

Then rebuild the APK.

---

## 🧠 How It Works

### The Font Encoding Problem

2002 ECI PDFs use **Gautami font with Identity-H encoding**. Telugu characters are stored as CID (Character ID) numbers — not Unicode. Direct text extraction gives garbage like `(cid:307)(cid:312)(cid:153)`.

### Our Solution — 3-Tier Approach

```
PDF (CID encoded)
       ↓
Tier 1: Reference DB Lookup (part+serial → Telugu name)  → 100% accuracy ✅
       ↓ (if not found)
Tier 2: CID Map Decoding (font glyph → Telugu char)      → ~60% accuracy ⚠️
       ↓ (if still garbled)
Tier 3: Partial Telugu (strip CIDs, keep known chars)    → readable ⚠️
```

### CID Map

Built from:
1. **Gautami font file** (extracted from PDF) — gives base char mappings
2. **Reference APK names** — 171,256 clean Telugu names used to validate
3. **Covers all Telugu Unicode chars** — consonants, vowels, matras, conjuncts

### House Number Search

Stores house as `-7-2-` (with boundary markers) so searching `7-2` finds:
- `7-2` ✅
- `7-2/3` ✅  
- `20-63-7-2` ✅
- But NOT `6-57-2` ❌ (false positive prevention)

---

## 📊 Database Schema

```sql
CREATE TABLE voters (
    id          INTEGER PRIMARY KEY,
    part        INTEGER,    -- Polling booth part number
    serial      INTEGER,    -- Serial number in part
    page        INTEGER,    -- Page in PDF
    house       TEXT,       -- Original house number
    house_norm  TEXT,       -- Normalized: -7-2- format
    name        TEXT,       -- Telugu name
    name_key    TEXT,       -- Phonetic key for search (e.g. "vade narasinhulu")
    rel         TEXT,       -- Relation type (తం/భ/భా/తల్లి)
    rel_name    TEXT,       -- Relation's name in Telugu
    rel_key     TEXT,       -- Relation's phonetic key
    gender      TEXT,       -- పు (male) / స్త్రీ (female)
    age         TEXT,       -- Age as of 2002
    epic        TEXT        -- EPIC card number
);

CREATE TABLE parts (
    part    INTEGER PRIMARY KEY,
    village TEXT,
    male    INTEGER,
    female  INTEGER,
    total   INTEGER
);
```

---

## 🐛 Troubleshooting

| Error | Fix |
|---|---|
| `No PDFs found` | Make sure PDFs are in `pdfs\` folder |
| `flutter not recognized` | Restart PowerShell after Flutter install |
| `License not accepted` | Run `flutter doctor --android-licenses` and press `y` |
| APK not installing | Enable "Install from Unknown Sources" in phone settings |
| Names showing in English | Run `generate_lookup.py` and rebuild with `--lookup` flag |
| EPIC showing "Not issued" | This is correct — some voters had no EPIC in 2002 |

---

## 📋 Constituency Coverage

| Constituency | AC No | Status | Name Accuracy |
|---|---|---|---|
| Dhone | 181 | ✅ Complete | 100% (reference DB) |
| Others | TBD | 🔄 Pending | ~60% (CID map) |

---

## 🔑 Key Files

| File | Purpose |
|---|---|
| `pipeline/build_db.py` | Main pipeline: PDF → SQLite |
| `pipeline/build_cid_from_reference.py` | Build CID map using reference APK |
| `pipeline/generate_lookup.py` | Export reference names as lookup JSON |
| `pipeline/merge_names.py` | Merge reference names into existing DB |
| `flutter_app/lib/main.dart` | Complete Flutter app |
| `output/cid_map.json` | CID → Telugu character mapping |

---

## ⚠️ Important Notes

- This app is for **reference only** — not for official use
- Always verify with original ECI PDF using Part, Page and Serial numbers
- Official voter information: **[voters.eci.gov.in](https://voters.eci.gov.in)**
- `AP261810000000` in EPIC column = voter had no EPIC card issued in 2002 (ECI data)

---

## 👥 Credits

- ECI for publishing 2002 SIR electoral rolls publicly
- Built with: Python, Flutter, SQLite, pdfplumber
- Font analysis: FontTools (Gautami CID mapping)

---

*Last updated: June 2026 | AP Electoral Roll SIR 2002 | Dhone AC-181*
