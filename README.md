# 🗳️ AP Voter Search App
### Find any voter from the 2002 Andhra Pradesh Electoral Roll — in seconds!

---

## 📖 What is this project?

This project helps you **search for voters** from the 2002 Special Intensive Revision (SIR) voter list of Andhra Pradesh.

It has **two parts:**
1. 🐍 **Python Pipeline** — reads PDF files from ECI and builds a searchable database
2. 📱 **Flutter App** — Android app that lets you search voters offline on your phone

---

## 📁 Project Folder Structure

```
ap-ec-voter-search/
│
├── pipeline/                  ← Python scripts (PDF → Database)
│   ├── requirements.txt       ← Python libraries needed
│   └── build_db.py            ← Main script that reads PDFs
│
├── flutter_app/               ← Android App code
│   ├── pubspec.yaml           ← App dependencies
│   ├── assets/
│   │   └── voters.db          ← Database (you generate this)
│   └── lib/
│       └── main.dart          ← Complete app code
│
├── output/                    ← Your generated files go here
│   ├── dhone.db               ← Generated database
│   └── MyDhone.apk            ← Generated APK for phone
│
├── pdfs/                      ← Put your PDF files here
│
└── README.md                  ← This file!
```

---

## 🖥️ What You Need (Prerequisites)

Before starting, you need these installed on your **Windows VM or PC:**

| Tool | What it does | Where to get it |
|---|---|---|
| Python 3.11 | Runs our scripts | Already installed on VM |
| Git | Saves code to GitHub | Already installed on VM |
| Java 17 | Needed for Android build | Already installed on VM |
| Flutter | Builds the Android app | Already installed on VM |
| Android SDK | Android build tools | Already installed on VM |

> ✅ **If you followed this guide from the beginning, all of these are already installed!**

---

## 🚀 PART 1 — Build the Database from PDFs

This part reads the ECI voter PDF files and creates a database (`voters.db`) that the app uses.

### Step 1 — Open PowerShell

Click **Start menu** → search **PowerShell** → right click → **Run as Administrator**

### Step 2 — Go to project folder

```powershell
cd C:\voter_project
```

### Step 3 — Create folders

```powershell
mkdir C:\voter_project\pdfs
mkdir C:\voter_project\output
```

### Step 4 — Copy your PDF files

Copy all your PDF files into this folder:
```
C:\voter_project\pdfs\
```

Your PDFs should be named like this:
```
S01_181_54.pdf
S01_181_55.pdf
S01_181_56.pdf
... and so on
```

> 💡 **Tip:** You can copy-paste files directly from your local laptop into the VM using RDP (Remote Desktop). Just copy on your laptop and paste inside the RDP window.

### Step 5 — Install Python libraries

```powershell
pip install pdfplumber pymupdf indic-transliteration
```

Wait for it to finish. You will see a lot of text — that is normal!

### Step 6 — Run the database builder

```powershell
python pipeline\build_db.py pdfs output\dhone.db
```

You will see output like this:
```
Found 22 PDFs -> output\dhone.db
[  1/22] S01_181_54.pdf ... 1059 voters | డోన్
[  2/22] S01_181_55.pdf ... 1084 voters | డోన్
...
Done in 278.0s | Total: 24812 voters | DB: output\dhone.db
```

> ⏱️ This takes about **4-5 minutes** for 22 PDFs. Just wait!

### Step 7 — Verify the database

```powershell
python -c "
import sqlite3
conn = sqlite3.connect('output/dhone.db')
total = conn.execute('SELECT COUNT(*) FROM voters').fetchone()[0]
parts = conn.execute('SELECT COUNT(*) FROM parts').fetchone()[0]
print('Total voters:', total)
print('Total parts:', parts)
conn.close()
"
```

You should see something like:
```
Total voters: 24812
Total parts: 22
```

✅ **Database is ready!**

---

## 📱 PART 2 — Build the Android App

This part builds the APK file that you install on your Android phone.

### Step 1 — Go to flutter app folder

```powershell
cd C:\voter_project\flutter_app
```

### Step 2 — Copy database to app assets

```powershell
copy C:\voter_project\output\dhone.db C:\voter_project\flutter_app\assets\voters.db
```

### Step 3 — Install app dependencies

```powershell
flutter pub get
```

Wait for it to finish. You will see:
```
Changed 54 dependencies!
```

### Step 4 — Accept Android licenses

```powershell
flutter doctor --android-licenses
```

For **every question** that appears, type `y` and press **Enter**.

Keep doing this until you see:
```
All SDK package licenses accepted
```

### Step 5 — Build the APK

```powershell
flutter build apk --release
```

This takes **3-5 minutes.** When done you will see:
```
✓ Built build\app\outputs\flutter-apk\app-release.apk (49.3MB)
```

✅ **APK is ready!**

### Step 6 — Copy APK to easy location

```powershell
copy C:\voter_project\flutter_app\build\app\outputs\flutter-apk\app-release.apk C:\voter_project\output\MyDhone.apk
```

---

## 📲 PART 3 — Install App on Your Phone

### Method 1 — Via USB Cable
1. Connect phone to your laptop with USB cable
2. Copy `C:\voter_project\output\MyDhone.apk` to your phone
3. Open the APK file on your phone
4. Click **Install**

### Method 2 — Via WhatsApp
1. Open VM browser → go to web.whatsapp.com
2. Send `MyDhone.apk` to yourself
3. Open WhatsApp on phone → download and install

### Method 3 — Via Google Drive
1. Upload `MyDhone.apk` to Google Drive from VM
2. Open Google Drive on phone → download → install

> ⚠️ **Important:** Before installing, go to phone **Settings → Security → Enable "Install from Unknown Sources"**

---

## 🔄 PART 4 — Doing This for Another Constituency

To build app for a different constituency (e.g. Kurnool), just change 3 things:

### Step 1 — Build new database

```powershell
# Put new constituency PDFs in a new folder
mkdir C:\voter_project\pdfs_kurnool

# Copy PDFs there, then run:
python pipeline\build_db.py pdfs_kurnool output\kurnool.db
```

### Step 2 — Update app name in main.dart

Open `C:\voter_project\flutter_app\lib\main.dart` in Notepad.

Find these lines at the top and change them:
```dart
const kAppName   = 'My Dhone';     // ← Change to 'My Kurnool'
const kConstName = 'Dhone';        // ← Change to 'Kurnool'
const kAcNumber  = '181';          // ← Change to correct AC number
```

### Step 3 — Copy new database and rebuild

```powershell
copy C:\voter_project\output\kurnool.db C:\voter_project\flutter_app\assets\voters.db
flutter build apk --release
copy C:\voter_project\flutter_app\build\app\outputs\flutter-apk\app-release.apk C:\voter_project\output\MyKurnool.apk
```

✅ **New APK ready in about 3 minutes!**

---

## 🔍 How to Use the App

Once installed on your phone:

1. **Open the app** → read disclaimer → tap **"I Understand, Continue"**

2. **Home screen** shows:
   - Total voters count
   - Male / Female count
   - Number of parts (polling booths)

3. **Search by Name** (default tab)
   - Type any part of the voter's name
   - Works even with partial names
   - Also searches relation names

4. **Search by House No**
   - Type house number like `7-2/3`
   - Partial search works too — type `7-2` to see all

5. **Search by EPIC**
   - Type EPIC card number like `AP261810`
   - Finds the exact voter

6. **Filter by Part** (funnel icon top right)
   - Filter results to specific polling booth parts
   - Useful when searching common names

7. **Share** any voter record via WhatsApp

---

## ⚠️ Important Notes

- This app is for **reference only** — not for official use
- Always verify with original ECI PDF using Part, Page and Serial numbers shown
- Official voter information: **voters.eci.gov.in**
- The names may appear garbled for 2002 PDFs due to old font encoding — this is a known issue. House number and EPIC search work perfectly.

---

## 🐛 Common Errors and Fixes

| Error | Fix |
|---|---|
| `python not recognized` | Run `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")` |
| `No PDFs found` | Make sure PDFs are in the correct folder |
| `flutter not recognized` | Restart PowerShell after Flutter install |
| `License not accepted` | Run `flutter doctor --android-licenses` and press `y` for all |
| APK not installing on phone | Enable "Install from Unknown Sources" in phone settings |

---

## 📊 What the Database Contains

| Column | Example | Description |
|---|---|---|
| part | 58 | Polling booth part number |
| serial | 123 | Voter serial number in part |
| page | 5 | Page number in PDF |
| house | 7-2/3 | House number |
| name | రాజేశ్వరి | Voter name in Telugu |
| name_key | rajesvari | Phonetic key for search |
| gender | పు / స్త్రీ | Male / Female |
| age | 35 | Age as of 2002 |
| epic | AP261810171000 | EPIC card number |

---

## 👥 Credits

- Original concept: My Dhone APK (anonymous developer)
- Enhanced pipeline and UI: kala-techies
- Built with: Python, Flutter, SQLite

---

## 📞 Need Help?

If something doesn't work:
1. Read the error message carefully
2. Check the **Common Errors** table above
3. Make sure all prerequisites are installed
4. Raise an issue on GitHub

---

*Last updated: June 2026 | AP Electoral Roll SIR 2002*