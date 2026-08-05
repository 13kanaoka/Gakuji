import 'dart:math';

import '../models/kanji_fusion_round.dart';
import '../models/term.dart';

class _FusionChoiceSpec {
  final String label;
  final List<String> forms;

  const _FusionChoiceSpec({
    required this.label,
    required this.forms,
  });
}

class KanjiFusionRoundGenerator {
  static const int easyChoiceCount = 7;
  static const int normalChoiceCount = 10;
  static const Map<String, List<String>> _easyRecipes = {
    '明': ['日', '月'],
    '休': ['人', '木'],
    '体': ['人', '本'],
    '何': ['人', '丁', '口'],
    '作': ['人', '乍'],
    '住': ['人', '主'],
    '位': ['人', '立'],
    '信': ['人', '言'],
    '仕': ['人', '士'],
    '件': ['人', '牛'],
    '化': ['人', '匕'],
    '代': ['人', '弋'],
    '仙': ['人', '山'],
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
    '時': ['日', '土', '寸'],
    '星': ['日', '生'],
    '早': ['日', '十'],
    '昌': ['日', '日'],
    '晶': ['日', '日', '日'],
    '映': ['日', '央'],
    '照': ['日', '刀', '口', '火'],
    '晴': ['日', '青'],
    '朋': ['月', '月'],
    '期': ['其', '月'],
    '炎': ['火', '火'],
    '灯': ['火', '丁'],
    '品': ['口', '口', '口'],
    '唱': ['口', '昌'],
    '味': ['口', '未'],
    '呼': ['口', '乎'],
    '名': ['夕', '口'],
    '多': ['夕', '夕'],
    '外': ['夕', '卜'],
    '和': ['禾', '口'],
    '秋': ['禾', '火'],
    '科': ['禾', '斗'],
    '私': ['禾', '厶'],
    '海': ['水', '毎'],
    '河': ['水', '丁', '口'],
    '池': ['水', '也'],
    '洗': ['水', '先'],
    '洋': ['水', '羊'],
    '酒': ['水', '酉'],
    '活': ['水', '千', '口'],
    '清': ['水', '青'],
    '泳': ['水', '永'],
    '語': ['言', '吾'],
    '話': ['言', '千', '口'],
    '計': ['言', '十'],
    '記': ['言', '己'],
    '読': ['言', '売'],
    '試': ['言', '式'],
    '詩': ['言', '土', '寸'],
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
    '電': ['雨', '申'],
    '岩': ['山', '石'],
    '炭': ['山', '灰'],
    '出': ['山', '山'],
    '音': ['立', '日'],
    '意': ['立', '目', '心'],
    '章': ['立', '早'],
    '新': ['立', '木', '斤'],
    '見': ['目', '儿'],
    '親': ['立', '木', '見'],
    '買': ['罒', '貝'],
    '貧': ['分', '貝'],
    '員': ['口', '貝'],
    '持': ['手', '土', '寸'],
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
    '図': ['囗', '乂'],
    '因': ['囗', '大'],
    '囲': ['囗', '井'],
  };
  static const Map<String, List<String>> _showcasePromptData = {
    '明': ['あかるい', 'bright; clear'],
    '休': ['やすむ', 'rest; take a break'],
    '体': ['からだ', 'body'],
    '何': ['なに', 'what'],
    '作': ['つくる', 'make; create'],
    '住': ['すむ', 'live; reside'],
    '位': ['くらい', 'rank; position'],
    '信': ['しん', 'trust; belief'],
    '仕': ['つかえる', 'serve; work'],
    '件': ['けん', 'matter; case'],
    '化': ['か', 'change; transformation'],
    '代': ['だい', 'generation; substitute'],
    '仙': ['せん', 'hermit; immortal'],
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
    '朋': ['とも', 'companion; friend'],
    '期': ['き', 'period; expectation'],
    '炎': ['ほのお', 'flame'],
    '灯': ['ひ', 'lamp; light'],
    '品': ['しな', 'goods; quality'],
    '唱': ['となえる', 'chant; recite'],
    '味': ['あじ', 'taste; flavor'],
    '呼': ['よぶ', 'call'],
    '名': ['な', 'name'],
    '多': ['おおい', 'many'],
    '外': ['そと', 'outside'],
    '和': ['わ', 'harmony; Japanese style'],
    '秋': ['あき', 'autumn'],
    '科': ['か', 'department; course'],
    '私': ['わたし', 'I; private'],
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
    '出': ['でる', 'go out; exit'],
    '音': ['おと', 'sound'],
    '意': ['い', 'meaning; intention'],
    '章': ['しょう', 'chapter; badge'],
    '新': ['あたらしい', 'new'],
    '見': ['みる', 'see; look'],
    '親': ['おや', 'parent; close'],
    '買': ['かう', 'buy'],
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

  // Normal and Hard use curated, reusable components rather than
  // mechanically splitting every kanji into the smallest possible shapes.
  // Components such as 本, 央, 成, 糸, 貝, and 戈 stay whole when nested,
  // while transparent reusable structures such as 交, 見, and 苗 expand.
  static const Map<String, String> _normalIds = {
    '明': '⿰日月', '休': '⿰亻木', '体': '⿰亻本', '何': '⿰亻⿹丁口', '作': '⿰亻乍',
    '住': '⿰亻主', '位': '⿰亻立', '信': '⿰亻言', '仕': '⿰亻士', '件': '⿰亻牛',
    '化': '⿰亻匕', '代': '⿰亻弋', '仙': '⿰亻山', '林': '⿰木木', '森': '⿱木⿰木木',
    '村': '⿰木寸', '校': '⿰木⿱亠父', '相': '⿰木目', '交': '⿱亠父', '男': '⿱田力',
    '思': '⿱田心', '界': '⿱田介', '町': '⿰田丁', '聞': '⿵門耳', '問': '⿵門口',
    '間': '⿵門日', '闇': '⿵門音', '時': '⿰日⿱土寸', '星': '⿱日生', '早': '⿱日十',
    '昌': '⿱日日', '晶': '⿱日⿰日日', '映': '⿰日央', '照': '⿱昭灬',
    '晴': '⿰日青', '朋': '⿰月月', '期': '⿰其月', '炎': '⿱火火', '灯': '⿰火丁',
    '品': '⿱口⿰口口', '唱': '⿰口⿱日日', '味': '⿰口未', '呼': '⿰口乎',
    '名': '⿱夕口', '多': '⿱夕夕', '外': '⿰夕卜', '和': '⿰禾口', '秋': '⿰禾火',
    '科': '⿰禾斗', '私': '⿰禾厶', '海': '⿰氵毎', '河': '⿰氵⿹丁口', '池': '⿰氵也',
    '洗': '⿰氵先', '洋': '⿰氵羊', '酒': '⿰氵酉', '活': '⿰氵⿱千口', '清': '⿰氵青',
    '泳': '⿰氵永', '語': '⿰言吾', '話': '⿰言⿱千口', '計': '⿰言十', '記': '⿰言己',
    '読': '⿰言売', '試': '⿰言式', '詩': '⿰言⿱土寸', '好': '⿰女子', '姉': '⿰女市',
    '妹': '⿰女未', '姓': '⿰女生', '安': '⿱宀女', '字': '⿱宀子', '家': '⿱宀豕',
    '室': '⿱宀至', '空': '⿱穴工', '花': '⿱艹化', '茶': '⿱艹⿱𠆢木',
    '草': '⿱艹早', '英': '⿱艹央', '苗': '⿱艹田', '薬': '⿱艹楽', '雪': '⿱雨彐', '雷': '⿱雨田',
    '電': '⿱雨申', '岩': '⿱山石', '炭': '⿱山⿸厂火', '出': '⿱山山',
    '音': '⿱立日', '意': '⿳立目心', '章': '⿱立早', '新': '⿰⿱立木斤',
    '見': '⿱目儿', '親': '⿰⿱立木⿱目儿', '買': '⿱罒貝', '貧': '⿱分貝',
    '員': '⿱口貝', '持': '⿰扌⿱土寸', '打': '⿰扌丁', '投': '⿰扌殳', '拾': '⿰扌合',
    '性': '⿰忄生', '情': '⿰忄青', '快': '⿰忄夬', '想': '⿱相心',
    '忘': '⿱亡心', '念': '⿱今心', '線': '⿰糹泉', '紙': '⿰糹氏', '組': '⿰糹且',
    '終': '⿰糹冬', '絵': '⿰糹会', '社': '⿰礻土', '神': '⿰礻申', '初': '⿰衤刀',
    '被': '⿰衤皮', '猫': '⿰犭⿱艹田', '独': '⿰犭虫', '地': '⿰土也', '城': '⿰土成',
    '国': '⿴囗玉', '回': '⿴囗口', '困': '⿴囗木', '図': '⿴囗乂', '因': '⿴囗大',
    '囲': '⿴囗井',
  };


  static const Map<String, List<String>> _radicalFormFamilies = {
    '人': ['人', '亻', '𠆢'],
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
    List<Term> _terms, {
    KanjiFusionDifficulty difficulty = KanjiFusionDifficulty.easy,
    KanjiFusionRadicalMode radicalMode = KanjiFusionRadicalMode.receive,
    Random? random,
  }) {
    final rng = random ?? Random();
    final sourceTerms = <String, Term>{};
    for (final term in _terms) {
      final spelling = term.kanji.trim();
      if (_normalIds.containsKey(spelling) &&
          !sourceTerms.containsKey(spelling)) {
        sourceTerms[spelling] = term;
      }
    }

    final entries = _normalIds.keys
        .where(_easyRecipes.containsKey)
        .toList()
      ..shuffle(rng);

    List<KanjiFusionSlot> structuralSlotsFor(String kanji) {
      final custom = _customStructuralSlots(kanji, difficulty);
      return custom ?? _parseSlots(_normalIds[kanji]!);
    }

    int componentCountFor(String kanji) {
      if (difficulty == KanjiFusionDifficulty.easy) {
        return _easyRecipes[kanji]!.length;
      }
      return structuralSlotsFor(kanji).length;
    }

    entries.sort((a, b) {
      return componentCountFor(b).compareTo(componentCountFor(a));
    });

    final componentPool = difficulty == KanjiFusionDifficulty.easy
        ? _easyRecipes.values
            .expand((components) => components)
            .toSet()
            .toList()
        : entries
            .expand(
              (kanji) => structuralSlotsFor(kanji).map(
                (slot) => slot.component,
              ),
            )
            .toSet()
            .toList();

    return List.unmodifiable(
      entries.map((kanji) {
        final slots = structuralSlotsFor(kanji);
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
        final choiceTarget = max(
          _choiceCountFor(difficulty),
          required.length,
        );
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
        );
      }),
    );
  }

  static int _choiceCountFor(KanjiFusionDifficulty difficulty) {
    switch (difficulty) {
      case KanjiFusionDifficulty.easy:
        return easyChoiceCount;
      case KanjiFusionDifficulty.normal:
        return normalChoiceCount;
      case KanjiFusionDifficulty.hard:
        return easyChoiceCount;
    }
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

  static String _difficultyLabel(KanjiFusionDifficulty difficulty) {
    switch (difficulty) {
      case KanjiFusionDifficulty.easy:
        return 'Easy';
      case KanjiFusionDifficulty.normal:
        return 'Normal';
      case KanjiFusionDifficulty.hard:
        return 'Hard';
    }
  }

  static String _difficultyPrompt(
    KanjiFusionDifficulty difficulty,
    String kanji,
    KanjiFusionRadicalMode radicalMode,
  ) {
    switch (difficulty) {
      case KanjiFusionDifficulty.easy:
        return 'Choose the parts that make $kanji.';
      case KanjiFusionDifficulty.normal:
        return radicalMode == KanjiFusionRadicalMode.create
            ? 'Choose each radical form and build $kanji.'
            : 'Place the visible parts of $kanji.';
      case KanjiFusionDifficulty.hard:
        return 'Build $kanji without layout hints.';
    }
  }

  static List<KanjiFusionSlot>? _customStructuralSlots(
    String kanji,
    KanjiFusionDifficulty difficulty,
  ) {
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

    if (gateInnerComponent != null &&
        difficulty != KanjiFusionDifficulty.easy) {
      return [
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
        KanjiFusionSlot(
          component: gateInnerComponent,
          left: 0.31,
          top: 0.29,
          width: 0.38,
          height: 0.62,
        ),
      ];
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
        enclosureInnerComponent = '乂';
        break;
      case '因':
        enclosureInnerComponent = '大';
        break;
      case '囲':
        enclosureInnerComponent = '井';
        break;
    }

    if (enclosureInnerComponent != null &&
        difficulty != KanjiFusionDifficulty.easy) {
      return [
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
      ];
    }


    if (kanji == '炭' && difficulty != KanjiFusionDifficulty.easy) {
      return const [
        KanjiFusionSlot(
          component: '山',
          left: 0.12,
          top: 0.04,
          width: 0.76,
          height: 0.25,
        ),
        KanjiFusionSlot(
          component: '厂',
          left: 0.12,
          top: 0.34,
          width: 0.76,
          height: 0.60,
          shape: KanjiFusionSlotShape.cliff,
          contentLeft: 0.02,
          contentTop: 0.34,
          contentWidth: 0.30,
          contentHeight: 0.46,
        ),
        KanjiFusionSlot(
          component: '火',
          left: 0.42,
          top: 0.56,
          width: 0.46,
          height: 0.38,
        ),
      ];
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

    if (rightHookLeftComponent != null &&
        difficulty != KanjiFusionDifficulty.easy) {
      return [
        KanjiFusionSlot(
          component: rightHookLeftComponent,
          left: 0.05,
          top: 0.08,
          width: 0.34,
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
      ];
    }



    return null;
  }

  static List<KanjiFusionSlot> _parseSlots(String ids) {
    final parser = _IdsSlotParser(ids);
    parser.parse(0.05, 0.05, 0.90, 0.90);
    return parser.slots;
  }
}

class _IdsSlotParser {
  final String source;
  int offset = 0;
  final List<KanjiFusionSlot> slots = [];
  _IdsSlotParser(this.source);

  void parse(double l, double t, double w, double h) {
    final token = _next();
    switch (token) {
      case '⿰': _splitHorizontal(2,l,t,w,h); break;
      case '⿲': _splitHorizontal(3,l,t,w,h); break;
      case '⿱': _splitVertical(2,l,t,w,h); break;
      case '⿳': _splitVertical(3,l,t,w,h); break;
      case '⿴': case '⿵': case '⿶': case '⿷':
        parse(l,t,w,h); parse(l+w*.23,t+h*.22,w*.58,h*.60); break;
      case '⿸': case '⿹': case '⿺':
        parse(l,t,w,h); parse(l+w*.30,t+h*.28,w*.62,h*.64); break;
      case '⿻':
        parse(l,t,w,h); parse(l+w*.12,t+h*.40,w*.76,h*.20); break;
      default:
        slots.add(KanjiFusionSlot(component: token,left:l,top:t,width:w,height:h));
    }
  }
  void _splitHorizontal(int n,double l,double t,double w,double h) {
    const gap=.035; final cw=(w-gap*(n-1))/n;
    for(var i=0;i<n;i++) parse(l+i*(cw+gap),t,cw,h);
  }
  void _splitVertical(int n,double l,double t,double w,double h) {
    const gap=.035; final ch=(h-gap*(n-1))/n;
    for(var i=0;i<n;i++) parse(l,t+i*(ch+gap),w,ch);
  }
  String _next() {
    final rune = source.runes.elementAt(offset);
    offset++;
    return String.fromCharCode(rune);
  }
}

