import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

// ── Config — change these 4 lines per constituency ───────────────────────────
const kAppName   = 'My Dhone';
const kConstName = 'Dhone';
const kAcNumber  = '181';
const kYear      = '2002';

// ── Colors ───────────────────────────────────────────────────────────────────
const kPrimary     = Color(0xFF0D3B8E);
const kSaffron     = Color(0xFFFF6B00);
const kMaleColor   = Color(0xFF1565C0);
const kFemaleColor = Color(0xFFD81B60);

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Capitalize each word: "vade narasinhulu" -> "Vade Narasinhulu"
String capitalize(String s) {
  if (s.trim().isEmpty) return '';
  return s.trim().split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Valid EPIC = not empty, not all zeros, not ending in 000000
bool isValidEpic(String epic) {
  if (epic.isEmpty) return false;
  if (epic == '00000000000000') return false;
  if (epic.endsWith('000000')) return false;
  return epic.length >= 10;
}

/// Human readable relation
String relLabel(String rel) {
  switch (rel.trim()) {
    case 'భ':      return 'Husband';
    case 'తం':     return 'Father';
    case 'భా':     return 'Wife';
    case 'తల్లి':  return 'Mother';
    default:       return rel.trim();
  }
}

// ── Database ──────────────────────────────────────────────────────────────────
class VoterDB {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'voters.db');
    if (!await File(path).exists()) {
      final data  = await rootBundle.load('assets/voters.db');
      final bytes = data.buffer.asUint8List();
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return openDatabase(path, readOnly: true);
  }

  static Future<List<Map<String, dynamic>>> searchName(
      String q, {List<int>? parts}) async {
    final d   = await db;
    final key = '%${q.toLowerCase().trim()}%';
    if (parts != null && parts.isNotEmpty) {
      final ph = parts.map((_) => '?').join(',');
      return d.rawQuery(
        'SELECT * FROM voters '
        'WHERE (name_key LIKE ? OR rel_key LIKE ?) '
        'AND part IN ($ph) '
        'ORDER BY part, serial LIMIT 200',
        [key, key, ...parts]);
    }
    return d.rawQuery(
      'SELECT * FROM voters '
      'WHERE name_key LIKE ? OR rel_key LIKE ? '
      'ORDER BY part, serial LIMIT 200',
      [key, key]);
  }

  static Future<List<Map<String, dynamic>>> searchHouse(
      String q, {List<int>? parts}) async {
    final d    = await db;
    // Use boundary markers matching build_db.py norm_house()
    // '-7-2-' stored in house_norm, search '%- 7-2-%' finds correct results
    final norm = '%-' + q.trim().replaceAll('/', '-').toLowerCase() + '-%';
    if (parts != null && parts.isNotEmpty) {
      final ph = parts.map((_) => '?').join(',');
      return d.rawQuery(
        'SELECT * FROM voters '
        'WHERE house_norm LIKE ? '
        'AND part IN ($ph) '
        'ORDER BY house_norm, part, serial LIMIT 200',
        [norm, ...parts]);
    }
    return d.rawQuery(
      'SELECT * FROM voters '
      'WHERE house_norm LIKE ? '
      'ORDER BY house_norm, part, serial LIMIT 200',
      [norm]);
  }

  static Future<List<Map<String, dynamic>>> searchEpic(String q) async {
    final d     = await db;
    final clean = q.toUpperCase().replaceAll('-', '').replaceAll(' ', '');
    return d.rawQuery(
      "SELECT * FROM voters "
      "WHERE REPLACE(REPLACE(UPPER(epic),'-',' '),' ','') LIKE ? LIMIT 50",
      ['%$clean%']);
  }

  static Future<List<Map<String, dynamic>>> getParts() async {
    return (await db).query('parts', orderBy: 'part');
  }

  static Future<Map<String, int>> getStats() async {
    final d      = await db;
    final total  = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM voters')) ?? 0;
    final male   = Sqflite.firstIntValue(await d.rawQuery("SELECT COUNT(*) FROM voters WHERE gender='పు'")) ?? 0;
    final parts  = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM parts')) ?? 0;
    final epic   = Sqflite.firstIntValue(await d.rawQuery(
        "SELECT COUNT(*) FROM voters WHERE epic!='' AND epic!='00000000000000' AND epic NOT LIKE '%000000'")) ?? 0;
    return {'total': total, 'male': male, 'female': total - male, 'parts': parts, 'epic': epic};
  }
}

// ── App ───────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kPrimary,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const VoterApp());
}

class VoterApp extends StatelessWidget {
  const VoterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kAppName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: kPrimary,
      appBarTheme: const AppBarTheme(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    ),
    home: const SplashScreen(),
  );
}

// ── Splash ────────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final prefs    = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('disclaimer_accepted') ?? false;
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => accepted ? const HomePage() : const DisclaimerScreen()));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [kPrimary, Color(0xFF1A237E)],
        ),
      ),
      child: FadeTransition(
        opacity: _fade,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 110, height: 110,
            decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 24)],
            ),
            child: const Icon(Icons.how_to_vote, size: 60, color: kPrimary),
          ),
          const SizedBox(height: 28),
          Text(kAppName, style: const TextStyle(
            fontSize: 34, fontWeight: FontWeight.bold,
            color: Colors.white, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text('$kConstName AC-$kAcNumber  |  SIR $kYear',
            style: const TextStyle(color: Colors.white60, fontSize: 14)),
          const SizedBox(height: 52),
          const SizedBox(width: 32, height: 32,
            child: CircularProgressIndicator(color: kSaffron, strokeWidth: 3)),
        ])),
      ),
    ),
  );
}

// ── Disclaimer ────────────────────────────────────────────────────────────────
class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.how_to_vote, color: kPrimary, size: 34),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kAppName, style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: kPrimary)),
            Text('$kConstName AC-$kAcNumber',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ]),
        ]),
        const SizedBox(height: 24),
        Expanded(child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange[50]!, Colors.amber[50]!],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kSaffron.withOpacity(0.3)),
          ),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.info_rounded, color: kSaffron),
                const SizedBox(width: 8),
                const Text('Important Notice',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 16),
              _point('This app helps you search the $kYear SIR voter list for $kConstName AC-$kAcNumber.'),
              _point('Voter names are shown in Telugu. Search works in both Telugu and English phonetic.'),
              _point('For official purposes only the original ECI / CEO Andhra Pradesh list is authoritative.'),
              _point('Verify any record using Part, Page and Serial number shown on each card.'),
              _point('For latest voter information visit voters.eci.gov.in'),
            ],
          )),
        )),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('I Understand, Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('disclaimer_accepted', true);
              if (context.mounted) Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const HomePage()));
            },
          ),
        ),
      ]),
    )),
  );

  Widget _point(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.circle, size: 7, color: kSaffron),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
        style: const TextStyle(height: 1.5, fontSize: 14))),
    ]),
  );
}

// ── Home ──────────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  int   _mode  = 0; // 0=name 1=house 2=epic

  List<Map<String, dynamic>> _results    = [];
  bool  _searching   = false;
  bool  _hasSearched = false;
  Map<String, int>           _stats    = {};
  List<Map<String, dynamic>> _allParts = [];
  final Set<int> _selectedParts = {};

  @override
  void initState() {
    super.initState();
    VoterDB.getStats().then((s) => setState(() => _stats = s));
    VoterDB.getParts().then((pp) => setState(() => _allParts = pp));
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _hasSearched = true; });
    final parts = _selectedParts.isEmpty ? null : _selectedParts.toList();
    List<Map<String, dynamic>> res;
    switch (_mode) {
      case 1:  res = await VoterDB.searchHouse(q, parts: parts); break;
      case 2:  res = await VoterDB.searchEpic(q); break;
      default: res = await VoterDB.searchName(q, parts: parts);
    }
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimary, Color(0xFF1565C0)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(kAppName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text('$kConstName AC-$kAcNumber  |  SIR $kYear',
          style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ]),
      actions: [
        IconButton(
          icon: Badge(
            isLabelVisible: _selectedParts.isNotEmpty,
            label: Text(_selectedParts.length.toString()),
            child: const Icon(Icons.filter_list)),
          onPressed: _showFilter),
      ],
    ),
    body: Column(children: [
      _searchBar(),
      Expanded(child: _hasSearched ? _results_widget() : _home()),
    ]),
  );

  Widget _searchBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
    ),
    child: Column(children: [
      // Tabs
      Container(
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          _tab(0, Icons.person_search,  'Name'),
          _tab(1, Icons.home_work,      'House No'),
          _tab(2, Icons.badge_outlined, 'EPIC'),
        ]),
      ),
      const SizedBox(height: 10),
      // Input
      TextField(
        controller: _ctrl,
        focusNode:  _focus,
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        onChanged:   (v) => setState(() {}),
        decoration: InputDecoration(
          hintText: _mode == 0 ? 'Type name in Telugu or English e.g. రెడ్డి, raju...'
              : _mode == 1    ? 'House number e.g. 7-2/3 or 22-42'
              :                 'EPIC number e.g. AP261810...',
          prefixIcon: const Icon(Icons.search, color: kPrimary),
          suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _ctrl.clear(); _results = []; _hasSearched = false; }))
              : null,
          filled: true, fillColor: const Color(0xFFF5F7FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
      if (_ctrl.text.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity, height: 44,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kSaffron,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
            icon: _searching
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.search, size: 18),
            label: Text(_searching ? 'Searching...' : 'Search',
              style: const TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _search(_ctrl.text),
          ),
        ),
      ],
      if (_selectedParts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.filter_alt, size: 14, color: kPrimary),
            const SizedBox(width: 4),
            Text('Filtering ${_selectedParts.length} part(s)',
              style: const TextStyle(fontSize: 12, color: kPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _selectedParts.clear()),
              child: const Text('Clear',
                style: TextStyle(fontSize: 12, color: Colors.red))),
          ]),
        ),
    ]),
  );

  Widget _tab(int idx, IconData icon, String label) {
    final sel = _mode == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() {
        _mode = idx; _ctrl.clear();
        _results = []; _hasSearched = false;
        _focus.requestFocus();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: sel ? kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14,
            color: sel ? Colors.white : Colors.grey[600]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: sel ? Colors.white : Colors.grey[600])),
        ]),
      ),
    ));
  }

  Widget _home() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      if (_stats.isNotEmpty) ...[
        Row(children: [
          _statCard('Total Voters', _stats['total'].toString(),
            Icons.people_alt_outlined, kPrimary),
          const SizedBox(width: 12),
          _statCard('Parts', _stats['parts'].toString(),
            Icons.location_on_outlined, kSaffron),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statCard('Male',   _stats['male'].toString(),
            Icons.male,   kMaleColor),
          const SizedBox(width: 12),
          _statCard('Female', _stats['female'].toString(),
            Icons.female, kFemaleColor),
        ]),
        const SizedBox(height: 12),
        _wideCard('${_stats['epic']} voters have valid EPIC cards',
          Icons.badge_outlined, Colors.green),
        const SizedBox(height: 24),
      ],
      // How to search
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
        child: Column(children: [
          _howTo(Icons.person_search, kPrimary, 'Search by Name',
            'Type phonetic name — raju, reddy, venkat, lakshmi...'),
          const Divider(height: 24),
          _howTo(Icons.home_work, kSaffron, 'Search by House No',
            'Type house number like 7-2/3 or partial like 22-42'),
          const Divider(height: 24),
          _howTo(Icons.badge_outlined, Colors.green, 'Search by EPIC Card',
            'Type EPIC number like AP261810...'),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Names are in Telugu. Search by Telugu name or English phonetic e.g. "raju" finds రాజు.',
            style: TextStyle(fontSize: 12, color: Colors.blue[800]))),
        ]),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade200)),
        child: Row(children: [
          Icon(Icons.warning_amber_outlined, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'For official purposes verify with original ECI PDF',
            style: TextStyle(fontSize: 12, color: Colors.amber[800]))),
        ]),
      ),
    ]),
  );

  Widget _statCard(String label, String value, IconData icon, Color color) =>
    Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.1),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(
            fontSize: 11, color: Colors.grey[600])),
        ]),
      ]),
    ));

  Widget _wideCard(String text, IconData icon, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(
        color: color.withOpacity(0.1),
        blurRadius: 8, offset: const Offset(0, 2))]),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22)),
      const SizedBox(width: 12),
      Text(text, style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: color)),
    ]),
  );

  Widget _howTo(IconData icon, Color color, String title, String desc) =>
    Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 14)),
          Text(desc, style: TextStyle(
            fontSize: 12, color: Colors.grey[600])),
        ])),
    ]);

  Widget _results_widget() {
    if (_searching) return const Center(
      child: CircularProgressIndicator(color: kPrimary));
    if (_results.isEmpty) return Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 12),
      Text('No results found',
        style: TextStyle(fontSize: 16, color: Colors.grey[600])),
      const SizedBox(height: 4),
      Text('Try different spelling or partial number',
        style: TextStyle(fontSize: 13, color: Colors.grey[400])),
    ]));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Text(
              '${_results.length} result${_results.length == 1 ? "" : "s"}'
              '${_results.length == 200 ? " (first 200)" : ""}',
              style: const TextStyle(
                color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ]),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _results.length,
        itemBuilder: (ctx, i) => _VoterCard(data: _results[i]),
      )),
    ]);
  }

  void _showFilter() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FilterSheet(
      allParts: _allParts,
      selected: Set.from(_selectedParts),
      onApply: (s) => setState(() {
        _selectedParts.clear(); _selectedParts.addAll(s); }),
    ),
  );
}

// ── Voter Card ────────────────────────────────────────────────────────────────
class _VoterCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _VoterCard({required this.data});

  bool   get _isMale  => (data['gender'] as String? ?? '') != 'స్త్రీ';
  bool   get _hasEpic => isValidEpic(data['epic'] as String? ?? '');
  String get _name {
    final telugu = (data['name'] as String? ?? '').trim();
    if (telugu.isNotEmpty) return telugu;
    return capitalize(data['name_key'] as String? ?? '');
  }
  String get _relName {
    final telugu = (data['rel_name'] as String? ?? '').trim();
    if (telugu.isNotEmpty) return telugu;
    return capitalize(data['rel_key'] as String? ?? '');
  }
  String get _rel     => relLabel(data['rel'] as String? ?? '');
  String get _house {
    final h = (data['house'] as String? ?? '').trim();
    return (h == '----' || h.isEmpty) ? '-' : h;
  }
  String get _age    => data['age']?.toString()    ?? '-';
  String get _part   => data['part']?.toString()   ?? '-';
  String get _page   => data['page']?.toString()   ?? '-';
  String get _serial => data['serial']?.toString() ?? '-';
  String get _epic   => data['epic']  as String?   ?? '';

  @override
  Widget build(BuildContext context) {
    final gColor = _isMale ? kMaleColor : kFemaleColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [gColor.withOpacity(0.08), Colors.transparent],
              begin: Alignment.centerLeft, end: Alignment.centerRight),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: gColor.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(
                _isMale ? Icons.person : Icons.person_2,
                color: gColor, size: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.isEmpty ? 'Unknown' : _name,
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
              if (_relName.isNotEmpty)
                Text(
                  '${_rel.isNotEmpty ? "$_rel: " : ""}$_relName',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: gColor, borderRadius: BorderRadius.circular(20)),
              child: Text(_isMale ? 'Male' : 'Female',
                style: const TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w600))),
          ]),
        ),

        // Details
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(children: [
            Row(children: [
              _det(Icons.home_outlined,        'House',  _house),
              _det(Icons.cake_outlined,        'Age',    _age),
              _det(Icons.pin_outlined,         'Part',   _part),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _det(Icons.menu_book_outlined,   'Page',   _page),
              _det(Icons.format_list_numbered, 'Serial', _serial),
              _det(Icons.badge_outlined,       'EPIC',
                _hasEpic ? _epic.substring(0, 8) + '...' : 'Not issued',
                color: _hasEpic ? kPrimary : Colors.grey[400]),
            ]),
            if (_hasEpic) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kPrimary.withOpacity(0.25))),
                child: Row(children: [
                  const Icon(Icons.badge, size: 16, color: kPrimary),
                  const SizedBox(width: 8),
                  Text('EPIC: $_epic', style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: kPrimary, fontSize: 13)),
                ])),
            ],
            if (!_hasEpic) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200)),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 6),
                  Text('EPIC card not issued in 2002',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ])),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: BorderSide(color: kPrimary.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8)),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share Voter Details',
                  style: TextStyle(fontSize: 13)),
                onPressed: _share)),
          ]),
        ),
      ]),
    );
  }

  Widget _det(IconData icon, String label, String val, {Color? color}) =>
    Expanded(child: Column(children: [
      Icon(icon, size: 16, color: color ?? Colors.grey[400]),
      const SizedBox(height: 3),
      Text(val, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700,
        color: color ?? Colors.black87),
        overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        textAlign: TextAlign.center),
    ]));

  void _share() {
    final relLine  = (_rel.isNotEmpty && _relName.isNotEmpty)
        ? '$_rel: $_relName\n' : '';
    final epicLine = _hasEpic ? 'EPIC   : $_epic\n' : '';
    Share.share(
      '$kConstName Voter List (SIR $kYear)\n'
      '━━━━━━━━━━━━━━━━━━━━━━\n'
      'Name   : $_name\n'
      '${relLine}'
      'House  : $_house\n'
      'Age    : $_age  |  ${_isMale ? "Male" : "Female"}\n'
      'Part: $_part  |  Page: $_page  |  Serial: $_serial\n'
      '${epicLine}'
      '\nVerify at: voters.eci.gov.in');
  }
}

// ── Filter Sheet ──────────────────────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  final List<Map<String, dynamic>> allParts;
  final Set<int>                   selected;
  final void Function(Set<int>)    onApply;
  const _FilterSheet({
    required this.allParts,
    required this.selected,
    required this.onApply});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<int> _sel;
  @override
  void initState() { super.initState(); _sel = Set.from(widget.selected); }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    child: DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize:     0.92,
      minChildSize:     0.4,
      expand: false,
      builder: (_, scroll) => Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            const Text('Filter by Part',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _sel.clear()),
              child: const Text('Clear All')),
          ])),
        const Divider(height: 1),
        Expanded(child: ListView.builder(
          controller: scroll,
          itemCount:  widget.allParts.length,
          itemBuilder: (_, i) {
            final part   = widget.allParts[i];
            final num    = part['part']   as int;
            final total  = part['total']  as int? ?? 0;
            final male   = part['male']   as int? ?? 0;
            final female = part['female'] as int? ?? 0;
            return CheckboxListTile(
              value: _sel.contains(num),
              onChanged: (v) => setState(() =>
                v == true ? _sel.add(num) : _sel.remove(num)),
              title: Text('Part $num',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Total: $total  |  Male: $male  |  Female: $female',
                style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              activeColor: kPrimary,
              dense: true);
          })),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
          child: SizedBox(
            width: double.infinity, height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                widget.onApply(_sel);
                Navigator.pop(context);
              },
              child: Text(
                _sel.isEmpty ? 'Show All' : 'Apply (${_sel.length} parts)',
                style: const TextStyle(fontWeight: FontWeight.w600))))),
      ]),
    ),
  );
}