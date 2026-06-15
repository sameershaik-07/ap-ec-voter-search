# 🗳️ AP Voter Search App

> Search the 2002 Special Intensive Revision (SIR) Electoral Roll of Andhra Pradesh — offline, instantly, on your Android phone.

Built for field workers, political teams, and citizens who need fast voter data access without internet.

---

## 📱 What This App Does

- 🔍 **Search by Name** — Telugu or English phonetic (e.g. రెడ్డి or "reddy")
- 🏠 **Search by House Number** — partial search works (e.g. 7-2 finds all 7-2/x voters)
- 🪪 **Search by EPIC Card Number** — full or partial
- 🔽 **Filter by Village** — 88 villages in Dhone
- 🔽 **Filter by Part** — 186 polling stations
- 📋 **Tap any card** → full voter details in Telugu + English
- 📤 **Copy & Share** voter details via WhatsApp
- ✅ **100% Offline** — no internet needed after install

---

## 🏗️ Project Structure

```
ap-ec-voter-search/
│
├── pipeline/                        ← Python scripts (PDF → Database)
│   ├── build_db.py                  ← MAIN: converts PDFs to SQLite DB
│   ├── build_cid_from_reference.py  ← Builds Telugu CID font map
│   ├── generate_lookup.py           ← Generates name lookup from reference APK
│   └── merge_names.py               ← Merges Telugu names into DB
│
├── flutter_app/                     ← Android App
│   ├── lib/main.dart                ← Complete app code (single file)
│   ├── pubspec.yaml                 ← App dependencies
│   └── assets/voters.db            ← Database (you generate this — gitignored)
│
├── build_apk.ps1                    ← ONE script to build APK for any constituency
├── README.md                        ← This file
└── .gitignore
```

---

## 💻 Prerequisites

Install these on your **Windows machine** before starting:

### 1. Python 3.11
Download from https://www.python.org/downloads/

During install → ✅ Check **"Add Python to PATH"**

Verify:
```powershell
python --version
# Should show: Python 3.11.x
```

### 2. Python Libraries
```powershell
pip install pdfplumber indic-transliteration
```

### 3. Java 17 (JDK)
Download from https://adoptium.net/

Verify:
```powershell
java -version
# Should show: openjdk version "17.x.x"
```

### 4. Flutter SDK
```powershell
cd C:\
git clone https://github.com/flutter/flutter.git -b stable --depth 1

# Add to PATH permanently
$p = [System.Environment]::GetEnvironmentVariable("Path","Machine")
[System.Environment]::SetEnvironmentVariable("Path","$p;C:\flutter\bin","Machine")
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

# Verify
flutter --version
```

### 5. Android SDK
```powershell
mkdir C:\android-sdk\cmdline-tools
cd C:\android-sdk\cmdline-tools

# Download command line tools
Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile "cmdtools.zip"
Expand-Archive -Path "cmdtools.zip" -DestinationPath "."
Rename-Item "cmdline-tools" "latest"

# Add to PATH
$p = [System.Environment]::GetEnvironmentVariable("Path","Machine")
[System.Environment]::SetEnvironmentVariable("Path","$p;C:\android-sdk\cmdline-tools\latest\bin;C:\android-sdk\platform-tools","Machine")
[System.Environment]::SetEnvironmentVariable("ANDROID_HOME","C:\android-sdk","Machine")
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
$env:ANDROID_HOME = "C:\android-sdk"

# Install Android build tools
sdkmanager --sdk_root="C:\android-sdk" "platform-tools" "platforms;android-35" "build-tools;35.0.0"
# Type 'y' for every license prompt

# Tell Flutter where Android SDK is
flutter config --android-sdk "C:\android-sdk"
flutter doctor --android-licenses
# Type 'y' for every prompt

# Verify everything
flutter doctor
# Should show Flutter ✓ and Android toolchain ✓
```

---

## 🚀 Quick Start — Build for Dhone AC-181

### Step 1 — Clone this repo
```powershell
git clone https://github.com/kala-techies/ap-ec-voter-search.git
cd ap-ec-voter-search
```

### Step 2 — Download PDFs from ECI
1. Go to https://voters.eci.gov.in
2. Click **"Download Electoral Roll"**
3. Select: **Andhra Pradesh → Kurnool District → Dhone AC-181**
4. Download all part PDFs (186 files)
5. Create folder and copy PDFs:
```powershell
New-Item -ItemType Directory -Force -Path pdfs_dhone
# Copy all downloaded PDFs into pdfs_dhone folder
```

### Step 3 — Build Database
```powershell
python pipeline\build_db.py pdfs_dhone output\dhone.db
```

You will see:
```
Found 186 PDFs -> output\dhone.db
[1/186] S01_181_1.pdf
  Part 1: 977 voters | M:977 F:0 | Village: 'దేవనకొండ'
[2/186] S01_181_2.pdf
  Part 2: 957 voters | M:0 F:957 | Village: 'దేవనకొండ'
...
Total voters : 1,71,256
Parts        : 186
Villages     : 88
```

⏱️ Takes about 35 minutes for 186 PDFs.

### Step 4 — Build APK (One Command!)
```powershell
.\build_apk.ps1 -DbPath "output\dhone.db"
```

This automatically:
- Reads constituency name from DB
- Sets app name in Android manifest
- Copies DB to Flutter assets
- Builds release APK
- Saves as `Dhone_AC181_SIR2002.apk`

⏱️ Takes about 3-5 minutes.

### Step 5 — Install on Phone
Transfer `output\Dhone_AC181_SIR2002.apk` to phone and install.

> ⚠️ On phone: **Settings → Security → Enable "Install from Unknown Sources"**

---

## 🔄 Adding Another Constituency

This is the power of this project — **zero code changes** for any new constituency!

```powershell
# 1. Create folder for new constituency
New-Item -ItemType Directory -Force -Path pdfs_kurnool

# 2. Copy PDFs downloaded from ECI into that folder

# 3. Build DB — everything extracted automatically from PDFs
#    (village names, gender, part numbers, constituency name)
python pipeline\build_db.py pdfs_kurnool output\kurnool.db

# 4. Build APK — app name set automatically from DB
.\build_apk.ps1 -DbPath "output\kurnool.db"

# Done! APK saved as Kurnool_ACxxx_SIR2002.apk
```

**That's it. 2 commands. No code changes.**

---

## 🧠 How It Works

### The Font Problem
2002 ECI PDFs use **Gautami font with Identity-H encoding**. Telugu characters are stored as CID (Character ID) glyph numbers — not Unicode. Direct text extraction gives `(cid:307)(cid:208)(cid:312)` instead of proper Telugu.

### Our Solution
```
PDF (CID encoded)
      ↓
build_db.py
      ↓
┌─────────────────────────────────────────┐
│ 1. CID Map → Decode Telugu chars        │
│ 2. indic_transliteration → phonetic key │
│ 3. House normalization → search ready   │
│ 4. Gender detection from cell chars     │
│ 5. Village from PDF header              │
│ 6. Config saved to DB automatically     │
└─────────────────────────────────────────┘
      ↓
SQLite DB (voters.db)
      ↓
Flutter App → Offline Search
```

### Database Schema
```sql
-- Voter records
voters (
    id, part, serial, page,
    house, house_norm,        -- normalized for search
    name, name_key,           -- Telugu + phonetic English
    rel, rel_name, rel_key,   -- relation type + name
    gender, age, epic
)

-- Polling station info
parts (
    part, village, male, female, total
)

-- Auto-set from PDFs
config (
    key, value
    -- const_name = 'డోన్'
    -- ac_number  = '181'
    -- year       = '2002'
)
```

---

## 📱 App Features

### Search
| Type | How to search | Example |
|---|---|---|
| Name | Telugu or English | `రెడ్డి` or `reddy` |
| Relation | Father/Husband name | `narasimhulu` |
| House | Full or partial | `7-2` or `1-42` |
| EPIC | Full or partial | `AP261810` |

### Filters
- **Village dropdown** — filter by any of 88 villages
- **Part dropdown** — filter by specific polling booth
- Selecting a village auto-selects all its parts

### Voter Card
Each card shows:
- Serial number + Part + Page
- Full name in Telugu
- Relation (Father/Husband) name
- House number + Village
- Age + Gender
- EPIC number (exactly as in PDF)

### Detail Sheet
Tap any card to see full bilingual detail:
- గ్రామం / Village
- ఇంటి నంబరు / House No
- తండ్రి/భర్త / Father/Husband
- లింగం / Gender
- వయసు / Age
- ఓటరు కార్డు / EPIC
- పుట / Page

---

## ⚠️ Important Notes

- This app is for **reference only** — not for official use
- EPIC showing `AP261810000000` means no EPIC was issued to that voter in 2002 — this is correct ECI data
- Verify any record using Part + Page + Serial from original ECI PDF
- Official voter information: **voters.eci.gov.in**

---

## 🐛 Troubleshooting

| Problem | Fix |
|---|---|
| `python not recognized` | Run: `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")` |
| `flutter not recognized` | Restart PowerShell after Flutter install |
| `No PDFs found` | Make sure PDFs are in the correct folder |
| `License not accepted` | Run `flutter doctor --android-licenses` and press `y` |
| APK won't install | Enable "Install from Unknown Sources" in phone settings |
| App name shows "voter_search" | Run `build_apk.ps1` — it sets the name automatically |
| Telugu names garbled | Normal for some names — phonetic search still works |

---

## 📊 Dhone AC-181 Stats

| Metric | Count |
|---|---|
| Total Voters | 1,71,256 |
| Male | 84,760 |
| Female | 86,496 |
| Polling Stations | 186 |
| Villages | 88 |
| Valid EPICs | 1,03,239 |

---

## 🔧 Tech Stack

| Component | Technology |
|---|---|
| PDF Extraction | Python + pdfplumber |
| Telugu Transliteration | indic-transliteration |
| Database | SQLite |
| Android App | Flutter (Dart) |
| Build Automation | PowerShell |

---

## 📁 Constituencies Covered

| Constituency | AC No | Status |
|---|---|---|
| Dhone | 181 | ✅ Complete |
| Others | — | 🔄 Add PDFs and run 2 commands |

---

## 👥 Contributing

1. Fork this repo
2. Add PDFs for your constituency in `pdfs_yourconst/`
3. Run `python pipeline\build_db.py pdfs_yourconst output\yourconst.db`
4. Run `.\build_apk.ps1 -DbPath "output\yourconst.db"`
5. Share the APK!

---

*Built with ❤️ for AP voters | SIR 2002 Electoral Roll*
*Last updated: June 2026*