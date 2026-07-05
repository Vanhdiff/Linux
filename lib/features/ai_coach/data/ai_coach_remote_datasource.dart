import '../../../app/services/api/api_client.dart';
import '../../../app/services/api/api_exception.dart';
import '../../../app/services/backend/backend_process_service.dart';
import '../../../app/state/active_account_session.dart';

class AiCoachRemoteDataSource {
  final ApiClient _apiClient;
  final BackendProcessService _backend;

  AiCoachRemoteDataSource({
    ApiClient? apiClient,
    BackendProcessService? backend,
  }) : _apiClient = apiClient ?? ApiClient(),
       _backend = backend ?? BackendProcessService();

  Future<AiCoachView> fetchReview({
    String period = 'day',
    String language = 'en',
  }) async {
    await _backend.ensureRunning();
    try {
      return await _fetchReview(period: period, language: language);
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      await _backend.restart();
      return _fetchReview(period: period, language: language);
    }
  }

  Future<AiCoachView> _fetchReview({
    required String period,
    required String language,
  }) async {
    final path = switch (period) {
      'week' => '/api/ai/weekly-review',
      'month' => '/api/ai/monthly-review',
      _ => '/api/ai/daily-review',
    };
    final response =
        await _apiClient.postJson(
              path,
              {},
              queryParameters: {
                'account_id': '${ActiveAccountSession.accountId}',
                'language': language,
              },
            )
            as Map<String, dynamic>;
    return AiCoachView.fromJson(response);
  }

  Future<AiCoachChatResponse> sendChat({
    required String question,
    String language = 'en',
  }) async {
    await _backend.ensureRunning();
    final response =
        await _apiClient.postJson(
              '/api/ai/chat',
              {'question': question},
              queryParameters: {
                'account_id': '${ActiveAccountSession.accountId}',
                'language': language,
              },
            )
            as Map<String, dynamic>;
    return AiCoachChatResponse.fromJson(response);
  }

  void close() {
    _apiClient.close();
    _backend.close();
  }
}

class AiCoachView {
  final AiCoachContext context;
  final AiCoachReview review;

  const AiCoachView({required this.context, required this.review});

  factory AiCoachView.fromJson(Map<String, dynamic> json) {
    return AiCoachView(
      context: AiCoachContext.fromJson(
        json['context'] as Map<String, dynamic>? ?? const {},
      ),
      review: AiCoachReview.fromJson(
        json['review'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  factory AiCoachView.empty() {
    return AiCoachView(
      context: AiCoachContext.empty(),
      review: AiCoachReview.empty(),
    );
  }
}

class AiCoachContext {
  final String period;
  final String startDate;
  final String endDate;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> guardrails;
  final List<Map<String, dynamic>> mistakes;
  final List<Map<String, dynamic>> symbols;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> ruleBreaks;
  final List<Map<String, dynamic>> topLosses;
  final List<Map<String, dynamic>> economicEvents;

  const AiCoachContext({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.summary,
    required this.guardrails,
    required this.mistakes,
    required this.symbols,
    required this.sessions,
    required this.ruleBreaks,
    required this.topLosses,
    required this.economicEvents,
  });

  factory AiCoachContext.fromJson(Map<String, dynamic> json) {
    return AiCoachContext(
      period: json['period'] as String? ?? 'day',
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      summary: Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      guardrails: Map<String, dynamic>.from(
        json['guardrails'] as Map? ?? const {},
      ),
      mistakes: _listOfMaps(json['mistakes']),
      symbols: _listOfMaps(json['symbols']),
      sessions: _listOfMaps(json['sessions']),
      ruleBreaks: _listOfMaps(json['rule_breaks']),
      topLosses: _listOfMaps(json['top_losses']),
      economicEvents: _listOfMaps(json['economic_events']),
    );
  }

  factory AiCoachContext.empty() {
    return const AiCoachContext(
      period: 'day',
      startDate: '',
      endDate: '',
      summary: {},
      guardrails: {},
      mistakes: [],
      symbols: [],
      sessions: [],
      ruleBreaks: [],
      topLosses: [],
      economicEvents: [],
    );
  }
}

class AiCoachReview {
  final String headline;
  final String riskLevel;
  final List<String> keyFindings;
  final List<String> advice;
  final Map<String, dynamic> nextSessionPlan;

  const AiCoachReview({
    required this.headline,
    required this.riskLevel,
    required this.keyFindings,
    required this.advice,
    required this.nextSessionPlan,
  });

  factory AiCoachReview.fromJson(Map<String, dynamic> json) {
    return AiCoachReview(
      headline: json['headline'] as String? ?? 'No coach review yet',
      riskLevel: json['risk_level'] as String? ?? 'neutral',
      keyFindings: _stringList(json['key_findings']),
      advice: _stringList(json['advice']),
      nextSessionPlan: Map<String, dynamic>.from(
        json['next_session_plan'] as Map? ?? const {},
      ),
    );
  }

  factory AiCoachReview.empty() {
    return const AiCoachReview(
      headline: 'No coach review yet',
      riskLevel: 'neutral',
      keyFindings: [],
      advice: [],
      nextSessionPlan: {},
    );
  }
}

class AiCoachChatResponse {
  final String answer;
  final int remaining;
  final int limit;
  final String source;

  const AiCoachChatResponse({
    required this.answer,
    required this.remaining,
    required this.limit,
    required this.source,
  });

  factory AiCoachChatResponse.fromJson(Map<String, dynamic> json) {
    return AiCoachChatResponse(
      answer: json['answer'] as String? ?? '',
      remaining: _intValue(json['remaining']),
      limit: _intValue(json['limit']),
      source: json['source'] as String? ?? 'local',
    );
  }
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => '$item')
      .toList(growable: false);
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
