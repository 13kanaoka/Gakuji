import 'dart:math';

import 'package:gakuji/features/games/models/kanji_fusion_round.dart';
import 'package:gakuji/domain/term.dart';

class _FusionChoiceSpec {
  final String label;
  final List<String> forms;

  const _FusionChoiceSpec({
    required this.label,
    required this.forms,
  });
}

class _FusionStructure {
  final List<KanjiFusionSlot> slots;
  final List<KanjiFusionGroup> groups;

  const _FusionStructure({
    required this.slots,
    this.groups = const [],
  });
}

class KanjiFusionRoundGenerator {
  static const double choicesPerAnswerSlot = 3.5;
  static const int minimumChoiceCount = 4;
  static const Map<String, List<String>> _easyRecipes = {
    '明': ['日', '月'],
    '休': ['人', '木'],
    '体': ['人', '本'],
    '何': ['人', '可'],
    '況': ['水', '兄'],
    '作': ['人', '乍'],
    '住': ['人', '主'],
    '位': ['人', '立'],
    '信': ['人', '言'],
    '仕': ['人', '士'],
    '件': ['人', '牛'],
    '化': ['人', '匕'],
    '代': ['人', '弋'],
    '仙': ['人', '山'],
    '兄': ['口', '儿'],
    '林': ['木', '木'],
    '森': ['木', '木', '木'],
    '村': ['木', '寸'],
    '校': ['木', '交'],
    '相': ['木', '目'],
    '交': ['亠', '父'],
    '男': ['田', '力'],
    '思': ['田', '心'],
    '界': ['田', '介'],
    '町': ['田', '丁'],
    '聞': ['門', '耳'],
    '問': ['門', '口'],
    '間': ['門', '日'],
    '闇': ['門', '音'],
    '時': ['日', '寺'],
    '星': ['日', '生'],
    '早': ['日', '十'],
    '昌': ['日', '日'],
    '晶': ['日', '日', '日'],
    '映': ['日', '央'],
    '照': ['昭', '火'],
    '晴': ['日', '青'],
    '曜': ['日', '羽', '隹'],
    '朋': ['月', '月'],
    '期': ['其', '月'],
    '炎': ['火', '火'],
    '灯': ['火', '丁'],
    '品': ['口', '口', '口'],
    '唱': ['口', '日', '日'],
    '歌': ['哥', '欠'],
    '鳴': ['口', '鳥'],
    '味': ['口', '未'],
    '呼': ['口', '乎'],
    '名': ['夕', '口'],
    '多': ['夕', '夕'],
    '外': ['夕', '卜'],
    '和': ['禾', '口'],
    '秋': ['禾', '火'],
    '科': ['禾', '斗'],
    '私': ['禾', '厶'],
    '流': ['水', '𠫓', '川'],
    '海': ['水', '毎'],
    '河': ['水', '可'],
    '池': ['水', '也'],
    '洗': ['水', '先'],
    '洋': ['水', '羊'],
    '酒': ['水', '酉'],
    '活': ['水', '舌'],
    '清': ['水', '青'],
    '泳': ['水', '永'],
    '語': ['言', '吾'],
    '話': ['言', '舌'],
    '計': ['言', '十'],
    '記': ['言', '己'],
    '読': ['言', '売'],
    '試': ['言', '式'],
    '詩': ['言', '寺'],
    '好': ['女', '子'],
    '姉': ['女', '市'],
    '妹': ['女', '未'],
    '姓': ['女', '生'],
    '安': ['宀', '女'],
    '字': ['宀', '子'],
    '家': ['宀', '豕'],
    '室': ['宀', '至'],
    '空': ['穴', '工'],
    '花': ['艹', '化'],
    '茶': ['艹', '人', '木'],
    '草': ['艹', '早'],
    '英': ['艹', '央'],
    '苗': ['艹', '田'],
    '薬': ['艹', '楽'],
    '雪': ['雨', '彐'],
    '雷': ['雨', '田'],
    '電': ['雨', '电'],
    '岩': ['山', '石'],
    '炭': ['山', '灰'],
    '音': ['立', '日'],
    '意': ['音', '心'],
    '章': ['立', '早'],
    '新': ['立', '木', '斤'],
    '見': ['目', '儿'],
    '親': ['立', '木', '見'],
    '買': ['罒', '貝'],
    '置': ['目', '直'],
    '貧': ['分', '貝'],
    '員': ['口', '貝'],
    '持': ['手', '寺'],
    '打': ['手', '丁'],
    '投': ['手', '殳'],
    '拾': ['手', '合'],
    '性': ['心', '生'],
    '情': ['心', '青'],
    '快': ['心', '夬'],
    '想': ['相', '心'],
    '忘': ['亡', '心'],
    '念': ['今', '心'],
    '線': ['糸', '泉'],
    '紙': ['糸', '氏'],
    '組': ['糸', '且'],
    '終': ['糸', '冬'],
    '絵': ['糸', '会'],
    '社': ['示', '土'],
    '神': ['示', '申'],
    '初': ['衣', '刀'],
    '被': ['衣', '皮'],
    '猫': ['犬', '苗'],
    '独': ['犬', '虫'],
    '地': ['土', '也'],
    '城': ['土', '成'],
    '国': ['囗', '玉'],
    '回': ['囗', '口'],
    '困': ['囗', '木'],
    '図': ['囗', '斗'],
    '因': ['囗', '大'],
    '囲': ['囗', '井'],
  };
  static const Map<String, List<String>> _showcasePromptData = {
    '明': ['あかるい', 'bright; clear'],
    '休': ['やすむ', 'rest; take a break'],
    '体': ['からだ', 'body'],
    '何': ['なに', 'what'],
    '況': ['きょう', 'condition; situation'],
    '作': ['つくる', 'make; create'],
    '住': ['すむ', 'live; reside'],
    '位': ['くらい', 'rank; position'],
    '信': ['しん', 'trust; belief'],
    '仕': ['つかえる', 'serve; work'],
    '件': ['けん', 'matter; case'],
    '化': ['か', 'change; transformation'],
    '代': ['だい', 'generation; substitute'],
    '仙': ['せん', 'hermit; immortal'],
    '兄': ['あに', 'older brother'],
    '林': ['はやし', 'woods'],
    '森': ['もり', 'forest'],
    '村': ['むら', 'village'],
    '校': ['こう', 'school'],
    '相': ['あい', 'mutual; appearance'],
    '交': ['まじわる', 'mix; associate'],
    '男': ['おとこ', 'man; male'],
    '思': ['おもう', 'think; feel'],
    '界': ['かい', 'world; boundary'],
    '町': ['まち', 'town'],
    '聞': ['きく', 'hear; ask'],
    '問': ['とう', 'ask; question'],
    '間': ['あいだ', 'interval; space'],
    '闇': ['やみ', 'darkness'],
    '時': ['とき', 'time'],
    '星': ['ほし', 'star'],
    '早': ['はやい', 'early; fast'],
    '昌': ['しょう', 'prosperous; bright'],
    '晶': ['しょう', 'crystal; sparkle'],
    '映': ['うつる', 'reflect; project'],
    '照': ['てる', 'shine; illuminate'],
    '晴': ['はれる', 'clear weather'],
    '曜': ['よう', 'weekday; day of the week'],
    '朋': ['とも', 'companion; friend'],
    '期': ['き', 'period; expectation'],
    '炎': ['ほのお', 'flame'],
    '灯': ['ひ', 'lamp; light'],
    '品': ['しな', 'goods; quality'],
    '唱': ['となえる', 'chant; recite'],
    '歌': ['うたう', 'sing; song'],
    '鳴': ['なく', 'make a sound; cry'],
    '味': ['あじ', 'taste; flavor'],
    '呼': ['よぶ', 'call'],
    '名': ['な', 'name'],
    '多': ['おおい', 'many'],
    '外': ['そと', 'outside'],
    '和': ['わ', 'harmony; Japanese style'],
    '秋': ['あき', 'autumn'],
    '科': ['か', 'department; course'],
    '私': ['わたし', 'I; private'],
    '流': ['ながす', 'let flow; drain; pour'],
    '海': ['うみ', 'sea'],
    '河': ['かわ', 'river'],
    '池': ['いけ', 'pond'],
    '洗': ['あらう', 'wash'],
    '洋': ['よう', 'ocean; Western style'],
    '酒': ['さけ', 'alcohol; sake'],
    '活': ['かつ', 'life; activity'],
    '清': ['きよい', 'pure; clean'],
    '泳': ['およぐ', 'swim'],
    '語': ['かたる', 'language; tell'],
    '話': ['はなす', 'speak; story'],
    '計': ['はかる', 'measure; plan'],
    '記': ['しるす', 'record; write down'],
    '読': ['よむ', 'read'],
    '試': ['ためす', 'try; test'],
    '詩': ['し', 'poem'],
    '好': ['すき', 'like; favorable'],
    '姉': ['あね', 'older sister'],
    '妹': ['いもうと', 'younger sister'],
    '姓': ['せい', 'surname'],
    '安': ['やすい', 'cheap; peaceful'],
    '字': ['じ', 'character; letter'],
    '家': ['いえ', 'house; home'],
    '室': ['しつ', 'room'],
    '空': ['そら', 'sky; empty'],
    '花': ['はな', 'flower'],
    '茶': ['ちゃ', 'tea'],
    '草': ['くさ', 'grass'],
    '英': ['えい', 'English; excellent'],
    '苗': ['なえ', 'seedling'],
    '薬': ['くすり', 'medicine'],
    '雪': ['ゆき', 'snow'],
    '雷': ['かみなり', 'thunder'],
    '電': ['でん', 'electricity'],
    '岩': ['いわ', 'rock'],
    '炭': ['すみ', 'charcoal'],
    '音': ['おと', 'sound'],
    '意': ['い', 'meaning; intention'],
    '章': ['しょう', 'chapter; badge'],
    '新': ['あたらしい', 'new'],
    '見': ['みる', 'see; look'],
    '親': ['おや', 'parent; close'],
    '買': ['かう', 'buy'],
    '置': ['おく', 'put; place'],
    '貧': ['まずしい', 'poor'],
    '員': ['いん', 'member'],
    '持': ['もつ', 'hold; possess'],
    '打': ['うつ', 'hit; strike'],
    '投': ['なげる', 'throw'],
    '拾': ['ひろう', 'pick up'],
    '性': ['せい', 'nature; sex'],
    '情': ['じょう', 'feeling; circumstances'],
    '快': ['こころよい', 'pleasant'],
    '想': ['そう', 'thought; idea'],
    '忘': ['わすれる', 'forget'],
    '念': ['ねん', 'thought; attention'],
    '線': ['せん', 'line'],
    '紙': ['かみ', 'paper'],
    '組': ['くむ', 'assemble; group'],
    '終': ['おわる', 'end; finish'],
    '絵': ['え', 'picture'],
    '社': ['しゃ', 'company; shrine'],
    '神': ['かみ', 'god; spirit'],
    '初': ['はじめ', 'first; beginning'],
    '被': ['こうむる', 'suffer; be covered'],
    '猫': ['ねこ', 'cat'],
    '独': ['ひとり', 'alone; independent'],
    '地': ['ち', 'ground; land'],
    '城': ['しろ', 'castle'],
    '国': ['くに', 'country'],
    '回': ['まわる', 'turn; occurrence'],
    '困': ['こまる', 'be troubled'],
    '図': ['ず', 'diagram; plan'],
    '因': ['いん', 'cause; factor'],
    '囲': ['かこむ', 'surround'],
  };

  // The top-level IDS follows the immediate reusable units identified by RTK.
  // Fusion then expands a curated set of transparent nested units so every
  // round remains understandable even when the learner has not followed a
  // fixed curriculum. Nested units keep a visible group boundary while their
  // leaf components become the draggable pieces. Opaque units such as 鳥 and
  // 直 remain whole rather than being forced into arbitrary stroke fragments.
  static const Map<String, String> _normalIds = {
    '明': '⿰日月', '休': '⿰亻木', '体': '⿰亻本', '何': '⿰亻可', '況': '⿰氵兄', '作': '⿰亻乍',
    '住': '⿰亻主', '位': '⿰亻立', '信': '⿰亻言', '仕': '⿰亻士', '件': '⿰亻牛',
    '化': '⿰亻匕', '代': '⿰亻弋', '仙': '⿰亻山', '兄': '⿱口儿',
    '林': '⿰木木', '森': '⿱木⿰木木',
    '村': '⿰木寸', '校': '⿰木交', '相': '⿰木目', '交': '⿱亠父', '男': '⿱田力',
    '思': '⿱田心', '界': '⿱田介', '町': '⿰田丁', '聞': '⿵門耳', '問': '⿵門口',
    '間': '⿵門日', '闇': '⿵門音', '時': '⿰日寺', '星': '⿱日生', '早': '⿱日十',
    '昌': '⿱日日', '晶': '⿱日⿰日日', '映': '⿰日央', '照': '⿱昭灬',
    '晴': '⿰日青', '曜': '⿰日⿱羽隹', '朋': '⿰月月', '期': '⿰其月', '炎': '⿱火火', '灯': '⿰火丁',
    '品': '⿱口⿰口口', '唱': '⿰口⿱日日',
    '歌': '⿰哥欠', '鳴': '⿰口鳥', '味': '⿰口未', '呼': '⿰口乎',
    '名': '⿱夕口', '多': '⿱夕夕', '外': '⿰夕卜', '和': '⿰禾口', '秋': '⿰禾火',
    '科': '⿰禾斗', '私': '⿰禾厶', '流': '⿰氵⿱𠫓川',
    '海': '⿰氵毎', '河': '⿰氵可', '池': '⿰氵也',
    '洗': '⿰氵先', '洋': '⿰氵羊', '酒': '⿰氵酉', '活': '⿰氵舌', '清': '⿰氵青',
    '泳': '⿰氵永', '語': '⿰言吾', '話': '⿰言舌', '計': '⿰言十', '記': '⿰言己',
    '読': '⿰言売', '試': '⿰言式', '詩': '⿰言寺', '好': '⿰女子', '姉': '⿰女市',
    '妹': '⿰女未', '姓': '⿰女生', '安': '⿱宀女', '字': '⿱宀子', '家': '⿱宀豕',
    '室': '⿱宀至', '空': '⿱穴工', '花': '⿱艹化', '茶': '⿱艹⿱𠆢木',
    '草': '⿱艹早', '英': '⿱艹央', '苗': '⿱艹田', '薬': '⿱艹楽', '雪': '⿱雨彐', '雷': '⿱雨田',
    '電': '⿱雨电', '岩': '⿱山石', '炭': '⿱山灰',
    '音': '⿱立日', '意': '⿱音心', '章': '⿱立早', '新': '⿰亲斤',
    '見': '⿱目儿', '親': '⿰亲見', '買': '⿱罒貝',
    '置': '⿱罒直', '貧': '⿱分貝',
    '員': '⿱口貝', '持': '⿰扌寺', '打': '⿰扌丁', '投': '⿰扌殳', '拾': '⿰扌合',
    '性': '⿰忄生', '情': '⿰忄青', '快': '⿰忄夬', '想': '⿱相心',
    '忘': '⿱亡心', '念': '⿱今心', '線': '⿰糹泉', '紙': '⿰糹氏', '組': '⿰糹且',
    '終': '⿰糹冬', '絵': '⿰糹会', '社': '⿰礻土', '神': '⿰礻申', '初': '⿰衤刀',
    '被': '⿰衤皮', '猫': '⿰犭苗', '独': '⿰犭虫', '地': '⿰土也', '城': '⿰土成',
    '国': '⿴囗玉', '回': '⿴囗口', '困': '⿴囗木', '図': '⿴囗斗', '因': '⿴囗大',
    '囲': '⿴囗井',
  };

  // Only components with a clear, reusable internal structure are expanded.
  // The completed component is retained as a visual group, but the listed
  // leaves are what the learner actually drags into the answer box.
  static const Map<String, String> _nestedComponentIds = {
    '兄': '⿱口儿',
    '見': '⿱目儿',
    '寺': '⿱土寸',
    '舌': '⿱千口',
    '音': '⿱立日',
    '亲': '⿱立木',
    '可': '⿹丁口',
    '哥': '⿱可可',
    '昭': '⿰日召',
    '召': '⿱刀口',
    '相': '⿰木目',
    '化': '⿰亻匕',
    '早': '⿱日十',
    '交': '⿱亠父',
    '苗': '⿱艹田',
  };


  static const Map<String, List<String>> _radicalFormFamilies = {
    '人': ['人', '亻', '𠆢'],
    '目': ['目', '罒'],
    '水': ['水', '氵'],
    '手': ['手', '扌'],
    '心': ['心', '忄', '⺗'],
    '糸': ['糸', '糹'],
    '言': ['言', '訁'],
    '示': ['示', '礻'],
    '衣': ['衣', '衤'],
    '犬': ['犬', '犭'],
    '火': ['火', '灬'],
    '刀': ['刀', '刂'],
    '金': ['金', '釒'],
    '食': ['食', '飠'],
  };


  static List<KanjiFusionRound> buildRounds(
    List<Term> terms, {
    KanjiFusionDifficulty difficulty = KanjiFusionDifficulty.easy,
    KanjiFusionRadicalMode radicalMode = KanjiFusionRadicalMode.receive,
    Random? random,
  }) {
    final rng = random ?? Random();

    _FusionStructure structureFor(String kanji) {
      final custom = _customStructure(kanji, difficulty);
      return custom ?? _parseStructure(_normalIds[kanji]!);
    }

    int componentCountFor(String kanji) {
      if (difficulty == KanjiFusionDifficulty.easy) {
        return _easyRecipes[kanji]!.length;
      }
      return structureFor(kanji).slots.length;
    }

    final allSupportedKanji = _normalIds.keys
        .where(_easyRecipes.containsKey)
        .where((kanji) => componentCountFor(kanji) >= 2)
        .toList(growable: false);

    final sourceTerms = <String, Term>{};
    final deckKanji = <String>{};

    for (final term in terms) {
      final spelling = term.kanji.trim();
      if (spelling.isEmpty) continue;

      for (final kanji in _extractKanji(spelling)) {
        if (!allSupportedKanji.contains(kanji)) continue;

        deckKanji.add(kanji);

        // An exact single-kanji card has the most specific saved prompt.
        // Kanji extracted from a larger word use the curated kanji-level
        // reading and meaning so Fusion remains a single-kanji activity.
        if (spelling == kanji) {
          sourceTerms[kanji] = term;
        } else {
          sourceTerms.putIfAbsent(
            kanji,
            () => _showcaseTerm(kanji, difficulty),
          );
        }
      }
    }

    final entries = deckKanji.toList()..shuffle(rng);

    // Distractors come from the complete supported component library rather
    // than only the current deck. A deck with one eligible kanji can therefore
    // still receive the full Normal-mode set of ten choices.
    final componentPool = difficulty == KanjiFusionDifficulty.easy
        ? allSupportedKanji
            .expand((kanji) => _easyRecipes[kanji]!)
            .toSet()
            .toList()
        : allSupportedKanji
            .expand(
              (kanji) => structureFor(kanji).slots.map(
                (slot) => slot.component,
              ),
            )
            .toSet()
            .toList();

    return List.unmodifiable(
      entries.map((kanji) {
        final structure = structureFor(kanji);
        final slots = structure.slots;
        final required = difficulty == KanjiFusionDifficulty.easy
            ? List<String>.from(_easyRecipes[kanji]!)
            : slots.map((slot) => slot.component).toList(growable: false);

        final choiceSpecs = <_FusionChoiceSpec>[
          for (final component in required)
            _choiceSpec(
              component,
              difficulty: difficulty,
              radicalMode: radicalMode,
            ),
        ];

        final distractors = componentPool
            .where((component) => !required.contains(component))
            .toList()
          ..shuffle(rng);
        final choiceTarget = _choiceCountFor(required.length);
        final usedDistractorKeys = <String>{
          for (final choice in choiceSpecs) _choiceKey(choice),
        };

        while (choiceSpecs.length < choiceTarget && distractors.isNotEmpty) {
          final candidate = _choiceSpec(
            distractors.removeLast(),
            difficulty: difficulty,
            radicalMode: radicalMode,
          );
          final key = _choiceKey(candidate);
          if (!usedDistractorKeys.add(key)) continue;
          choiceSpecs.add(candidate);
        }

        choiceSpecs.shuffle(rng);

        return KanjiFusionRound(
          term: sourceTerms[kanji] ?? _showcaseTerm(kanji, difficulty),
          targetKanji: kanji,
          requiredComponents: List<String>.unmodifiable(required),
          componentChoices: List<String>.unmodifiable(
            choiceSpecs.map((choice) => choice.label),
          ),
          componentFormChoices: List<List<String>>.unmodifiable(
            choiceSpecs.map(
              (choice) => List<String>.unmodifiable(choice.forms),
            ),
          ),
          structuralSlots: List<KanjiFusionSlot>.unmodifiable(slots),
          structuralGroups: List<KanjiFusionGroup>.unmodifiable(
            structure.groups,
          ),
        );
      }),
    );
  }

  static Iterable<String> _extractKanji(String text) sync* {
    for (final rune in text.runes) {
      if (_isKanjiRune(rune)) {
        yield String.fromCharCode(rune);
      }
    }
  }

  static bool _isKanjiRune(int rune) {
    return (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x20000 && rune <= 0x2FA1F);
  }

  static int _choiceCountFor(int requiredSlotCount) {
    if (requiredSlotCount <= 0) return 0;

    final scaledChoiceCount =
        (requiredSlotCount * choicesPerAnswerSlot).floor();

    return max(
      requiredSlotCount,
      max(minimumChoiceCount, scaledChoiceCount),
    );
  }

  static Term _showcaseTerm(
    String kanji,
    KanjiFusionDifficulty difficulty,
  ) {
    final prompt = _showcasePromptData[kanji];
    final reading = prompt == null ? kanji : prompt[0];
    final definition = prompt == null ? 'Kanji component practice' : prompt[1];

    return Term(
      id: 'fusion_showcase_${difficulty.name}_$kanji',
      kanji: kanji,
      reading: reading,
      meaning: definition,
    );
  }

  static _FusionChoiceSpec _choiceSpec(
    String exactComponent, {
    required KanjiFusionDifficulty difficulty,
    required KanjiFusionRadicalMode radicalMode,
  }) {
    final shouldCreateForm = difficulty == KanjiFusionDifficulty.normal &&
        radicalMode == KanjiFusionRadicalMode.create;

    if (!shouldCreateForm) {
      return _FusionChoiceSpec(
        label: exactComponent,
        forms: <String>[exactComponent],
      );
    }

    final base = _baseComponentFor(exactComponent);
    return _FusionChoiceSpec(
      label: base,
      forms: List<String>.from(
        _radicalFormFamilies[base] ?? <String>[exactComponent],
      ),
    );
  }

  static String _choiceKey(_FusionChoiceSpec choice) {
    return '${choice.label}|${choice.forms.join(',')}';
  }

  static String _baseComponentFor(String component) {
    for (final entry in _radicalFormFamilies.entries) {
      if (entry.value.contains(component)) return entry.key;
    }
    return component;
  }

  static _FusionStructure? _customStructure(
    String kanji,
    KanjiFusionDifficulty difficulty,
  ) {
    if (difficulty == KanjiFusionDifficulty.easy) return null;

    String? gateInnerComponent;
    switch (kanji) {
      case '聞':
        gateInnerComponent = '耳';
        break;
      case '問':
        gateInnerComponent = '口';
        break;
      case '間':
        gateInnerComponent = '日';
        break;
      case '闇':
        gateInnerComponent = '音';
        break;
    }

    if (gateInnerComponent != null) {
      final slots = <KanjiFusionSlot>[
        const KanjiFusionSlot(
          component: '門',
          left: 0.10,
          top: 0.05,
          width: 0.80,
          height: 0.86,
          shape: KanjiFusionSlotShape.gate,
          contentLeft: 0.30,
          contentTop: 0.02,
          contentWidth: 0.40,
          contentHeight: 0.20,
        ),
      ];
      final groups = <KanjiFusionGroup>[];

      if (gateInnerComponent == '音') {
        groups.add(
          const KanjiFusionGroup(
            component: '音',
            left: 0.29,
            top: 0.26,
            width: 0.42,
            height: 0.65,
          ),
        );
        slots.addAll(const [
          KanjiFusionSlot(
            component: '立',
            left: 0.33,
            top: 0.30,
            width: 0.34,
            height: 0.27,
          ),
          KanjiFusionSlot(
            component: '日',
            left: 0.33,
            top: 0.61,
            width: 0.34,
            height: 0.26,
          ),
        ]);
      } else {
        slots.add(
          KanjiFusionSlot(
            component: gateInnerComponent,
            left: 0.31,
            top: 0.29,
            width: 0.38,
            height: 0.62,
          ),
        );
      }

      return _FusionStructure(slots: slots, groups: groups);
    }

    String? enclosureInnerComponent;
    switch (kanji) {
      case '国':
        enclosureInnerComponent = '玉';
        break;
      case '回':
        enclosureInnerComponent = '口';
        break;
      case '困':
        enclosureInnerComponent = '木';
        break;
      case '図':
        enclosureInnerComponent = '斗';
        break;
      case '因':
        enclosureInnerComponent = '大';
        break;
      case '囲':
        enclosureInnerComponent = '井';
        break;
    }

    if (enclosureInnerComponent != null) {
      return _FusionStructure(
        slots: [
          const KanjiFusionSlot(
            component: '囗',
            left: 0.12,
            top: 0.06,
            width: 0.76,
            height: 0.82,
            shape: KanjiFusionSlotShape.enclosure,
            contentLeft: 0.30,
            contentTop: 0.02,
            contentWidth: 0.40,
            contentHeight: 0.18,
          ),
          KanjiFusionSlot(
            component: enclosureInnerComponent,
            left: 0.29,
            top: 0.24,
            width: 0.42,
            height: 0.46,
          ),
        ],
      );
    }

    if (kanji == '炭') {
      return const _FusionStructure(
        slots: [
          KanjiFusionSlot(
            component: '山',
            left: 0.13,
            top: 0.05,
            width: 0.74,
            height: 0.27,
          ),
          KanjiFusionSlot(
            component: '灰',
            left: 0.18,
            top: 0.37,
            width: 0.64,
            height: 0.56,
          ),
        ],
      );
    }

    String? rightHookLeftComponent;
    switch (kanji) {
      case '何':
        rightHookLeftComponent = '亻';
        break;
      case '河':
        rightHookLeftComponent = '氵';
        break;
    }

    if (rightHookLeftComponent != null) {
      return _FusionStructure(
        groups: const [
          KanjiFusionGroup(
            component: '可',
            left: 0.40,
            top: 0.05,
            width: 0.57,
            height: 0.90,
          ),
        ],
        slots: [
          KanjiFusionSlot(
            component: rightHookLeftComponent,
            left: 0.05,
            top: 0.08,
            width: 0.30,
            height: 0.84,
          ),
          const KanjiFusionSlot(
            component: '丁',
            left: 0.43,
            top: 0.08,
            width: 0.52,
            height: 0.84,
            shape: KanjiFusionSlotShape.rightHook,
            contentLeft: 0.30,
            contentTop: 0.02,
            contentWidth: 0.40,
            contentHeight: 0.20,
          ),
          const KanjiFusionSlot(
            component: '口',
            left: 0.43,
            top: 0.35,
            width: 0.29,
            height: 0.57,
          ),
        ],
      );
    }

    if (kanji == '兄') {
      return const _FusionStructure(
        slots: [
          KanjiFusionSlot(
            component: '口',
            left: 0.24,
            top: 0.08,
            width: 0.52,
            height: 0.34,
          ),
          KanjiFusionSlot(
            component: '儿',
            left: 0.18,
            top: 0.48,
            width: 0.64,
            height: 0.44,
          ),
        ],
      );
    }

    if (kanji == '流') {
      return const _FusionStructure(
        slots: [
          KanjiFusionSlot(
            component: '氵',
            left: 0.05,
            top: 0.08,
            width: 0.27,
            height: 0.84,
          ),
          KanjiFusionSlot(
            component: '𠫓',
            left: 0.39,
            top: 0.08,
            width: 0.55,
            height: 0.34,
          ),
          KanjiFusionSlot(
            component: '川',
            left: 0.39,
            top: 0.49,
            width: 0.55,
            height: 0.43,
          ),
        ],
      );
    }

    if (kanji == '歌') {
      return const _FusionStructure(
        groups: [
          KanjiFusionGroup(
            component: '哥',
            left: 0.04,
            top: 0.05,
            width: 0.60,
            height: 0.90,
          ),
          KanjiFusionGroup(
            component: '可',
            left: 0.07,
            top: 0.08,
            width: 0.54,
            height: 0.39,
            depth: 1,
          ),
          KanjiFusionGroup(
            component: '可',
            left: 0.07,
            top: 0.50,
            width: 0.54,
            height: 0.39,
            depth: 1,
          ),
        ],
        slots: [
          KanjiFusionSlot(
            component: '丁',
            left: 0.09,
            top: 0.10,
            width: 0.50,
            height: 0.34,
            shape: KanjiFusionSlotShape.rightHook,
            contentLeft: 0.30,
            contentTop: 0.02,
            contentWidth: 0.40,
            contentHeight: 0.20,
          ),
          KanjiFusionSlot(
            component: '口',
            left: 0.09,
            top: 0.22,
            width: 0.28,
            height: 0.20,
          ),
          KanjiFusionSlot(
            component: '丁',
            left: 0.09,
            top: 0.52,
            width: 0.50,
            height: 0.34,
            shape: KanjiFusionSlotShape.rightHook,
            contentLeft: 0.30,
            contentTop: 0.02,
            contentWidth: 0.40,
            contentHeight: 0.20,
          ),
          KanjiFusionSlot(
            component: '口',
            left: 0.09,
            top: 0.64,
            width: 0.28,
            height: 0.20,
          ),
          KanjiFusionSlot(
            component: '欠',
            left: 0.68,
            top: 0.11,
            width: 0.27,
            height: 0.78,
          ),
        ],
      );
    }

    if (kanji == '鳴') {
      return const _FusionStructure(
        slots: [
          KanjiFusionSlot(
            component: '口',
            left: 0.05,
            top: 0.29,
            width: 0.27,
            height: 0.40,
          ),
          KanjiFusionSlot(
            component: '鳥',
            left: 0.38,
            top: 0.06,
            width: 0.57,
            height: 0.87,
          ),
        ],
      );
    }

    if (kanji == '置') {
      return const _FusionStructure(
        slots: [
          KanjiFusionSlot(
            component: '罒',
            left: 0.13,
            top: 0.05,
            width: 0.74,
            height: 0.25,
          ),
          KanjiFusionSlot(
            component: '直',
            left: 0.18,
            top: 0.35,
            width: 0.64,
            height: 0.58,
          ),
        ],
      );
    }

    if (kanji == '電') {
      return const _FusionStructure(
        slots: [
          KanjiFusionSlot(
            component: '雨',
            left: 0.13,
            top: 0.05,
            width: 0.74,
            height: 0.31,
          ),
          KanjiFusionSlot(
            component: '电',
            left: 0.21,
            top: 0.40,
            width: 0.58,
            height: 0.53,
          ),
        ],
      );
    }

    if (kanji == '新') {
      return const _FusionStructure(
        groups: [
          KanjiFusionGroup(
            component: '亲',
            left: 0.04,
            top: 0.04,
            width: 0.60,
            height: 0.92,
          ),
        ],
        slots: [
          KanjiFusionSlot(
            component: '立',
            left: 0.09,
            top: 0.08,
            width: 0.50,
            height: 0.35,
          ),
          KanjiFusionSlot(
            component: '木',
            left: 0.09,
            top: 0.49,
            width: 0.50,
            height: 0.40,
          ),
          KanjiFusionSlot(
            component: '斤',
            left: 0.68,
            top: 0.10,
            width: 0.27,
            height: 0.80,
          ),
        ],
      );
    }

    if (kanji == '親') {
      return const _FusionStructure(
        groups: [
          KanjiFusionGroup(
            component: '亲',
            left: 0.03,
            top: 0.04,
            width: 0.52,
            height: 0.92,
          ),
          KanjiFusionGroup(
            component: '見',
            left: 0.57,
            top: 0.04,
            width: 0.40,
            height: 0.92,
          ),
        ],
        slots: [
          KanjiFusionSlot(
            component: '立',
            left: 0.07,
            top: 0.08,
            width: 0.44,
            height: 0.35,
          ),
          KanjiFusionSlot(
            component: '木',
            left: 0.07,
            top: 0.49,
            width: 0.44,
            height: 0.40,
          ),
          KanjiFusionSlot(
            component: '目',
            left: 0.61,
            top: 0.08,
            width: 0.32,
            height: 0.38,
          ),
          KanjiFusionSlot(
            component: '儿',
            left: 0.61,
            top: 0.52,
            width: 0.32,
            height: 0.37,
          ),
        ],
      );
    }

    return null;
  }

  static _FusionStructure _parseStructure(String ids) {
    final parser = _IdsStructureParser(
      nestedIds: _nestedComponentIds,
    );
    parser.parseIds(ids, 0.05, 0.05, 0.90, 0.90);
    return _FusionStructure(
      slots: parser.slots,
      groups: parser.groups,
    );
  }
}

class _IdsStructureParser {
  final Map<String, String> nestedIds;
  final List<KanjiFusionSlot> slots = [];
  final List<KanjiFusionGroup> groups = [];

  _IdsStructureParser({required this.nestedIds});

  void parseIds(
    String ids,
    double left,
    double top,
    double width,
    double height, {
    int depth = 0,
  }) {
    final cursor = _IdsCursor(ids);
    _parse(cursor, left, top, width, height, depth: depth);
  }

  void _parse(
    _IdsCursor cursor,
    double left,
    double top,
    double width,
    double height, {
    required int depth,
    KanjiFusionSlotShape leafShape = KanjiFusionSlotShape.standard,
    double contentLeft = 0,
    double contentTop = 0,
    double contentWidth = 1,
    double contentHeight = 1,
  }) {
    final token = cursor.next();

    switch (token) {
      case '⿰':
        _splitHorizontal(cursor, 2, left, top, width, height, depth);
        return;
      case '⿲':
        _splitHorizontal(cursor, 3, left, top, width, height, depth);
        return;
      case '⿱':
        _splitVertical(cursor, 2, left, top, width, height, depth);
        return;
      case '⿳':
        _splitVertical(cursor, 3, left, top, width, height, depth);
        return;
      case '⿴':
        _parse(
          cursor,
          left,
          top,
          width,
          height,
          depth: depth,
          leafShape: KanjiFusionSlotShape.enclosure,
          contentLeft: 0.30,
          contentTop: 0.02,
          contentWidth: 0.40,
          contentHeight: 0.18,
        );
        _parse(
          cursor,
          left + (width * 0.23),
          top + (height * 0.22),
          width * 0.58,
          height * 0.60,
          depth: depth,
        );
        return;
      case '⿵':
        _parse(
          cursor,
          left,
          top,
          width,
          height,
          depth: depth,
          leafShape: KanjiFusionSlotShape.gate,
          contentLeft: 0.30,
          contentTop: 0.02,
          contentWidth: 0.40,
          contentHeight: 0.20,
        );
        _parse(
          cursor,
          left + (width * 0.23),
          top + (height * 0.22),
          width * 0.58,
          height * 0.60,
          depth: depth,
        );
        return;
      case '⿸':
        _parse(
          cursor,
          left,
          top,
          width,
          height,
          depth: depth,
          leafShape: KanjiFusionSlotShape.cliff,
          contentLeft: 0.04,
          contentTop: 0.02,
          contentWidth: 0.42,
          contentHeight: 0.22,
        );
        _parse(
          cursor,
          left + (width * 0.30),
          top + (height * 0.28),
          width * 0.62,
          height * 0.64,
          depth: depth,
        );
        return;
      case '⿹':
        _parse(
          cursor,
          left,
          top,
          width,
          height,
          depth: depth,
          leafShape: KanjiFusionSlotShape.rightHook,
          contentLeft: 0.30,
          contentTop: 0.02,
          contentWidth: 0.40,
          contentHeight: 0.20,
        );
        _parse(
          cursor,
          left,
          top + (height * 0.32),
          width * 0.58,
          height * 0.66,
          depth: depth,
        );
        return;
      case '⿶':
      case '⿷':
      case '⿺':
        _parse(cursor, left, top, width, height, depth: depth);
        _parse(
          cursor,
          left + (width * 0.30),
          top + (height * 0.28),
          width * 0.62,
          height * 0.64,
          depth: depth,
        );
        return;
      case '⿻':
        _parse(cursor, left, top, width, height, depth: depth);
        _parse(
          cursor,
          left + (width * 0.12),
          top + (height * 0.40),
          width * 0.76,
          height * 0.20,
          depth: depth,
        );
        return;
    }

    final nestedIdsForToken = nestedIds[token];
    if (nestedIdsForToken != null) {
      groups.add(
        KanjiFusionGroup(
          component: token,
          left: left,
          top: top,
          width: width,
          height: height,
          depth: depth,
        ),
      );

      final horizontalPadding = width * 0.055;
      final verticalPadding = height * 0.055;
      parseIds(
        nestedIdsForToken,
        left + horizontalPadding,
        top + verticalPadding,
        width - (horizontalPadding * 2),
        height - (verticalPadding * 2),
        depth: depth + 1,
      );
      return;
    }

    slots.add(
      KanjiFusionSlot(
        component: token,
        left: left,
        top: top,
        width: width,
        height: height,
        shape: leafShape,
        contentLeft: contentLeft,
        contentTop: contentTop,
        contentWidth: contentWidth,
        contentHeight: contentHeight,
      ),
    );
  }

  void _splitHorizontal(
    _IdsCursor cursor,
    int count,
    double left,
    double top,
    double width,
    double height,
    int depth,
  ) {
    const gap = 0.035;
    final childWidth = (width - (gap * (count - 1))) / count;
    for (var index = 0; index < count; index++) {
      _parse(
        cursor,
        left + (index * (childWidth + gap)),
        top,
        childWidth,
        height,
        depth: depth,
      );
    }
  }

  void _splitVertical(
    _IdsCursor cursor,
    int count,
    double left,
    double top,
    double width,
    double height,
    int depth,
  ) {
    const gap = 0.035;
    final childHeight = (height - (gap * (count - 1))) / count;
    for (var index = 0; index < count; index++) {
      _parse(
        cursor,
        left,
        top + (index * (childHeight + gap)),
        width,
        childHeight,
        depth: depth,
      );
    }
  }
}

class _IdsCursor {
  final List<int> runes;
  int offset = 0;

  _IdsCursor(String source) : runes = source.runes.toList(growable: false);

  String next() {
    if (offset >= runes.length) {
      throw StateError('Unexpected end of IDS structure.');
    }
    return String.fromCharCode(runes[offset++]);
  }
}
