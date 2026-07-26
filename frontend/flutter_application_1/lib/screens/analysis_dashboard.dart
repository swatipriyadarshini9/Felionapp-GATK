import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_service.dart';
import '../config/supabase_config.dart';
import '../services/analysis_repository.dart';
import '../services/auth_service.dart';
import '../services/local_auth_store.dart';
import '../widgets/circos_plot.dart';
import 'login_page.dart';
import 'painters.dart';

class AnalysisDashboard extends StatefulWidget {
  const AnalysisDashboard({super.key});

  @override
  State<AnalysisDashboard> createState() => _AnalysisDashboardState();
}

class _AnalysisDashboardState extends State<AnalysisDashboard> {
  final ApiService _api = ApiService();
  final AnalysisRepository _repo = AnalysisRepository();
  final AuthService _auth = AuthService();

  bool _isAnalyzing = false;
  bool _hasResults = false;
  String _aiSummary = '';
  List<dynamic> _variants = [];

  Future<void> _persist({
    required String uploadId,
    required String summary,
    required List<dynamic> variants,
  }) async {
    try {
      await _repo.saveAnalysis(
        uploadId: uploadId,
        drugName: 'Clopidogrel',
        aiSummary: summary,
        variants: variants,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved locally; cloud sync failed: $e'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  Future<void> _handleFileUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bam', 'sam', 'vcf'],
      withData: true,
    );

    if (result == null || result.files.first.bytes == null) return;

    final file = result.files.first;
    setState(() => _isAnalyzing = true);

    try {
      final response = await _api.analyzeVariantFile(file);
      final variants = response['variants'] as List<dynamic>? ?? [];
      final rawSummary = response['ai_summary']?.toString() ?? '';
      final cleanedSummary = _scrubSummary(rawSummary);

      setState(() {
        _variants = variants;
        _aiSummary = cleanedSummary;
        _hasResults = true;
        _isAnalyzing = false;
      });

      await _persist(
        uploadId: 'upload_${DateTime.now().millisecondsSinceEpoch}',
        summary: cleanedSummary,
        variants: variants,
      );
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pipeline Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _loadDemoVariants() async {
    setState(() => _isAnalyzing = true);

    // Prefer live backend curated chr10 panel when API is up.
    try {
      final healthy = await _api.ping();
      if (healthy) {
        final bytes = Uint8List.fromList(_embeddedChr10Vcf());
        final demoFile = PlatformFile(
          name: 'chr10_cyp2c19_demo.vcf',
          size: bytes.length,
          bytes: bytes,
        );
        final response = await _api.analyzeVariantFile(demoFile);
        final variants = response['variants'] as List<dynamic>? ?? [];
        final summary = _scrubSummary(response['ai_summary']?.toString() ?? '');
        setState(() {
          _variants = variants;
          _aiSummary = summary;
          _hasResults = true;
          _isAnalyzing = false;
        });
        await _persist(
          uploadId: 'demo_${DateTime.now().millisecondsSinceEpoch}',
          summary: summary,
          variants: variants,
        );
        return;
      }
    } catch (_) {
      // Fall through to local curated panel.
    }

    final demo = _demoVariants();
    const summary =
        'Chromosome 10 pharmacogenomic review for Clopidogrel. '
        'rs4244285 (CYP2C19*2) and rs12248560 (CYP2C19*17) are highlighted on chr10. '
        'Loss-of-function alleles can reduce clopidogrel bioactivation; *17 may increase activity. '
        'Start the Felino backend on port 8000 for live /analyze responses.';

    setState(() {
      _variants = demo;
      _aiSummary = summary;
      _hasResults = true;
      _isAnalyzing = false;
    });

    await _persist(
      uploadId: 'demo_${DateTime.now().millisecondsSinceEpoch}',
      summary: summary,
      variants: demo,
    );
  }

  List<int> _embeddedChr10Vcf() {
    const vcf = '''##fileformat=VCFv4.2
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	SAMPLE
10	96522463	rs4244285	G	A	99.0	PASS	.	GT	0/1
10	96521657	rs4986893	G	A	88.5	PASS	.	GT	0/0
10	96535173	rs12248560	C	T	92.1	PASS	.	GT	0/1
10	96522472	rs72552267	C	T	75.0	PASS	.	GT	0/0
10	96541616	rs1057910	A	C	85.4	PASS	.	GT	0/1
''';
    return utf8.encode(vcf);
  }

  List<Map<String, dynamic>> _demoVariants() {
    return const [
      {
        'variant_id': 'rs4244285',
        'chromosome': '10',
        'position': 96522463,
        'genotype': '0/1',
        'qual': 99.0,
      },
      {
        'variant_id': 'rs4986893',
        'chromosome': '10',
        'position': 96521657,
        'genotype': '0/0',
        'qual': 88.5,
      },
      {
        'variant_id': 'rs12248560',
        'chromosome': '10',
        'position': 96535173,
        'genotype': '0/1',
        'qual': 92.1,
      },
      {
        'variant_id': 'rs72552267',
        'chromosome': '10',
        'position': 96522472,
        'genotype': '0/0',
        'qual': 75.0,
      },
      {
        'variant_id': 'rs1057910',
        'chromosome': '10',
        'position': 96541616,
        'genotype': '0/1',
        'qual': 85.4,
      },
    ];
  }

  String _scrubSummary(String raw) {
    return raw
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll(RegExp(r'#+'), '')
        .replaceAll(RegExp(r'-\s'), '• ')
        .split('\n')
        .map((line) => line.trim())
        .join('\n')
        .trim();
  }

  Future<void> _signOut() async {
    if (!SupabaseConfig.isConfigured) {
      await LocalAuthStore.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginPage(configMissing: true),
          ),
          (_) => false,
        );
      }
      return;
    }
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'WORKSTATION // FELINO',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _hasResults ? _buildResultsLayout() : _buildUploadState(),
      ),
    );
  }

  Widget _buildUploadState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.biotech_outlined, size: 80, color: Colors.blue.shade100),
          const SizedBox(height: 20),
          const Text(
            'No Active Genomic Sample',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'CHR10 // CYP2C19 workstation — upload VCF or BAM',
            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 30),
          if (_isAnalyzing)
            const CircularProgressIndicator()
          else ...[
            ElevatedButton.icon(
              onPressed: _handleFileUpload,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('UPLOAD GENOMIC DATA'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadDemoVariants,
              icon: const Icon(Icons.bubble_chart_outlined),
              label: const Text('LOAD DEMO VARIANTS'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsLayout() {
    final isWide = MediaQuery.sizeOf(context).width > 700;

    final visualColumn = Column(
      children: [
        CircosPlot(variants: _variants),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: GATKChartPainter()),
                ),
                const Positioned(
                  top: 10,
                  left: 12,
                  child: Text(
                    'GATK // READ DEPTH',
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildGeminiCard()),
      ],
    );

    if (!isWide) {
      return Column(
        children: [
          CircosPlot(variants: _variants, height: 260),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _hasResults = false;
                _variants = [];
                _aiSummary = '';
              }),
              child: const Text('New analysis'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _buildGeminiCard(fixedHeight: false),
                const SizedBox(height: 12),
                ..._variantCards(),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: visualColumn),
        const SizedBox(width: 24),
        Expanded(flex: 3, child: _buildVariantTable()),
      ],
    );
  }

  Widget _buildGeminiCard({bool fixedHeight = true}) {
    final child = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Text(
          _aiSummary,
          textAlign: TextAlign.justify,
          style: const TextStyle(fontSize: 14, color: Colors.black, height: 1.6),
        ),
      ),
    );
    return fixedHeight ? child : child;
  }

  Widget _buildVariantTable() {
    return ListView(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() {
              _hasResults = false;
              _variants = [];
              _aiSummary = '';
            }),
            child: const Text('New analysis'),
          ),
        ),
        ..._variantCards(),
      ],
    );
  }

  List<Widget> _variantCards() {
    return List.generate(_variants.length, (index) {
      final v = _variants[index] as Map;
      final chrom = v['chromosome']?.toString() ?? '';
      final id = v['variant_id']?.toString() ?? '';
      final isAlarming = chrom.contains('10') &&
          (id.contains('rs4244285') ||
              id.contains('rs12248560') ||
              id.contains('rs4986893') ||
              (v['genotype']?.toString().contains('1') ?? false));
      final color = isAlarming ? Colors.red : Colors.green;
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
        child: ListTile(
          title: Text(
            '$id  ·  POS ${v['position']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('chr$chrom | GT: ${v['genotype']} | QUAL: ${v['qual']}'),
          trailing: Text(
            isAlarming ? 'ACTIONABLE' : 'REF',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      );
    });
  }
}
