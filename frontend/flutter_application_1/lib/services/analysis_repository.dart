import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AnalysisRepository {
  AnalysisRepository({SupabaseClient? client}) : _overrideClient = client;

  final SupabaseClient? _overrideClient;

  SupabaseClient? get _clientOrNull {
    if (_overrideClient != null) return _overrideClient;
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  /// Persists an analysis + variants under RLS (user JWT).
  /// Returns the new analysis id, or null if not authenticated / not configured.
  Future<String?> saveAnalysis({
    required String uploadId,
    required String drugName,
    required String aiSummary,
    required List<dynamic> variants,
  }) async {
    final client = _clientOrNull;
    if (client == null) return null;

    final user = client.auth.currentUser;
    if (user == null) return null;

    final analysisInsert = await client
        .from('analyses')
        .insert({
          'user_id': user.id,
          'upload_id': uploadId,
          'drug_name': drugName,
          'ai_summary': aiSummary,
          'status': 'completed',
        })
        .select('id')
        .single();

    final analysisId = analysisInsert['id'] as String;

    if (variants.isNotEmpty) {
      final rows = variants.map((v) {
        final map = Map<String, dynamic>.from(v as Map);
        return {
          'analysis_id': analysisId,
          'chromosome': map['chromosome']?.toString(),
          'position': map['position'] is int
              ? map['position']
              : int.tryParse('${map['position']}'),
          'variant_id': map['variant_id']?.toString(),
          'genotype': map['genotype']?.toString(),
          'qual': map['qual'] is num
              ? (map['qual'] as num).toDouble()
              : double.tryParse('${map['qual']}'),
        };
      }).toList();

      await client.from('variants').insert(rows);
    }

    return analysisId;
  }
}
