import 'package:gakuji/models/term.dart';

class JapaneseConjugationForm {
  final String label;
  final String value;

  const JapaneseConjugationForm({
    required this.label,
    required this.value,
  });
}

enum _JapaneseInflectionClass {
  ichidan,
  godan,
  suru,
  kuru,
  iAdjective,
}

class JapaneseConjugationService {
  static List<JapaneseConjugationForm> formsForTerm(Term term) {
    final inflectionClass = _classForTerm(term);
    final spelling = _displaySpelling(term);

    if (inflectionClass == null || spelling.isEmpty) {
      return const [];
    }

    switch (inflectionClass) {
      case _JapaneseInflectionClass.ichidan:
        return _ichidanForms(spelling);
      case _JapaneseInflectionClass.godan:
        return _godanForms(spelling);
      case _JapaneseInflectionClass.suru:
        return _suruForms(spelling);
      case _JapaneseInflectionClass.kuru:
        return _kuruForms(spelling);
      case _JapaneseInflectionClass.iAdjective:
        return _iAdjectiveForms(spelling);
    }
  }

  static bool isInflectableTerm(Term term) {
    return _classForTerm(term) != null;
  }

  /// Produces likely dictionary-form spellings for a surface form without
  /// touching the dictionary. Camera Mode batches these candidates and then
  /// validates the returned entries against their real part-of-speech tags.
  static Set<String> deinflectionCandidates(String rawSurface) {
    final surface = rawSurface.trim();
    final candidates = <String>{};

    if (surface.isEmpty) return candidates;

    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty || cleaned == surface) return;
      candidates.add(cleaned);
    }

    void addPoliteCandidates(String suffix) {
      if (!surface.endsWith(suffix) || surface.length <= suffix.length) return;

      final stem = surface.substring(0, surface.length - suffix.length);
      _addDictionaryFormsFromIStem(stem, add);

      // Ichidan verbs use the bare stem before ます.
      add('$stemる');

      if (stem.endsWith('し')) {
        add('${stem.substring(0, stem.length - 1)}する');
      }

      if (stem.endsWith('き')) {
        add('${stem.substring(0, stem.length - 1)}くる');
      }

      if (stem.endsWith('来')) {
        add('$stemる');
      }
    }

    addPoliteCandidates('ませんでした');
    addPoliteCandidates('ました');
    addPoliteCandidates('ません');
    addPoliteCandidates('ます');

    void addNegativeCandidates(String suffix) {
      if (!surface.endsWith(suffix) || surface.length <= suffix.length) return;

      final stem = surface.substring(0, surface.length - suffix.length);
      _addDictionaryFormsFromAStem(stem, add);
      add('$stemる');

      if (stem.endsWith('し')) {
        add('${stem.substring(0, stem.length - 1)}する');
      }

      if (stem.endsWith('こ')) {
        add('${stem.substring(0, stem.length - 1)}くる');
      }

      if (stem.endsWith('来')) {
        add('$stemる');
      }
    }

    addNegativeCandidates('なかった');
    addNegativeCandidates('ない');

    _addTePastCandidates(surface, add);
    _addExtendedVerbCandidates(surface, add);
    _addIAdjectiveCandidates(surface, add);

    for (final requestSuffix in const ['ください', '下さい']) {
      if (!surface.endsWith(requestSuffix) ||
          surface.length <= requestSuffix.length) {
        continue;
      }

      final preceding = surface.substring(
        0,
        surface.length - requestSuffix.length,
      );

      for (final candidate in deinflectionCandidates(preceding)) {
        add(candidate);
      }
    }

    return candidates;
  }

  /// Confirms that [surface] is a plausible form of [term]. This prevents the
  /// reverse rules from accepting an unrelated homographic dictionary entry.
  static bool surfaceMatchesTerm(Term term, String rawSurface) {
    final surface = rawSurface.trim();

    if (surface.isEmpty || !isInflectableTerm(term)) return false;

    for (final spelling in _candidateSpellings(term)) {
      if (spelling == surface) return true;

      final forms = _recognitionFormsForSpelling(
        term: term,
        spelling: spelling,
      );

      if (forms.contains(surface)) return true;
    }

    return false;
  }

  static Set<String> _recognitionFormsForSpelling({
    required Term term,
    required String spelling,
  }) {
    final inflectionClass = _classForTerm(term);

    if (inflectionClass == null || spelling.isEmpty) return const <String>{};

    final forms = <String>{spelling};
    final chartForms = switch (inflectionClass) {
      _JapaneseInflectionClass.ichidan => _ichidanForms(spelling),
      _JapaneseInflectionClass.godan => _godanForms(spelling),
      _JapaneseInflectionClass.suru => _suruForms(spelling),
      _JapaneseInflectionClass.kuru => _kuruForms(spelling),
      _JapaneseInflectionClass.iAdjective => _iAdjectiveForms(spelling),
    };

    forms.addAll(chartForms.map((form) => form.value));

    if (inflectionClass == _JapaneseInflectionClass.iAdjective) {
      return forms;
    }

    final polite = _formValue(chartForms, 'Polite');
    final teForm = _formValue(chartForms, 'て-form');

    if (polite != null && polite.endsWith('ます')) {
      final politeStem = polite.substring(0, polite.length - 2);
      forms.add('$politeStemました');
      forms.add('$politeStemません');
      forms.add('$politeStemませんでした');
    }

    if (teForm != null) {
      forms.add('$teFormください');
      forms.add('$teForm下さい');
    }

    return forms;
  }

  static String? _formValue(
    List<JapaneseConjugationForm> forms,
    String label,
  ) {
    for (final form in forms) {
      if (form.label == label) return form.value;
    }

    return null;
  }

  static List<String> _candidateSpellings(Term term) {
    final spellings = <String>[];

    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty || spellings.contains(cleaned)) return;
      spellings.add(cleaned);
    }

    add(term.kanji);
    for (final alternative in term.alternativeKanji) {
      add(alternative);
    }
    add(term.reading);

    return spellings;
  }

  static _JapaneseInflectionClass? _classForTerm(Term term) {
    final tags = <String>[
      term.partOfSpeech,
      for (final sense in term.senses) ...sense.partOfSpeechTags,
    ].map((tag) => tag.trim().toLowerCase()).where((tag) {
      return tag.isNotEmpty;
    }).toList(growable: false);

    bool anyTag(bool Function(String tag) test) => tags.any(test);

    if (anyTag((tag) =>
        tag == 'vk' ||
        tag.startsWith('vk-') ||
        tag.contains('kuru verb') ||
        tag.contains('来る verb'))) {
      return _JapaneseInflectionClass.kuru;
    }

    if (anyTag((tag) =>
        tag == 'vs' ||
        tag.startsWith('vs-') ||
        tag.contains('suru verb') ||
        tag.contains('する verb'))) {
      return _JapaneseInflectionClass.suru;
    }

    if (anyTag((tag) =>
        tag == 'v1' ||
        tag.startsWith('v1-') ||
        tag.contains('ichidan'))) {
      return _JapaneseInflectionClass.ichidan;
    }

    if (anyTag((tag) => tag.startsWith('v5') || tag.contains('godan'))) {
      return _JapaneseInflectionClass.godan;
    }

    if (anyTag((tag) =>
        tag == 'adj-i' ||
        tag.startsWith('adj-i-') ||
        tag == 'adj-ix' ||
        tag.startsWith('adj-ix-') ||
        tag.contains('i-adjective'))) {
      return _JapaneseInflectionClass.iAdjective;
    }

    final explicitlyVerb = anyTag((tag) => tag.contains('verb'));
    final spelling = _displaySpelling(term);

    if (explicitlyVerb) {
      if (spelling.endsWith('する')) return _JapaneseInflectionClass.suru;
      if (spelling.endsWith('来る') || spelling.endsWith('くる')) {
        return _JapaneseInflectionClass.kuru;
      }

      if (_looksLikeIchidanByReading(term.reading)) {
        return _JapaneseInflectionClass.ichidan;
      }

      if (_godanEnding(spelling) != null) {
        return _JapaneseInflectionClass.godan;
      }
    }

    return null;
  }

  static bool _looksLikeIchidanByReading(String rawReading) {
    final reading = rawReading.trim();
    if (!reading.endsWith('る') || reading.length < 2) return false;

    const commonGodanRuExceptions = <String>{
      'ある',
      'いる',
      'おる',
      'かえる',
      'きる',
      'しる',
      'すべる',
      'はいる',
      'はしる',
      'へる',
      'まいる',
      'まじる',
      'にぎる',
      'しゃべる',
      'ける',
    };

    if (commonGodanRuExceptions.contains(reading)) return false;

    final previous = reading.substring(reading.length - 2, reading.length - 1);

    return RegExp(r'[いきぎしじちぢにひびぴみりえけげせぜてでねへべぺめれ]').hasMatch(previous);
  }

  static String _displaySpelling(Term term) {
    final kanji = term.kanji.trim();
    return kanji.isNotEmpty ? kanji : term.reading.trim();
  }

  static List<JapaneseConjugationForm> _verbForms({
    required String dictionary,
    required String politeStem,
    required String negative,
    required String past,
    required String negativePast,
    required String teForm,
    required String negativeTeForm,
    required String potential,
    required String passive,
    required String causative,
    required String volitional,
    required String conditional,
    required String taraConditional,
    required String imperative,
    required String negativeConditional,
    required String negativeTaraConditional,
    required String negativePotential,
    required String negativePassive,
    required String negativeCausative,
    required String negativeImperative,
    required String negativeRequest,
  }) {
    String politeRuForm(String value, String ending) {
      if (!value.endsWith('る') || value.length < 2) return '';

      return '${value.substring(0, value.length - 1)}$ending';
    }

    return [
      JapaneseConjugationForm(label: 'Dictionary', value: dictionary),
      JapaneseConjugationForm(label: 'Past', value: past),
      JapaneseConjugationForm(label: 'て-form', value: teForm),
      JapaneseConjugationForm(label: 'Conditional', value: conditional),
      JapaneseConjugationForm(
        label: 'Tara conditional',
        value: taraConditional,
      ),
      JapaneseConjugationForm(label: 'Potential', value: potential),
      JapaneseConjugationForm(label: 'Passive', value: passive),
      JapaneseConjugationForm(label: 'Causative', value: causative),
      JapaneseConjugationForm(label: 'Imperative', value: imperative),
      JapaneseConjugationForm(label: 'Volitional', value: volitional),
      JapaneseConjugationForm(label: 'Negative', value: negative),
      JapaneseConjugationForm(label: 'Negative past', value: negativePast),
      JapaneseConjugationForm(
        label: 'Negative て-form',
        value: negativeTeForm,
      ),
      JapaneseConjugationForm(
        label: 'Negative conditional',
        value: negativeConditional,
      ),
      JapaneseConjugationForm(
        label: 'Negative tara conditional',
        value: negativeTaraConditional,
      ),
      JapaneseConjugationForm(
        label: 'Negative potential',
        value: negativePotential,
      ),
      JapaneseConjugationForm(
        label: 'Negative passive',
        value: negativePassive,
      ),
      JapaneseConjugationForm(
        label: 'Negative causative',
        value: negativeCausative,
      ),
      JapaneseConjugationForm(
        label: 'Negative imperative',
        value: negativeImperative,
      ),
      JapaneseConjugationForm(label: 'Polite', value: '$politeStemます'),
      JapaneseConjugationForm(
        label: 'Polite past',
        value: '$politeStemました',
      ),
      JapaneseConjugationForm(
        label: 'Polite conditional',
        value: '$politeStemませば',
      ),
      JapaneseConjugationForm(
        label: 'Polite tara conditional',
        value: '$politeStemましたら',
      ),
      JapaneseConjugationForm(
        label: 'Polite potential',
        value: politeRuForm(potential, 'ます'),
      ),
      JapaneseConjugationForm(
        label: 'Polite passive',
        value: politeRuForm(passive, 'ます'),
      ),
      JapaneseConjugationForm(
        label: 'Polite causative',
        value: politeRuForm(causative, 'ます'),
      ),
      JapaneseConjugationForm(
        label: 'Polite imperative',
        value: '$teFormください',
      ),
      JapaneseConjugationForm(
        label: 'Polite volitional',
        value: '$politeStemましょう',
      ),
      JapaneseConjugationForm(
        label: 'Polite negative',
        value: '$politeStemません',
      ),
      JapaneseConjugationForm(
        label: 'Polite negative past',
        value: '$politeStemませんでした',
      ),
      JapaneseConjugationForm(
        label: 'Polite negative potential',
        value: politeRuForm(potential, 'ません'),
      ),
      JapaneseConjugationForm(
        label: 'Polite negative passive',
        value: politeRuForm(passive, 'ません'),
      ),
      JapaneseConjugationForm(
        label: 'Polite negative causative',
        value: politeRuForm(causative, 'ません'),
      ),
      JapaneseConjugationForm(
        label: 'Polite negative imperative',
        value: negativeRequest,
      ),
    ].where((form) => form.value.trim().isNotEmpty).toList(growable: false);
  }

  static List<JapaneseConjugationForm> _ichidanForms(String word) {
    if (!word.endsWith('る') || word.length < 2) return const [];

    final stem = word.substring(0, word.length - 1);

    return _verbForms(
      dictionary: word,
      politeStem: stem,
      negative: '$stemない',
      past: '$stemた',
      negativePast: '$stemなかった',
      teForm: '$stemて',
      negativeTeForm: '$stemなくて',
      potential: '$stemられる',
      passive: '$stemられる',
      causative: '$stemさせる',
      volitional: '$stemよう',
      conditional: '$stemれば',
      taraConditional: '$stemたら',
      imperative: '$stemろ',
      negativeConditional: '$stemなければ',
      negativeTaraConditional: '$stemなかったら',
      negativePotential: '$stemられない',
      negativePassive: '$stemられない',
      negativeCausative: '$stemさせない',
      negativeImperative: '$wordな',
      negativeRequest: '$stemないでください',
    );
  }

  static List<JapaneseConjugationForm> _godanForms(String word) {
    final ending = _godanEnding(word);
    if (ending == null) return const [];

    final stem = word.substring(0, word.length - 1);
    final row = _godanRows[ending]!;
    var teForm = '$stem${row.te}';
    var past = '$stem${row.past}';

    if (_isIkuException(word)) {
      teForm = '${word.substring(0, word.length - 1)}って';
      past = '${word.substring(0, word.length - 1)}った';
    }

    return _verbForms(
      dictionary: word,
      politeStem: '$stem${row.i}',
      negative: '$stem${row.a}ない',
      past: past,
      negativePast: '$stem${row.a}なかった',
      teForm: teForm,
      negativeTeForm: '$stem${row.a}なくて',
      potential: '$stem${row.e}る',
      passive: '$stem${row.a}れる',
      causative: '$stem${row.a}せる',
      volitional: '$stem${row.o}う',
      conditional: '$stem${row.e}ば',
      taraConditional: '$pastら',
      imperative: '$stem${row.e}',
      negativeConditional: '$stem${row.a}なければ',
      negativeTaraConditional: '$stem${row.a}なかったら',
      negativePotential: '$stem${row.e}ない',
      negativePassive: '$stem${row.a}れない',
      negativeCausative: '$stem${row.a}せない',
      negativeImperative: '$wordな',
      negativeRequest: '$stem${row.a}ないでください',
    );
  }

  static List<JapaneseConjugationForm> _suruForms(String word) {
    if (!word.endsWith('する')) return const [];

    final stem = word.substring(0, word.length - 2);

    return _verbForms(
      dictionary: word,
      politeStem: '$stemし',
      negative: '$stemしない',
      past: '$stemした',
      negativePast: '$stemしなかった',
      teForm: '$stemして',
      negativeTeForm: '$stemしなくて',
      potential: '$stemできる',
      passive: '$stemされる',
      causative: '$stemさせる',
      volitional: '$stemしよう',
      conditional: '$stemすれば',
      taraConditional: '$stemしたら',
      imperative: '$stemしろ',
      negativeConditional: '$stemしなければ',
      negativeTaraConditional: '$stemしなかったら',
      negativePotential: '$stemできない',
      negativePassive: '$stemされない',
      negativeCausative: '$stemさせない',
      negativeImperative: '$wordな',
      negativeRequest: '$stemしないでください',
    );
  }

  static List<JapaneseConjugationForm> _kuruForms(String word) {
    if (word.endsWith('来る')) {
      final stem = word.substring(0, word.length - 1);

      return _verbForms(
        dictionary: word,
        politeStem: stem,
        negative: '$stemない',
        past: '$stemた',
        negativePast: '$stemなかった',
        teForm: '$stemて',
        negativeTeForm: '$stemなくて',
        potential: '$stemられる',
        passive: '$stemられる',
        causative: '$stemさせる',
        volitional: '$stemよう',
        conditional: '$stemれば',
        taraConditional: '$stemたら',
        imperative: '$stemい',
        negativeConditional: '$stemなければ',
        negativeTaraConditional: '$stemなかったら',
        negativePotential: '$stemられない',
        negativePassive: '$stemられない',
        negativeCausative: '$stemさせない',
        negativeImperative: '$wordな',
        negativeRequest: '$stemないでください',
      );
    }

    if (!word.endsWith('くる')) return const [];

    final stem = word.substring(0, word.length - 2);

    return _verbForms(
      dictionary: word,
      politeStem: '$stemき',
      negative: '$stemこない',
      past: '$stemきた',
      negativePast: '$stemこなかった',
      teForm: '$stemきて',
      negativeTeForm: '$stemこなくて',
      potential: '$stemこられる',
      passive: '$stemこられる',
      causative: '$stemこさせる',
      volitional: '$stemこよう',
      conditional: '$stemくれば',
      taraConditional: '$stemきたら',
      imperative: '$stemこい',
      negativeConditional: '$stemこなければ',
      negativeTaraConditional: '$stemこなかったら',
      negativePotential: '$stemこられない',
      negativePassive: '$stemこられない',
      negativeCausative: '$stemこさせない',
      negativeImperative: '$wordな',
      negativeRequest: '$stemこないでください',
    );
  }

  static List<JapaneseConjugationForm> _iAdjectiveForms(String word) {
    if (!word.endsWith('い') || word.length < 2) return const [];

    final regularStem = word.substring(0, word.length - 1);
    final isIi = word == 'いい';
    final isYoi = word == '良い';
    final stem = isIi ? 'よ' : regularStem;
    final inflectedStem = isYoi ? '良' : stem;

    return [
      JapaneseConjugationForm(label: 'Dictionary', value: word),
      JapaneseConjugationForm(label: 'Past', value: '$inflectedStemかった'),
      JapaneseConjugationForm(label: 'て-form', value: '$inflectedStemくて'),
      JapaneseConjugationForm(
        label: 'Conditional',
        value: '$inflectedStemければ',
      ),
      JapaneseConjugationForm(
        label: 'Tara conditional',
        value: '$inflectedStemかったら',
      ),
      JapaneseConjugationForm(label: 'Adverbial', value: '$inflectedStemく'),
      JapaneseConjugationForm(label: 'Negative', value: '$inflectedStemくない'),
      JapaneseConjugationForm(
        label: 'Negative past',
        value: '$inflectedStemくなかった',
      ),
      JapaneseConjugationForm(
        label: 'Negative て-form',
        value: '$inflectedStemくなくて',
      ),
      JapaneseConjugationForm(
        label: 'Negative conditional',
        value: '$inflectedStemくなければ',
      ),
      JapaneseConjugationForm(
        label: 'Negative tara conditional',
        value: '$inflectedStemくなかったら',
      ),
      JapaneseConjugationForm(label: 'Polite', value: '$wordです'),
      JapaneseConjugationForm(
        label: 'Polite past',
        value: '$inflectedStemかったです',
      ),
      JapaneseConjugationForm(
        label: 'Polite negative',
        value: '$inflectedStemくないです',
      ),
      JapaneseConjugationForm(
        label: 'Polite negative past',
        value: '$inflectedStemくなかったです',
      ),
    ];
  }

  static String? _godanEnding(String word) {
    if (word.isEmpty) return null;
    final ending = word.substring(word.length - 1);
    return _godanRows.containsKey(ending) ? ending : null;
  }

  static bool _isIkuException(String word) {
    return word == '行く' || word == 'いく' || word == 'ゆく' || word == '往く';
  }

  static void _addDictionaryFormsFromIStem(
    String stem,
    void Function(String value) add,
  ) {
    if (stem.isEmpty) return;

    final ending = stem.substring(stem.length - 1);
    final dictionaryEnding = _iStemToDictionary[ending];

    if (dictionaryEnding != null) {
      add('${stem.substring(0, stem.length - 1)}$dictionaryEnding');
    }
  }

  static void _addDictionaryFormsFromAStem(
    String stem,
    void Function(String value) add,
  ) {
    if (stem.isEmpty) return;

    final ending = stem.substring(stem.length - 1);
    final dictionaryEnding = _aStemToDictionary[ending];

    if (dictionaryEnding != null) {
      add('${stem.substring(0, stem.length - 1)}$dictionaryEnding');
    }
  }

  static void _addTePastCandidates(
    String surface,
    void Function(String value) add,
  ) {
    void replaceSuffix(String suffix, List<String> dictionaryEndings) {
      if (!surface.endsWith(suffix) || surface.length <= suffix.length) return;

      final stem = surface.substring(0, surface.length - suffix.length);
      for (final ending in dictionaryEndings) {
        add('$stem$ending');
      }
    }

    replaceSuffix('って', const ['う', 'つ', 'る', 'く']);
    replaceSuffix('った', const ['う', 'つ', 'る', 'く']);
    replaceSuffix('いて', const ['く']);
    replaceSuffix('いた', const ['く']);
    replaceSuffix('いで', const ['ぐ']);
    replaceSuffix('いだ', const ['ぐ']);
    replaceSuffix('して', const ['す', 'する']);
    replaceSuffix('した', const ['す', 'する']);
    replaceSuffix('んで', const ['ぬ', 'ぶ', 'む']);
    replaceSuffix('んだ', const ['ぬ', 'ぶ', 'む']);

    // Ichidan て/た forms. Longer godan/suru patterns above will also have
    // generated their candidates, and dictionary/POS validation resolves the
    // ambiguity later.
    replaceSuffix('て', const ['る']);
    replaceSuffix('た', const ['る']);

    if (surface.endsWith('きて') && surface.length > 2) {
      add('${surface.substring(0, surface.length - 2)}くる');
    }
    if (surface.endsWith('きた') && surface.length > 2) {
      add('${surface.substring(0, surface.length - 2)}くる');
    }
    if (surface.endsWith('来て')) {
      add('${surface.substring(0, surface.length - 1)}る');
    }
    if (surface.endsWith('来た')) {
      add('${surface.substring(0, surface.length - 1)}る');
    }
  }

  static void _addExtendedVerbCandidates(
    String surface,
    void Function(String value) add,
  ) {
    // Ichidan potential/passive, causative, volitional, and conditional.
    void ichidanFromSuffix(String suffix, String replacement) {
      if (!surface.endsWith(suffix) || surface.length <= suffix.length) return;
      final stem = surface.substring(0, surface.length - suffix.length);
      add('$stem$replacement');
    }

    ichidanFromSuffix('られる', 'る');
    ichidanFromSuffix('させる', 'る');
    ichidanFromSuffix('よう', 'る');
    ichidanFromSuffix('れば', 'る');

    // Godan passive and causative return to the a-stem.
    for (final suffix in const ['れる', 'せる']) {
      if (!surface.endsWith(suffix) || surface.length <= suffix.length) continue;
      final aStem = surface.substring(0, surface.length - suffix.length);
      _addDictionaryFormsFromAStem(aStem, add);
    }

    // Godan conditional uses the e-stem + ば.
    if (surface.endsWith('ば') && surface.length > 1) {
      final eStem = surface.substring(0, surface.length - 1);
      _addDictionaryFormsFromEStem(eStem, add);
    }

    // Godan potential uses the e-stem + る.
    if (surface.endsWith('る') && surface.length > 1) {
      final eStem = surface.substring(0, surface.length - 1);
      _addDictionaryFormsFromEStem(eStem, add);
    }

    // Godan volitional uses the o-stem + う.
    if (surface.endsWith('う') && surface.length > 1) {
      final oStem = surface.substring(0, surface.length - 1);
      _addDictionaryFormsFromOStem(oStem, add);
    }
  }

  static void _addIAdjectiveCandidates(
    String surface,
    void Function(String value) add,
  ) {
    void fromSuffix(String suffix, String stemSuffix) {
      if (!surface.endsWith(suffix) || surface.length <= suffix.length) return;
      final stem = surface.substring(0, surface.length - suffix.length);
      add('$stem$stemSuffix');

      if (stem == 'よ') {
        add('いい');
      } else if (stem == '良') {
        add('良い');
      }
    }

    fromSuffix('くなかった', 'い');
    fromSuffix('くない', 'い');
    fromSuffix('かった', 'い');
    fromSuffix('くて', 'い');
    fromSuffix('ければ', 'い');

    if (surface.endsWith('いです') && surface.length > 2) {
      add(surface.substring(0, surface.length - 2));
    }
  }

  static void _addDictionaryFormsFromEStem(
    String stem,
    void Function(String value) add,
  ) {
    if (stem.isEmpty) return;

    final ending = stem.substring(stem.length - 1);
    final dictionaryEnding = _eStemToDictionary[ending];

    if (dictionaryEnding != null) {
      add('${stem.substring(0, stem.length - 1)}$dictionaryEnding');
    }
  }

  static void _addDictionaryFormsFromOStem(
    String stem,
    void Function(String value) add,
  ) {
    if (stem.isEmpty) return;

    final ending = stem.substring(stem.length - 1);
    final dictionaryEnding = _oStemToDictionary[ending];

    if (dictionaryEnding != null) {
      add('${stem.substring(0, stem.length - 1)}$dictionaryEnding');
    }
  }

  static const Map<String, String> _iStemToDictionary = {
    'い': 'う',
    'き': 'く',
    'ぎ': 'ぐ',
    'し': 'す',
    'ち': 'つ',
    'に': 'ぬ',
    'び': 'ぶ',
    'み': 'む',
    'り': 'る',
  };

  static const Map<String, String> _aStemToDictionary = {
    'わ': 'う',
    'か': 'く',
    'が': 'ぐ',
    'さ': 'す',
    'た': 'つ',
    'な': 'ぬ',
    'ば': 'ぶ',
    'ま': 'む',
    'ら': 'る',
  };

  static const Map<String, String> _eStemToDictionary = {
    'え': 'う',
    'け': 'く',
    'げ': 'ぐ',
    'せ': 'す',
    'て': 'つ',
    'ね': 'ぬ',
    'べ': 'ぶ',
    'め': 'む',
    'れ': 'る',
  };

  static const Map<String, String> _oStemToDictionary = {
    'お': 'う',
    'こ': 'く',
    'ご': 'ぐ',
    'そ': 'す',
    'と': 'つ',
    'の': 'ぬ',
    'ぼ': 'ぶ',
    'も': 'む',
    'ろ': 'る',
  };

  static const Map<String, _GodanRow> _godanRows = {
    'う': _GodanRow(a: 'わ', i: 'い', e: 'え', o: 'お', te: 'って', past: 'った'),
    'く': _GodanRow(a: 'か', i: 'き', e: 'け', o: 'こ', te: 'いて', past: 'いた'),
    'ぐ': _GodanRow(a: 'が', i: 'ぎ', e: 'げ', o: 'ご', te: 'いで', past: 'いだ'),
    'す': _GodanRow(a: 'さ', i: 'し', e: 'せ', o: 'そ', te: 'して', past: 'した'),
    'つ': _GodanRow(a: 'た', i: 'ち', e: 'て', o: 'と', te: 'って', past: 'った'),
    'ぬ': _GodanRow(a: 'な', i: 'に', e: 'ね', o: 'の', te: 'んで', past: 'んだ'),
    'ぶ': _GodanRow(a: 'ば', i: 'び', e: 'べ', o: 'ぼ', te: 'んで', past: 'んだ'),
    'む': _GodanRow(a: 'ま', i: 'み', e: 'め', o: 'も', te: 'んで', past: 'んだ'),
    'る': _GodanRow(a: 'ら', i: 'り', e: 'れ', o: 'ろ', te: 'って', past: 'った'),
  };
}

class _GodanRow {
  final String a;
  final String i;
  final String e;
  final String o;
  final String te;
  final String past;

  const _GodanRow({
    required this.a,
    required this.i,
    required this.e,
    required this.o,
    required this.te,
    required this.past,
  });
}
