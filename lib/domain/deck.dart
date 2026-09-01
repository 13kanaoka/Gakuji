import 'package:gakuji/domain/term.dart';

enum DeckType {
  writing,
  reading,
  hybrid,
}

enum StudyMode {
  study,
  review,
}

/// Determines which card variants a term creates inside a hybrid deck.
///
/// Reading and writing decks ignore this setting because their card type is
/// already determined by [Deck.type].
enum HybridCardMode {
  reading,
  writing,
  both,
}

/// Converts a stored string back into a hybrid-card mode.
///
/// Existing hybrid terms that were saved before this feature was added default
/// to [HybridCardMode.both].
HybridCardMode hybridCardModeFromStorage(String? value) {
  switch (value) {
    case 'reading':
      return HybridCardMode.reading;
    case 'writing':
      return HybridCardMode.writing;
    case 'both':
    default:
      return HybridCardMode.both;
  }
}


class DeckAdapterCredit {
  final String uid;
  final String? username;

  const DeckAdapterCredit({
    required this.uid,
    this.username,
  });

  factory DeckAdapterCredit.fromJson(Map<String, dynamic> json) {
    final rawUsername = json['username']?.toString().trim();

    return DeckAdapterCredit(
      uid: json['uid']?.toString().trim() ?? '',
      username: rawUsername == null || rawUsername.isEmpty
          ? null
          : rawUsername,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      if (username != null && username!.trim().isNotEmpty)
        'username': username!.trim(),
    };
  }
}

/// Deck = container of copied deck-owned Terms.
class Deck {
  final String id;
  final String name;

  final DeckType type;

  /// Original creator attribution for shared/imported decks.
  ///
  /// Local decks created before attribution was added leave these null and are
  /// treated as belonging to the current user. Imported decks preserve the
  /// original creator so attribution survives independent copies and re-shares.
  final String? creatorUid;
  final String? creatorUsername;

  /// Ordered, de-duplicated attribution for users who published modified
  /// versions of a shared deck after the original creator.
  final List<DeckAdapterCredit> adaptedBy;

  /// Share code for the exact snapshot this local deck most recently matched.
  ///
  /// The code remains attached while the local deck is edited so the next
  /// share can compare [shareSnapshotHash] and decide whether to reuse the
  /// immutable snapshot or publish a new version.
  String? shareCode;

  /// Stable hash of the shareable deck content represented by [shareCode].
  String? shareSnapshotHash;

  /// Optional user-selected ARGB color for this deck.
  ///
  /// A null value means the UI should fall back to the deck type's original
  /// default color, which keeps decks saved before custom colors compatible.
  int? colorValue;

  /// Independent term/card copies saved to this deck.
  ///
  /// These are separate from the global dictionary terms.
  /// Each copied term should keep a sourceId that points back to the
  /// original dictionary term ID.
  final List<Term> terms;

  /// Card mode selected for each term in a hybrid deck.
  ///
  /// Keys are deck-owned [Term.id] values. A missing entry defaults to
  /// [HybridCardMode.both], which safely migrates hybrid decks created before
  /// per-term card modes existed.
  ///
  /// Reading and writing decks do not use this map.
  final Map<String, HybridCardMode> hybridCardModes;

  /// Whether this deck has entered the Review system.
  ///
  /// If false, the deck is only using normal Study behavior.
  /// If true, Review scheduling data can exist and continue aging
  /// even when the deck's active study mode is Study.
  bool reviewEnabled;

  /// The deck's currently active study experience.
  ///
  /// Study = free practice.
  /// Review = scheduled review.
  StudyMode activeStudyMode;

  /// When Review was first enabled for this deck.
  DateTime? reviewEnabledAt;

  /// Study progress tracking.
  int lastStudyIndex;

  /// Shuffle state per deck.
  bool isShuffled;

  Deck({
    required this.id,
    required this.name,
    required this.type,
    this.creatorUid,
    this.creatorUsername,
    List<DeckAdapterCredit>? adaptedBy,
    this.shareCode,
    this.shareSnapshotHash,
    this.colorValue,
    required this.terms,
    Map<String, HybridCardMode>? hybridCardModes,
    this.reviewEnabled = false,
    this.activeStudyMode = StudyMode.study,
    this.reviewEnabledAt,
    this.lastStudyIndex = 0,
    this.isShuffled = false,
  })  : adaptedBy = List<DeckAdapterCredit>.from(
          adaptedBy ?? const <DeckAdapterCredit>[],
        ),
        hybridCardModes = Map<String, HybridCardMode>.from(
          hybridCardModes ?? const {},
        );

  /// Returns the effective card mode for [term].
  ///
  /// Normal reading and writing decks always return their single fixed mode.
  /// Hybrid decks use the saved per-term choice and default older dictionary
  /// terms to both card types. User-authored custom terms are reading-only.
  HybridCardMode cardModeFor(Term term) {
    switch (type) {
      case DeckType.reading:
        return HybridCardMode.reading;
      case DeckType.writing:
        return HybridCardMode.writing;
      case DeckType.hybrid:
        if (term.isCustom) return HybridCardMode.reading;
        return hybridCardModes[term.id] ?? HybridCardMode.both;
    }
  }

  bool readingEnabledFor(Term term) {
    final mode = cardModeFor(term);

    return mode == HybridCardMode.reading || mode == HybridCardMode.both;
  }

  bool writingEnabledFor(Term term) {
    final mode = cardModeFor(term);

    return mode == HybridCardMode.writing || mode == HybridCardMode.both;
  }

  /// Sets the card mode for one term in a hybrid deck.
  ///
  /// The method intentionally does nothing for normal reading and writing
  /// decks so their behavior cannot accidentally be changed.
  void setHybridCardMode(
    Term term,
    HybridCardMode mode,
  ) {
    if (type != DeckType.hybrid) return;

    if (term.isCustom) {
      hybridCardModes[term.id] = HybridCardMode.reading;
      return;
    }

    hybridCardModes[term.id] = mode;
  }

  /// Removes stale mode data when a term is removed from a hybrid deck.
  void removeHybridCardMode(Term term) {
    hybridCardModes.remove(term.id);
  }

  /// Removes mode entries whose deck-owned term no longer exists.
  void cleanHybridCardModes() {
    final currentTermIds = terms.map((term) => term.id).toSet();

    hybridCardModes.removeWhere(
      (termId, mode) => !currentTermIds.contains(termId),
    );
  }

  /// Number of actual study cards generated by this deck.
  ///
  /// A hybrid term set to both contributes two cards.
  int get studyCardCount {
    switch (type) {
      case DeckType.reading:
      case DeckType.writing:
        return terms.length;
      case DeckType.hybrid:
        var count = 0;

        for (final term in terms) {
          final mode = cardModeFor(term);
          count += mode == HybridCardMode.both ? 2 : 1;
        }

        return count;
    }
  }

  /// Helpful copy method for updates + persistence.
  Deck copyWith({
    String? id,
    String? name,
    DeckType? type,
    String? creatorUid,
    String? creatorUsername,
    List<DeckAdapterCredit>? adaptedBy,
    String? shareCode,
    String? shareSnapshotHash,
    int? colorValue,
    List<Term>? terms,
    Map<String, HybridCardMode>? hybridCardModes,
    bool? reviewEnabled,
    StudyMode? activeStudyMode,
    DateTime? reviewEnabledAt,
    int? lastStudyIndex,
    bool? isShuffled,
  }) {
    return Deck(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      creatorUid: creatorUid ?? this.creatorUid,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      adaptedBy: adaptedBy ?? this.adaptedBy,
      shareCode: shareCode ?? this.shareCode,
      shareSnapshotHash: shareSnapshotHash ?? this.shareSnapshotHash,
      colorValue: colorValue ?? this.colorValue,
      terms: terms ?? this.terms,
      hybridCardModes: hybridCardModes ?? this.hybridCardModes,
      reviewEnabled: reviewEnabled ?? this.reviewEnabled,
      activeStudyMode: activeStudyMode ?? this.activeStudyMode,
      reviewEnabledAt: reviewEnabledAt ?? this.reviewEnabledAt,
      lastStudyIndex: lastStudyIndex ?? this.lastStudyIndex,
      isShuffled: isShuffled ?? this.isShuffled,
    );
  }

  /// Debug helper.
  @override
  String toString() {
    return 'Deck(id: $id, name: $name, type: $type, terms: ${terms.length}, studyCards: $studyCardCount, reviewEnabled: $reviewEnabled, activeStudyMode: $activeStudyMode, progress: $lastStudyIndex, shuffled: $isShuffled)';
  }
}
