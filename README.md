# AP Voter Search App
Telugu Electoral Roll 2002 - Search Application

## Project Structure
- pipeline/     -> Python scripts to extract PDFs and build SQLite DB
- flutter_app/  -> Flutter Android app for offline voter search
- output/       -> Generated DBs and APKs (gitignored)

## Quick Start

### Step 1: Build Database
cd pipeline
pip install -r requirements.txt
python build_db.py ../pdfs/dhone/ ../output/dhone.db

### Step 2: Build APK
cd ../flutter_app
copy ..\output\dhone.db assets\voters.db
flutter build apk --release

## Constituencies Covered
- [ ] Dhone (AC-181)
- [ ] Kurnool
- [ ] Nandyal
- [ ] Atmakur
- [ ] Allagadda

## Tech Stack
- Python 3.11 + pdfplumber (PDF extraction)
- indic-transliteration (Telugu phonetic keys)
- SQLite (offline database)
- Flutter 3.x (Android app)

## Credits
Original concept: My Dhone APK
Enhanced UI and pipeline by this project
