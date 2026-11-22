/// Classification of user query intent.
enum UserIntent {
  /// Query targeting personal on-device memories (screen time, calls, transactions, documents).
  personalMemory('Personal Memory'),

  /// Query requiring live web/world knowledge (news, scores, weather, general facts).
  liveWebWorld('Live Web'),

  /// Query combining personal context with live web search (e.g. flight ticket + destination weather).
  hybrid('Hybrid (Personal + Web)');

  final String label;
  const UserIntent(this.label);
}

/// Zero-latency, deterministic Intent Classifier for user queries.
class IntentRouterService {
  // Strong indicators of personal data lookup
  static final List<String> _personalEntities = [
    'screen time',
    'app usage',
    'spent',
    'spending',
    'expense',
    'expenses',
    'transaction',
    'transactions',
    'bank',
    'debit',
    'credit',
    'upi',
    'call',
    'calls',
    'called',
    'who called',
    'missed call',
    'passport',
    'receipt',
    'invoice',
    'ticket',
    'booking',
    'pnr',
    'aadhaar',
    'pan card',
    'my bill',
    'my note',
    'did i pay',
    'who did i',
    'how much did i',
  ];

  // External / Web indicators
  static final List<String> _externalActions = [
    'weather',
    'forecast',
    'return policy',
    'policy',
    'compare',
    'average',
    'news',
    'score',
    'scores',
    'match',
    'game',
    'who won',
    'stock price',
    'bitcoin',
    'crypto',
    'online',
    'wikipedia',
    'reviews',
    'customer support',
    'headquarters',
  ];

  /// Classifies a query into [UserIntent.personalMemory], [UserIntent.liveWebWorld], or [UserIntent.hybrid].
  UserIntent classify(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) {
      return UserIntent.personalMemory;
    }

    final hasPersonalEntity = _personalEntities.any((e) => lower.contains(e));
    final hasPersonalPronoun =
        RegExp(r'\b(my|me|i|i\x27m|i\x27ve)\b').hasMatch(lower);
    final hasExternalAction = _externalActions.any((a) => lower.contains(a));

    // 1. Hybrid detection: Personal entity/pronoun combined with an external web action
    // E.g.: "I bought shoes from Nike, what is their return policy online?"
    // E.g.: "Compare my screen time with average daily smartphone usage"
    // E.g.: "I have a flight ticket to Paris, what is the weather there right now?"
    if ((hasPersonalEntity || hasPersonalPronoun) && hasExternalAction) {
      return UserIntent.hybrid;
    }

    // 2. Personal Memory: Query has personal entities or asks about personal possessions
    // E.g.: "What is my passport number?", "How much did I spend yesterday?", "Who called me?"
    if (hasPersonalEntity || (hasPersonalPronoun && !hasExternalAction)) {
      return UserIntent.personalMemory;
    }

    // 3. Otherwise: External live web / world knowledge
    return UserIntent.liveWebWorld;
  }
}
