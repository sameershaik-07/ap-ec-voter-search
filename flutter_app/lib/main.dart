import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

const kAppName   = 'My Dhone';
const kConstName = 'Dhone';
const kAcNumber  = '181';
const kYear      = '2002';
const kPrimary     = Color(0xFF0D3B8E);
const kSaffron     = Color(0xFFFF6B00);
const kGold        = Color(0xFFFFB300);
const kFemaleColor = Color(0xFFD81B60);
const kMaleColor   = Color(0xFF1565C0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kPrimary,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const VoterApp());
}

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

  static Future<List<Map<String,dynamic>>> searchName(String q, {List<int>? parts}) async {
    final d   = await db;
    final key = '%${q.toLowerCase()}%';
    if (parts != null && parts.isNotEmpty) {
      final ph = parts.map((_) => '?').join(',');
      return d.rawQuery(
        'SELECT * FROM voters WHERE (name_key LIKE ? OR rel_key LIKE ?) AND part IN ($ph) ORDER BY part,serial LIMIT 200',
        [key, key, ...parts]);
    }
    return d.rawQuery(
      'SELECT * FROM voters WHERE name_key LIKE ? OR rel_key LIKE ? ORDER BY part,serial LIMIT 200',
      [key, key]);
  }

  static Future<List<Map<String,dynamic>>> searchHouse(String q, {List<int>? parts}) async {
    final d = await db;
    if (parts != null && parts.isNotEmpty) {
      final ph = parts.map((_) => '?').join(',');
      return d.rawQuery(
        'SELECT * FROM voters WHERE house_norm LIKE ? AND part IN ($ph) ORDER BY house_norm,serial LIMIT 200',
        ['%$q%', ...parts]);
    }
    return d.rawQuery(
      'SELECT * FROM voters WHERE house_norm LIKE ? ORDER BY house_norm,serial LIMIT 200',
      ['%$q%']);
  }

  static Future<List<Map<String,dynamic>>> searchEpic(String q) async {
    final d = await db;
    return d.rawQuery(
      "SELECT * FROM voters WHERE REPLACE(REPLACE(UPPER(epic),'-',''),'/','') LIKE ? LIMIT 50",
      ['%${q.toUpperCase()}%']);
  }

  static Future<List<Map<String,dynamic>>> getParts() async {
    final d = await db;
    return d.query('parts', orderBy: 'part');
  }

  static Future<Map<String,int>> getStats() async {
    final d     = await db;
    final total = (await d.rawQuery('SELECT COUNT(*) as c FROM voters'))[0]['c'] as int;
    final male  = (await d.rawQuery("SELECT COUNT(*) as c FROM voters WHERE gender='పు'"))[0]['c'] as int;
    final parts = (await d.rawQuery('SELECT COUNT(*) as c FROM parts'))[0]['c'] as int;
    return {'total': total, 'male': male, 'female': total - male, 'parts': parts};
  }
}

class VoterApp extends StatelessWidget {
  const VoterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kPrimary,
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final prefs    = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('disclaimer_accepted') ?? false;
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => accepted ? const HomePage() : const DisclaimerScreen(),
    ));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPrimary, Color(0xFF1A237E)],
          ),
        ),
        child: FadeTransition(
          opacity: _fade,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
                  ),
                  child: const Icon(Icons.how_to_vote, size: 56, color: kPrimary),
                ),
                const SizedBox(height: 24),
                const Text(kAppName,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                    color: Colors.white, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text('$kConstName AC-$kAcNumber | SIR $kYear',
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 48),
                const SizedBox(width: 32, height: 32,
                  child: CircularProgressIndicator(color: kSaffron, strokeWidth: 3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.how_to_vote, color: kPrimary, size: 32),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kAppName,
                    style: const TextStyle(fontSize: 22,
                      fontWeight: FontWeight.bold, color: kPrimary)),
                  Text('$kConstName AC-$kAcNumber',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ]),
              ]),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange[50]!, Colors.amber[50]!],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kSaffron.withOpacity(0.3)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.info_rounded, color: kSaffron),
                          const SizedBox(width: 8),
                          const Text('Important Notice',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ]),
                        const SizedBox(height: 16),
                        _point('This app is built to make searching the $kYear SIR voter list ($kConstName AC-$kAcNumber) easy.'),
                        _point('For any official purpose, only the original list published by ECI / CEO Andhra Pradesh is authoritative.'),
                        _point('For the latest voter information visit voters.eci.gov.in'),
                        _point('If you notice any difference, verify against the original PDF using the Part, Page and Serial number shown with every record.'),
                      ],
                    ),
                  ),
                ),
              ),
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
                    if (context.mounted) {
                      Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const HomePage()));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _point(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.circle, size: 7, color: kSaffron),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
    ]),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  int   _mode  = 0;
  List<Map<String,dynamic>> _results    = [];
  bool  _searching   = false;
  bool  _hasSearched = false;
  Map<String,int>           _stats    = {};
  List<Map<String,dynamic>> _allParts = [];
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
    List<Map<String,dynamic>> res;
    switch (_mode) {
      case 1:  res = await VoterDB.searchHouse(q, parts: parts); break;
      case 2:  res = await VoterDB.searchEpic(q); break;
      default: res = await VoterDB.searchName(q, parts: parts);
    }
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimary, Color(0xFF1565C0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(kAppName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text('$kConstName AC-$kAcNumber | SIR $kYear',
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _selectedParts.isNotEmpty,
              label: Text(_selectedParts.length.toString()),
              child: const Icon(Icons.filter_list)),
            onPressed: _showFilter,
          ),
        ],
      ),
      body: Column(children: [
        _buildSearchBar(),
        Expanded(child: _hasSearched ? _buildResults() : _buildHome()),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))],
      ),
      child: Column(children: [
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            _tab(0, Icons.person_search, 'Name'),
            _tab(1, Icons.home_work,     'House No'),
            _tab(2, Icons.badge,         'EPIC'),
          ]),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          focusNode:  _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          onChanged:   (v) => setState(() {}),
          decoration: InputDecoration(
            hintText: _mode == 0
              ? 'Enter voter or relation name...'
              : _mode == 1
                ? 'Enter house number e.g. 7-2/3'
                : 'Enter EPIC number e.g. AP2618...',
            prefixIcon: const Icon(Icons.search, color: kPrimary),
            suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _ctrl.clear();
                    _results = [];
                    _hasSearched = false;
                  }))
              : null,
            filled: true,
            fillColor: const Color(0xFFF5F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPrimary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        if (_ctrl.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity, height: 42,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kSaffron,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
              icon: _searching
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.search, size: 18),
              label: Text(_searching ? 'Searching...' : 'Search',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => _search(_ctrl.text),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _tab(int idx, IconData icon, String label) {
    final sel = _mode == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = idx;
          _ctrl.clear();
          _results = [];
          _hasSearched = false;
          _focus.requestFocus();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: sel ? kPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: sel ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 4),
            Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey[600])),
          ]),
        ),
      ),
    );
  }

  Widget _buildHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        if (_stats.isNotEmpty) ...[
          Row(children: [
            _statCard('Total Voters', _stats['total'].toString(), Icons.people,      kPrimary),
            const SizedBox(width: 12),
            _statCard('Parts',        _stats['parts'].toString(), Icons.location_on, kSaffron),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _statCard('Male',   _stats['male'].toString(),   Icons.male,   kMaleColor),
            const SizedBox(width: 12),
            _statCard('Female', _stats['female'].toString(), Icons.female, kFemaleColor),
          ]),
          const SizedBox(height: 24),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            _howTo(Icons.person_search, kPrimary,  'Search by Name',
              'Type the voter name or relation name'),
            const Divider(height: 24),
            _howTo(Icons.home_work,     kSaffron,  'Search by House No',
              'Enter house number like 7-2/3 or partial 7-2'),
            const Divider(height: 24),
            _howTo(Icons.badge,         Colors.green, 'Search by EPIC',
              'Enter EPIC card number like AP261810...'),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.amber[700]),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'For official purposes verify with original ECI PDF',
              style: TextStyle(fontSize: 12, color: Colors.amber[800]),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.1),
          blurRadius: 8, offset: const Offset(0,2))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
      ]),
    ));
  }

  Widget _howTo(IconData icon, Color color, String title, String desc) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        Text(desc,
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ])),
    ]);
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_results.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('No results found',
          style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text('Try different spelling or search term',
          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      ]));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16,10,16,4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_results.length} result${_results.length == 1 ? "" : "s"}${_results.length == 200 ? " (first 200)" : ""}',
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

  void _showFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        allParts: _allParts,
        selected: Set.from(_selectedParts),
        onApply:  (s) => setState(() {
          _selectedParts.clear();
          _selectedParts.addAll(s);
        }),
      ),
    );
  }
}

class _VoterCard extends StatelessWidget {
  final Map<String,dynamic> data;
  const _VoterCard({required this.data});

  bool get _hasEpic {
    final e = data['epic'] as String;
    return e.isNotEmpty
      && e != 'AP261810000000'
      && e != '00000000000000';
  }

  String _relLabel(String rel) {
    switch (rel.trim()) {
      case 'భ':    return 'Husband';
      case 'తం':   return 'Father';
      case 'భా':   return 'Wife';
      case 'తల్లి': return 'Mother';
      default:     return rel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMale = data['gender'] != 'స్త్రీ';
    final gColor = isMale ? kMaleColor : kFemaleColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8, offset: const Offset(0,2))],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [gColor.withOpacity(0.08), Colors.transparent],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: gColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMale ? Icons.person : Icons.person_2,
                color: gColor, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] as String,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if ((data['rel_name'] as String).isNotEmpty)
                  Text(
                    '${_relLabel(data["rel"] as String)} : ${data["rel_name"]}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: gColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isMale ? 'Male' : 'Female',
                style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            Row(children: [
              _detail(Icons.home_outlined, 'House',
                (data['house'] as String).isEmpty ? '-' : data['house'] as String),
              _detail(Icons.cake_outlined,           'Age',    data['age'] as String),
              _detail(Icons.pin_outlined,            'Part',   data['part'].toString()),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _detail(Icons.menu_book_outlined,      'Page',   data['page'].toString()),
              _detail(Icons.format_list_numbered,    'Serial', data['serial'].toString()),
              _detail(Icons.badge_outlined,          'EPIC',
                _hasEpic ? (data['epic'] as String).substring(0,8)+'...' : '-',
                color: _hasEpic ? kPrimary : null),
            ]),
            if (_hasEpic) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kPrimary.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.badge, size: 16, color: kPrimary),
                  const SizedBox(width: 8),
                  Text('EPIC: ${data["epic"]}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: kPrimary, fontSize: 13)),
                ]),
              ),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share Voter Details',
                  style: TextStyle(fontSize: 13)),
                onPressed: _share,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _detail(IconData icon, String label, String val, {Color? color}) {
    return Expanded(child: Column(children: [
      Icon(icon, size: 16, color: color ?? Colors.grey[500]),
      const SizedBox(height: 2),
      Text(val,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: color ?? Colors.black87),
        overflow: TextOverflow.ellipsis),
      Text(label,
        style: TextStyle(fontSize: 10, color: Colors.grey[500])),
    ]));
  }

  void _share() {
    final epic = _hasEpic ? '\nEPIC   : ${data["epic"]}' : '';
    Share.share(
      '$kConstName Voter List (SIR $kYear)\n'
      '━━━━━━━━━━━━━━━━━━━━━━\n'
      'Name   : ${data["name"]}\n'
      'House  : ${data["house"]}\n'
      'Age    : ${data["age"]}\n'
      'Part   : ${data["part"]} | Page: ${data["page"]} | Serial: ${data["serial"]}'
      '$epic\n\n'
      'Verify at: voters.eci.gov.in',
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final List<Map<String,dynamic>> allParts;
  final Set<int>                  selected;
  final void Function(Set<int>)   onApply;
  const _FilterSheet({
    required this.allParts,
    required this.selected,
    required this.onApply,
  });
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<int> _sel;
  @override
  void initState() { super.initState(); _sel = Set.from(widget.selected); }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize:     0.9,
        minChildSize:     0.4,
        expand: false,
        builder: (_, scroll) => Column(children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Text('Filter by Part',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _sel.clear()),
                child: const Text('Clear All')),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: ListView.builder(
            controller: scroll,
            itemCount:  widget.allParts.length,
            itemBuilder: (_, i) {
              final part = widget.allParts[i];
              final num  = part['part'] as int;
              final tot  = part['total'] as int;
              return CheckboxListTile(
                value:    _sel.contains(num),
                onChanged: (v) => setState(() =>
                  v == true ? _sel.add(num) : _sel.remove(num)),
                title: Text('Part $num — ${part["village"]}'),
                subtitle: Text('$tot voters',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                activeColor: kPrimary,
                dense: true,
              );
            },
          )),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16,
              MediaQuery.of(context).padding.bottom + 8),
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
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}