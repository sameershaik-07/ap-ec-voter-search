import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:io';

// ── Config (auto-loaded from DB) ──────────────────────────────
String kAppName   = 'SIR శోధన';
String kConstName = '...';
String kAcNumber  = '...';
String kYear      = '2002';

// ── Colors ────────────────────────────────────────────────────
const kNavy    = Color(0xFF0B1F3A);
const kNavy2   = Color(0xFF1A3A5C);
const kGold    = Color(0xFFC8952A);
const kBlue    = Color(0xFF3B5BDB);
const kMale    = Color(0xFF1D6AE5);
const kFemale  = Color(0xFFBE185D);
const kGreen   = Color(0xFF2E7D32);
const kBg      = Color(0xFFF4F6FA);
const kCard    = Colors.white;
const kBorder  = Color(0xFFE8EAF0);

// ── Helpers ───────────────────────────────────────────────────
String capitalize(String s) {
  if (s.trim().isEmpty) return '';
  return s.trim().split(' ').where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

String relLabel(String rel) {
  switch (rel.trim()) {
    case 'తం':    return 'తండ్రి';
    case 'భ':     return 'భర్త';
    case 'భా':    return 'భార్య';
    case 'తల్లి': return 'తల్లి';
    case 'Z':     return 'తండ్రి';
    case 'R3':    return 'భర్త';
    default:      return 'తండ్రి';
  }
}

String relLabelEn(String rel) {
  switch (rel.trim()) {
    case 'తం':    return 'Father';
    case 'భ':     return 'Husband';
    case 'భా':    return 'Wife';
    case 'తల్లి': return 'Mother';
    case 'Z':     return 'Father';
    case 'R3':    return 'Husband';
    default:      return 'Father';
  }
}

bool isValidEpic(String e) =>
    e.isNotEmpty && e != '00000000000000';

// ── Database ──────────────────────────────────────────────────
class VoterDB {
  static Database? _db;
  static Future<Database> get db async { _db ??= await _open(); return _db!; }

  static Future<Database> _open() async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'voters.db');
    if (!await File(path).exists()) {
      final data  = await rootBundle.load('assets/voters.db');
      await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return openDatabase(path, readOnly: true);
  }

  static Future<void> loadConfig() async {
    try {
      final d    = await db;
      final rows = await d.query('config');
      final cfg  = {for (var r in rows) r['key'] as String: r['value'] as String};
      kConstName = cfg['const_name'] ?? kConstName;
      kAcNumber  = cfg['ac_number']  ?? kAcNumber;
      kYear      = cfg['year']       ?? kYear;
      kAppName   = '$kConstName SIR $kYear';
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> search(
      String q, {List<int>? parts, String? village}) async {
    q = q.trim();
    if (q.isEmpty) return [];
    if (RegExp(r'^[A-Za-z]{2}\d+$').hasMatch(q) || q.length >= 10)
      return _searchEpic(q);
    // AFTER — allows letters mixed in (3/53C, 3-53C, 2-75A, 3-18B etc.)
    if (RegExp(r'^\d').hasMatch(q))
      return _searchHouse(q, parts: parts, village: village);
    return _searchName(q, parts: parts, village: village);
  }

  static Future<List<Map<String, dynamic>>> _searchName(
      String q, {List<int>? parts, String? village}) async {
    final d    = await db;
    final key  = '%${q.toLowerCase()}%';
    final tkey = '%$q%';
    String where = 'WHERE (v.name_key LIKE ? OR v.rel_key LIKE ? OR v.name LIKE ? OR v.rel_name LIKE ?)';
    List<Object?> args = [key, key, tkey, tkey];
    if (village != null && village.isNotEmpty) {
      where += ' AND p.village = ?'; args.add(village);
    } else if (parts != null && parts.isNotEmpty) {
      where += ' AND v.part IN (${parts.map((_) => '?').join(',')})';
      args.addAll(parts);
    }
    return d.rawQuery(
      'SELECT v.*, p.village as village_name FROM voters v '
      'LEFT JOIN parts p ON v.part = p.part $where '
      'ORDER BY v.part, v.serial LIMIT 300', args);
  }

  static Future<List<Map<String, dynamic>>> _searchHouse(
      String q, {List<int>? parts, String? village}) async {
    final d    = await db;
    final norm = '%-${q.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '').toLowerCase()}-%';
    String where = 'WHERE v.house_norm LIKE ?';
    List<Object?> args = [norm];
    if (village != null && village.isNotEmpty) {
      where += ' AND p.village = ?'; args.add(village);
    } else if (parts != null && parts.isNotEmpty) {
      where += ' AND v.part IN (${parts.map((_) => '?').join(',')})';
      args.addAll(parts);
    }
    return d.rawQuery(
      'SELECT v.*, p.village as village_name FROM voters v '
      'LEFT JOIN parts p ON v.part = p.part $where '
      'ORDER BY v.house_norm, v.part, v.serial LIMIT 300', args);
  }

  static Future<List<Map<String, dynamic>>> _searchEpic(String q) async {
    final d     = await db;
    final clean = q.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    return d.rawQuery(
      'SELECT v.*, p.village as village_name FROM voters v '
      'LEFT JOIN parts p ON v.part = p.part '
      "WHERE REPLACE(UPPER(v.epic),'-','') LIKE ? LIMIT 50",
      ['%$clean%']);
  }

  static Future<List<String>> getVillages() async {
    final d = await db;
    final r = await d.rawQuery(
      'SELECT DISTINCT village FROM parts WHERE village IS NOT NULL '
      'AND village != "" ORDER BY village');
    return r.map((x) => x['village'] as String).toList();
  }

  static Future<List<Map<String, dynamic>>> getParts({String? village}) async {
    final d = await db;
    if (village != null && village.isNotEmpty)
      return d.rawQuery('SELECT * FROM parts WHERE village=? ORDER BY part', [village]);
    return d.query('parts', orderBy: 'part');
  }

  static Future<Map<String, dynamic>> getStats() async {
    final d  = await db;
    final tv = (await d.rawQuery('SELECT COUNT(*) c FROM voters'))[0]['c'] as int? ?? 0;
    final m  = (await d.rawQuery("SELECT COUNT(*) c FROM voters WHERE gender='పు'"))[0]['c'] as int? ?? 0;
    final pt = (await d.rawQuery('SELECT COUNT(*) c FROM parts'))[0]['c'] as int? ?? 0;
    final ep = (await d.rawQuery(
      "SELECT COUNT(*) c FROM voters WHERE epic!='' AND epic!='00000000000000' AND epic NOT LIKE '%000000'"))[0]['c'] as int? ?? 0;
    final vl = (await d.rawQuery('SELECT COUNT(DISTINCT village) c FROM parts'))[0]['c'] as int? ?? 0;
    return {'total': tv, 'male': m, 'female': tv - m, 'parts': pt, 'epic': ep, 'villages': vl};
  }
}

// ── Main ──────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await VoterDB.loadConfig();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kNavy, statusBarIconBrightness: Brightness.light));
  runApp(const VoterApp());
}

class VoterApp extends StatelessWidget {
  const VoterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kAppName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: kBlue,
      scaffoldBackgroundColor: kBg),
    home: const SplashScreen(),
  );
}

// ── Splash ────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashState();
}
class _SplashState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double>   _f;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _f = CurvedAnimation(parent: _c, curve: Curves.easeIn);
    _c.forward();
    Future.delayed(const Duration(seconds: 2), _go);
  }
  Future<void> _go() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final accepted = prefs.getBool('ok') ?? false;
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => accepted ? const HomePage() : const DisclaimerPage()));
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kNavy,
    body: FadeTransition(opacity: _f, child: Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72,
        decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 38)),
      const SizedBox(height: 4),
      Container(width: 72, height: 2, color: kGold),
      const SizedBox(height: 20),
      Text(kAppName, style: const TextStyle(
        fontSize: 24, fontWeight: FontWeight.w500, color: Colors.white)),
      const SizedBox(height: 6),
      Text('AC-$kAcNumber | $kYear', style: const TextStyle(
        fontSize: 12, color: Colors.white38)),
      const SizedBox(height: 48),
      const SizedBox(width: 24, height: 24,
        child: CircularProgressIndicator(color: kGold, strokeWidth: 2)),
    ]))),
  );
}

// ── Disclaimer ────────────────────────────────────────────────
class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 22)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kAppName, style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w500, color: kNavy)),
            Text('AC-$kAcNumber | SIR $kYear',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
        ]),
        const SizedBox(height: 20),
        Expanded(child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder)),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.info_outline_rounded, color: kGold, size: 20),
              const SizedBox(width: 8),
              const Text('Important / ముఖ్యమైన సమాచారం',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
            ]),
            const SizedBox(height: 14),
            _pt('ఈ యాప్ $kYear SIR ఓటర్ల జాబితాను చూపిస్తుంది — $kConstName AC-$kAcNumber.'),
            _pt('This app displays the $kYear Special Intensive Revision (SIR) voter list for $kConstName AC-$kAcNumber.'),
            _pt('ముఖ్యమైన హెచ్చరిక: ఈ యాప్‌లో చూపించే సమాచారాన్ని తప్పనిసరిగా అసలు భారత ఎన్నికల సంఘం (ECI) జాబితాతో సరిపోల్చి ధృవీకరించుకోండి.'),
            _pt('Important: Always cross-verify this information with the official Election Commission of India (ECI) electoral roll before use.'),
            _pt('ఈ యాప్ కేవలం సహాయం కోసం మాత్రమే. వ్యక్తిగత సమాచార లోపాలకు యాప్ డెవలపర్లు బాధ్యులు కారు.'),
            _pt('This app is for reference purposes only. The developers are not accountable for any individual data discrepancies or errors.'),
            _pt('అధికారిక సమాచారం కోసం: voters.eci.gov.in'),
          ])))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kNavy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('I Understand / అర్థమైంది',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('ok', true);
              if (!context.mounted) return;
              Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const HomePage()));
            })),
      ]),
    )),
  );
  Widget _pt(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.circle, size: 5, color: kGold),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5))),
    ]));
}

// ── Home ──────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomeState();
}
class _HomeState extends State<HomePage> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  List<Map<String, dynamic>> _results  = [];
  bool   _searching  = false;
  bool   _searched   = false;
  Map<String, dynamic> _stats = {};
  List<String>         _villages = [];
  List<Map<String, dynamic>> _allParts = [];
  String?  _village;
  Set<int> _parts = {};

  @override void initState() {
    super.initState();
    VoterDB.getStats().then((s) { if (mounted) setState(() => _stats = s); });
    VoterDB.getVillages().then((v) { if (mounted) setState(() => _villages = v); });
    VoterDB.getParts().then((p) { if (mounted) setState(() => _allParts = p); });
  }
  @override void dispose() {
    _debounce?.cancel(); _ctrl.dispose(); _focus.dispose(); super.dispose();
  }

  void _onChange(String v) {
    setState(() {});
    if (v.trim().isEmpty) { setState(() { _results = []; _searched = false; }); return; }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (v.trim().length >= 2) _search(v);
    });
  }

  Future<void> _search(String q) async {
    q = q.trim(); if (q.isEmpty) return;
    setState(() { _searching = true; _searched = true; });
    final r = await VoterDB.search(q,
      parts: _parts.isEmpty ? null : _parts.toList(),
      village: _village);
    if (mounted) setState(() { _results = r; _searching = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: Column(children: [
      _header(),
      Expanded(child: _searched ? _resultsList() : _home()),
    ]),
  );

  Widget _header() => Container(
    color: kNavy,
    child: SafeArea(bottom: false, child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kAppName, style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white)),
            Text('శాసనసభ నియోజకవర్గం $kAcNumber | ఓటర్ల జాబితా $kYear',
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ])),
          GestureDetector(
            onTap: _showInfo,
            child: Container(width: 32, height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.info_outline, color: Colors.white54, size: 16))),
        ]),
      ),
      Container(height: 0.5, color: kGold),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: TextField(
            controller: _ctrl, focusNode: _focus,
            onChanged: _onChange, onSubmitted: _search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'పేరు / ఇల్లు నం. / EPIC నంబర్ వెతకండి...',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
              prefixIcon: _searching
                ? const Padding(padding: EdgeInsets.all(11),
                    child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBlue)))
                : const Icon(Icons.search, color: Colors.grey, size: 20),
              suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                    onPressed: () { _ctrl.clear();
                      setState(() { _results = []; _searched = false; }); })
                : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          Expanded(child: _dropBtn(
            label: _village ?? 'అన్ని గ్రామాలు', onTap: _showVillages)),
          const SizedBox(width: 10),
          Expanded(child: _dropBtn(
            label: _parts.isEmpty ? 'అన్ని భాగాలు' : '${_parts.length} భాగాలు',
            onTap: _showParts)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            _searched
              ? '${_results.length}${_results.length == 300 ? '+' : ''} ఫలితాలు'
              : _stats.isNotEmpty
                ? '${_stats['total']} ఓటర్లు | ${_stats['villages']} గ్రామాలు'
                : '',
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
          if (_searched && !_searching)
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: kGold,
                borderRadius: BorderRadius.circular(4)),
              child: const Text('LIVE', style: TextStyle(
                fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600))),
        ]),
      ),
    ])),
  );

  Widget _dropBtn({required String label, required VoidCallback onTap}) =>
    GestureDetector(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.15))),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(
            fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis)),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 16),
        ]),
      ));

  Widget _home() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      if (_stats.isNotEmpty) ...[
        Row(children: [
          _stat('మొత్తం', _stats['total'].toString(), Icons.people_outline, kBlue),
          const SizedBox(width: 10),
          _stat('భాగాలు', _stats['parts'].toString(), Icons.location_on_outlined, kGold),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _stat('పురుషులు', _stats['male'].toString(), Icons.male, kMale),
          const SizedBox(width: 10),
          _stat('మహిళలు', _stats['female'].toString(), Icons.female, kFemale),
        ]),
        const SizedBox(height: 10),
        _wideStat('${_stats['epic']} మంది ఓటర్లకు EPIC కార్డులు ఉన్నాయి',
          Icons.badge_outlined, kGreen),
        const SizedBox(height: 20),
      ],
      Container(
        decoration: BoxDecoration(color: kCard,
          borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(children: [
          _tip(Icons.person_search_outlined, kBlue, 'పేరుతో వెతకండి',
            'తెలుగు లేదా ఇంగ్లీష్ లో పేరు టైప్ చేయండి'),
          _div(),
          _tip(Icons.home_outlined, kGold, 'ఇల్లు నంబర్తో వెతకండి',
            'ఉదా: 7-2/3 లేదా 1-42 అని టైప్ చేయండి'),
          _div(),
          _tip(Icons.badge_outlined, kGreen, 'EPIC నంబర్తో వెతకండి',
            'EPIC నంబర్ AP261810... అని టైప్ చేయండి'),
          _div(),
          _tip(Icons.people_outlined, kMale, 'తండ్రి / భర్త పేరుతో కూడా వెతకవచ్చు',
            'Relation name search also works'),
        ]),
      ),
    ]),
  );

  Widget _stat(String label, String val, IconData icon, Color color) =>
    Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kCard,
        borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ]),
      ]),
    ));

  Widget _wideStat(String text, IconData icon, Color color) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: kCard,
      borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500, color: color))),
    ]));

  Widget _tip(IconData icon, Color color, String title, String sub) =>
    Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      Container(padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ])),
    ]));

  Widget _div() => Divider(height: 1, color: kBorder);

  Widget _resultsList() {
    if (_searching) return const Center(
      child: Padding(padding: EdgeInsets.only(top: 60),
        child: CircularProgressIndicator(color: kBlue)));
    if (_results.isEmpty) return Center(child: Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off, size: 56, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('ఫలితాలు లేవు', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
        const SizedBox(height: 4),
        Text('వేరే పదం ప్రయత్నించండి',
          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      ])));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _results.length,
      itemBuilder: (ctx, i) => _VoterCard(
        data: _results[i],
        onTap: () => _showDetail(_results[i])));
  }

  void _showDetail(Map<String, dynamic> data) => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailSheet(data: data));

  void _showVillages() => showModalBottomSheet(
    context: context, backgroundColor: Colors.white, isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, maxChildSize: 0.9,
      builder: (_, sc) => Column(children: [
        _sheetHandle(),
        ListTile(
          title: const Text('అన్ని గ్రామాలు / All villages',
            style: TextStyle(fontWeight: FontWeight.w500)),
          onTap: () {
            setState(() { _village = null; _parts.clear(); });
            Navigator.pop(context);
            if (_ctrl.text.trim().isNotEmpty) _search(_ctrl.text);
          }),
        const Divider(height: 1),
        Expanded(child: ListView.builder(
          controller: sc, itemCount: _villages.length,
          itemBuilder: (_, i) {
            final v = _villages[i];
            return ListTile(
              title: Text(v),
              selected: _village == v,
              selectedColor: kBlue,
              trailing: _village == v
                ? const Icon(Icons.check, color: kBlue, size: 18) : null,
              onTap: () async {
                final pts = await VoterDB.getParts(village: v);
                if (!context.mounted) return;
                setState(() {
                  _village = v;
                  _parts = pts.map((p) => p['part'] as int).toSet();
                });
                Navigator.pop(context);
                if (_ctrl.text.trim().isNotEmpty) _search(_ctrl.text);
              });
          })),
      ])));

  void _showParts() => showModalBottomSheet(
    context: context, backgroundColor: Colors.white, isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _PartsSheet(
      allParts: _village != null
        ? _allParts.where((p) => _parts.contains(p['part'])).toList()
        : _allParts,
      selected: Set.from(_parts),
      onApply: (s) {
        setState(() { _parts = s; _village = null; });
        if (_ctrl.text.trim().isNotEmpty) _search(_ctrl.text);
      }));

  void _showInfo() => showDialog(context: context, builder: (_) => AlertDialog(
    title: Text(kAppName),
    content: Text('$kConstName నియోజకవర్గం AC-$kAcNumber\nSIR $kYear ఓటర్ల జాబితా\n\nమొత్తం: ${_stats['total']} ఓటర్లు | భాగాలు: ${_stats['parts']}'),
    actions: [TextButton(onPressed: () => Navigator.pop(context),
      child: const Text('సరే'))],
  ));

  Widget _sheetHandle() => Container(
    margin: const EdgeInsets.symmetric(vertical: 8), width: 36, height: 4,
    decoration: BoxDecoration(color: Colors.grey[300],
      borderRadius: BorderRadius.circular(2)));
}

// ── Voter Card ────────────────────────────────────────────────
class _VoterCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _VoterCard({required this.data, required this.onTap});

  bool   get _male => (data['gender'] as String? ?? '') != 'స్త్రీ';
  String get _name {
    final t = (data['name'] as String? ?? '').trim();
    return t.isNotEmpty ? t : capitalize(data['name_key'] as String? ?? '');
  }
  String get _relName {
    final t = (data['rel_name'] as String? ?? '').trim();
    return t.isNotEmpty ? t : capitalize(data['rel_key'] as String? ?? '');
  }
  String get _rel     => (data['rel'] as String? ?? '').trim();
  String get _house {
    final h = (data['house'] as String? ?? '').trim();
    return (h == '----' || h.isEmpty) ? '-' : h;
  }
  String get _village => (data['village_name'] as String? ?? '').trim();
  String get _age     => data['age']?.toString()    ?? '-';
  String get _part    => data['part']?.toString()   ?? '-';
  String get _page    => data['page']?.toString()   ?? '-';
  String get _serial  => data['serial']?.toString() ?? '-';
  String get _epic    => (data['epic'] as String?   ?? '').trim();
  bool   get _hasEpic => isValidEpic(_epic);

  @override
  Widget build(BuildContext context) {
    final gc = _male ? kMale : kFemale;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Left badge - serial, part, page
            Column(children: [
              Container(width: 52, height: 52,
                decoration: BoxDecoration(
                  color: kBlue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_serial, style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w500, color: kBlue)),
                  Text('భా.$_part', style: TextStyle(
                    fontSize: 9, color: Colors.grey[500])),
                ])),
              const SizedBox(height: 2),
              // FIX: Show పే. (Telugu) with correct page number
              Text('పే.$_page', style: TextStyle(fontSize: 9, color: Colors.grey[400])),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_name.isEmpty ? '-' : _name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: gc.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: gc.withOpacity(0.25))),
                  child: Text(_male ? 'పు' : 'స్త్రీ',
                    style: TextStyle(fontSize: 10, color: gc, fontWeight: FontWeight.w500))),
              ]),
              // FIX: Show relation label properly in Telugu
              if (_relName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('${relLabel(_rel)}: $_relName',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _tag(Icons.home_outlined, _house),
                if (_village.isNotEmpty) _tag(Icons.location_on_outlined, _village),
                _tag(Icons.cake_outlined, 'వయసు $_age'),
              ]),
              const SizedBox(height: 5),
              if (_epic.isNotEmpty && _epic != '00000000000000')
                Row(children: [
                  Container(width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: _hasEpic ? kBlue : Colors.grey[400],
                      borderRadius: BorderRadius.circular(3)),
                    child: const Icon(Icons.credit_card, color: Colors.white, size: 10)),
                  const SizedBox(width: 5),
                  Text(_epic, style: TextStyle(
                    fontSize: 10,
                    color: _hasEpic ? kBlue : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace')),
                ])
              else
                Text('EPIC: జారీ కాలేదు (2002)',
                  style: TextStyle(fontSize: 10, color: Colors.grey[400])),
            ])),
            GestureDetector(
              onTap: _share,
              child: Padding(padding: const EdgeInsets.only(left: 4),
                child: const Icon(Icons.send_rounded, size: 18, color: kGreen))),
          ]),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(4),
      border: Border.all(color: kBorder)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: Colors.grey[500]),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
    ]));

  void _share() {
    final rel  = _relName.isNotEmpty ? '${relLabelEn(_rel)}: $_relName\n' : '';
    final epic = _hasEpic ? 'EPIC: $_epic\n' : '';
    Share.share(
      '$kConstName SIR $kYear\n'
      'పేరు: $_name\n'
      '${rel}'
      'గ్రామం: $_village\n'
      'ఇల్లు: $_house | వయసు: $_age | ${_male ? "పురుషుడు" : "స్త్రీ"}\n'
      'భాగం: $_part | పుట: $_page | వరుస: $_serial\n'
      '${epic}');
  }
}

// ── Detail Sheet ──────────────────────────────────────────────
class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DetailSheet({required this.data});

  bool   get _male => (data['gender'] as String? ?? '') != 'స్త్రీ';
  String get _name {
    final t = (data['name'] as String? ?? '').trim();
    return t.isNotEmpty ? t : capitalize(data['name_key'] as String? ?? '');
  }
  String get _relName {
    final t = (data['rel_name'] as String? ?? '').trim();
    return t.isNotEmpty ? t : capitalize(data['rel_key'] as String? ?? '');
  }
  String get _rel     => (data['rel'] as String? ?? '').trim();
  String get _village => (data['village_name'] as String? ?? '').trim();
  String get _house {
    final h = (data['house'] as String? ?? '').trim();
    return (h == '----' || h.isEmpty) ? '-' : h;
  }
  String get _age    => data['age']?.toString()    ?? '-';
  String get _part   => data['part']?.toString()   ?? '-';
  String get _page   => data['page']?.toString()   ?? '-';
  String get _serial => data['serial']?.toString() ?? '-';
  String get _epic   => (data['epic'] as String?   ?? '').trim();
  bool   get _hasEpic => isValidEpic(_epic);

  @override
  Widget build(BuildContext context) {
    final gc = _male ? kMale : kFemale;
    return Container(
      decoration: const BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                color: gc.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(_male ? Icons.person : Icons.person_2,
                color: gc, size: 26)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.isEmpty ? '-' : _name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Text('భాగం $_part | పుట $_page | వరుస $_serial',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ])),
            GestureDetector(onTap: _copy,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: kBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder)),
                child: const Row(children: [
                  Icon(Icons.copy_outlined, size: 14, color: kBlue),
                  SizedBox(width: 4),
                  Text('కాపీ', style: TextStyle(fontSize: 12, color: kBlue)),
                ]))),
            const SizedBox(width: 8),
            GestureDetector(onTap: _share,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kGreen.withOpacity(0.2))),
                child: const Row(children: [
                  Icon(Icons.send_rounded, size: 14, color: kGreen),
                  SizedBox(width: 4),
                  Text('పంపు', style: TextStyle(fontSize: 12, color: kGreen)),
                ]))),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.of(context).padding.bottom + 16),
          child: Column(children: [
            _row('గ్రామం', 'Village', _village.isNotEmpty ? _village : '-'),
            _row('ఇంటి నంబరు', 'House No', _house),
            if (_relName.isNotEmpty)
              _row(relLabel(_rel), relLabelEn(_rel), _relName),
            _row('లింగం', 'Gender', _male ? 'పురుషుడు / M' : 'స్త్రీ / F'),
            _row('వయసు', 'Age ($kYear)', _age),
            _row('ఓటరు కార్డు', 'EPIC',
              (_epic.isNotEmpty && _epic != '00000000000000')
                ? _epic : 'జారీ కాలేదు / Not issued'),
            _row('పుట', 'Page', _page),
            _row('భాగం', 'Part', _part),
            _row('వరుస సంఖ్య', 'Serial No', _serial),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String tel, String en, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      SizedBox(width: 130, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        Text(en, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ])),
      Expanded(child: Text(val,
        style: const TextStyle(fontSize: 13),
        textAlign: TextAlign.right)),
    ]));

  void _copy() {
    Clipboard.setData(ClipboardData(text:
      '$_name | గ్రామం: $_village | ఇల్లు: $_house | వయసు: $_age | '
      'భాగం: $_part | పుట: $_page | వరుస: $_serial | EPIC: $_epic'));
  }

  void _share() {
    final rel  = _relName.isNotEmpty ? '${relLabelEn(_rel)}: $_relName\n' : '';
    final epic = _hasEpic ? 'EPIC: $_epic\n' : '';
    Share.share(
      '$kConstName SIR $kYear\n'
      'పేరు: $_name\n'
      '${rel}'
      'గ్రామం: $_village\n'
      'ఇల్లు: $_house | వయసు: $_age | ${_male ? "పురుషుడు" : "స్త్రీ"}\n'
      'భాగం: $_part | పుట: $_page | వరుస: $_serial\n'
      '${epic}');
  }
}

// ── Parts Sheet ───────────────────────────────────────────────
class _PartsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> allParts;
  final Set<int>                   selected;
  final void Function(Set<int>)    onApply;
  const _PartsSheet({required this.allParts, required this.selected, required this.onApply});
  @override State<_PartsSheet> createState() => _PartsSheetState();
}
class _PartsSheetState extends State<_PartsSheet> {
  late Set<int> _sel;
  @override void initState() { super.initState(); _sel = Set.from(widget.selected); }
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false, initialChildSize: 0.7, maxChildSize: 0.92,
    builder: (_, sc) => Container(
      decoration: const BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 8),
          width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            const Text('భాగం వారీగా ఫిల్టర్',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _sel.clear()),
              child: const Text('Clear All')),
          ])),
        const Divider(height: 1),
        Expanded(child: ListView.builder(
          controller: sc, itemCount: widget.allParts.length,
          itemBuilder: (_, i) {
            final part = widget.allParts[i];
            final num  = part['part'] as int;
            final tot  = part['total'] as int? ?? 0;
            final vil  = part['village'] as String? ?? '';
            return CheckboxListTile(
              value: _sel.contains(num),
              onChanged: (v) => setState(() =>
                v == true ? _sel.add(num) : _sel.remove(num)),
              title: Text('భాగం $num',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
              subtitle: Text('$vil | $tot ఓటర్లు',
                style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              activeColor: kBlue, dense: true);
          })),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16,
            MediaQuery.of(context).padding.bottom + 8),
          child: SizedBox(width: double.infinity, height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kNavy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () { widget.onApply(_sel); Navigator.pop(context); },
              child: Text(_sel.isEmpty ? 'అన్నీ చూపించు'
                : 'Apply (${_sel.length} parts)',
                style: const TextStyle(fontWeight: FontWeight.w500))))),
      ]),
    ));
}