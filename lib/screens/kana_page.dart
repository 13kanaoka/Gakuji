import 'package:flutter/material.dart';
import '../models/term.dart';
import '../models/writing_point.dart';
import '../services/dictionary_service.dart';
import '../widgets/gakuji_domino.dart';
import 'kana_study_page.dart';
import '../widgets/gakuji_styles.dart';
import '../widgets/gakuji_top_bar.dart';

class KanaPage extends StatefulWidget {
  const KanaPage({super.key});

  static const List<_KanaRow> hiraganaRows = [
    _KanaRow(
      kana: [
        _KanaEntry(character: 'あ', romaji: 'a'),
        _KanaEntry(character: 'い', romaji: 'i'),
        _KanaEntry(character: 'う', romaji: 'u'),
        _KanaEntry(character: 'え', romaji: 'e'),
        _KanaEntry(character: 'お', romaji: 'o'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'か', romaji: 'ka'),
        _KanaEntry(character: 'き', romaji: 'ki'),
        _KanaEntry(character: 'く', romaji: 'ku'),
        _KanaEntry(character: 'け', romaji: 'ke'),
        _KanaEntry(character: 'こ', romaji: 'ko'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'さ', romaji: 'sa'),
        _KanaEntry(character: 'し', romaji: 'shi'),
        _KanaEntry(character: 'す', romaji: 'su'),
        _KanaEntry(character: 'せ', romaji: 'se'),
        _KanaEntry(character: 'そ', romaji: 'so'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'た', romaji: 'ta'),
        _KanaEntry(character: 'ち', romaji: 'chi'),
        _KanaEntry(character: 'つ', romaji: 'tsu'),
        _KanaEntry(character: 'て', romaji: 'te'),
        _KanaEntry(character: 'と', romaji: 'to'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'な', romaji: 'na'),
        _KanaEntry(character: 'に', romaji: 'ni'),
        _KanaEntry(character: 'ぬ', romaji: 'nu'),
        _KanaEntry(character: 'ね', romaji: 'ne'),
        _KanaEntry(character: 'の', romaji: 'no'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'は', romaji: 'ha'),
        _KanaEntry(character: 'ひ', romaji: 'hi'),
        _KanaEntry(character: 'ふ', romaji: 'fu'),
        _KanaEntry(character: 'へ', romaji: 'he'),
        _KanaEntry(character: 'ほ', romaji: 'ho'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ま', romaji: 'ma'),
        _KanaEntry(character: 'み', romaji: 'mi'),
        _KanaEntry(character: 'む', romaji: 'mu'),
        _KanaEntry(character: 'め', romaji: 'me'),
        _KanaEntry(character: 'も', romaji: 'mo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'や', romaji: 'ya'),
        null,
        _KanaEntry(character: 'ゆ', romaji: 'yu'),
        null,
        _KanaEntry(character: 'よ', romaji: 'yo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ら', romaji: 'ra'),
        _KanaEntry(character: 'り', romaji: 'ri'),
        _KanaEntry(character: 'る', romaji: 'ru'),
        _KanaEntry(character: 'れ', romaji: 're'),
        _KanaEntry(character: 'ろ', romaji: 'ro'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'わ', romaji: 'wa'),
        null,
        null,
        null,
        _KanaEntry(character: 'を', romaji: 'wo'),
      ],
    ),
    _KanaRow(
      kana: [
        null,
        null,
        _KanaEntry(character: 'ん', romaji: 'n'),
        null,
        null,
      ],
    ),
  ];

  static const List<_KanaRow> katakanaRows = [
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ア', romaji: 'a'),
        _KanaEntry(character: 'イ', romaji: 'i'),
        _KanaEntry(character: 'ウ', romaji: 'u'),
        _KanaEntry(character: 'エ', romaji: 'e'),
        _KanaEntry(character: 'オ', romaji: 'o'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'カ', romaji: 'ka'),
        _KanaEntry(character: 'キ', romaji: 'ki'),
        _KanaEntry(character: 'ク', romaji: 'ku'),
        _KanaEntry(character: 'ケ', romaji: 'ke'),
        _KanaEntry(character: 'コ', romaji: 'ko'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'サ', romaji: 'sa'),
        _KanaEntry(character: 'シ', romaji: 'shi'),
        _KanaEntry(character: 'ス', romaji: 'su'),
        _KanaEntry(character: 'セ', romaji: 'se'),
        _KanaEntry(character: 'ソ', romaji: 'so'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'タ', romaji: 'ta'),
        _KanaEntry(character: 'チ', romaji: 'chi'),
        _KanaEntry(character: 'ツ', romaji: 'tsu'),
        _KanaEntry(character: 'テ', romaji: 'te'),
        _KanaEntry(character: 'ト', romaji: 'to'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ナ', romaji: 'na'),
        _KanaEntry(character: 'ニ', romaji: 'ni'),
        _KanaEntry(character: 'ヌ', romaji: 'nu'),
        _KanaEntry(character: 'ネ', romaji: 'ne'),
        _KanaEntry(character: 'ノ', romaji: 'no'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ハ', romaji: 'ha'),
        _KanaEntry(character: 'ヒ', romaji: 'hi'),
        _KanaEntry(character: 'フ', romaji: 'fu'),
        _KanaEntry(character: 'ヘ', romaji: 'he'),
        _KanaEntry(character: 'ホ', romaji: 'ho'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'マ', romaji: 'ma'),
        _KanaEntry(character: 'ミ', romaji: 'mi'),
        _KanaEntry(character: 'ム', romaji: 'mu'),
        _KanaEntry(character: 'メ', romaji: 'me'),
        _KanaEntry(character: 'モ', romaji: 'mo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ヤ', romaji: 'ya'),
        null,
        _KanaEntry(character: 'ユ', romaji: 'yu'),
        null,
        _KanaEntry(character: 'ヨ', romaji: 'yo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ラ', romaji: 'ra'),
        _KanaEntry(character: 'リ', romaji: 'ri'),
        _KanaEntry(character: 'ル', romaji: 'ru'),
        _KanaEntry(character: 'レ', romaji: 're'),
        _KanaEntry(character: 'ロ', romaji: 'ro'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ワ', romaji: 'wa'),
        null,
        null,
        null,
        _KanaEntry(character: 'ヲ', romaji: 'wo'),
      ],
    ),
    _KanaRow(
      kana: [
        null,
        null,
        _KanaEntry(character: 'ン', romaji: 'n'),
        null,
        null,
      ],
    ),
  ];

  static const List<_KanaRow> hiraganaDakuonRows = [
    _KanaRow(
      kana: [
        _KanaEntry(character: 'が', romaji: 'ga'),
        _KanaEntry(character: 'ぎ', romaji: 'gi'),
        _KanaEntry(character: 'ぐ', romaji: 'gu'),
        _KanaEntry(character: 'げ', romaji: 'ge'),
        _KanaEntry(character: 'ご', romaji: 'go'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ざ', romaji: 'za'),
        _KanaEntry(character: 'じ', romaji: 'ji'),
        _KanaEntry(character: 'ず', romaji: 'zu'),
        _KanaEntry(character: 'ぜ', romaji: 'ze'),
        _KanaEntry(character: 'ぞ', romaji: 'zo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'だ', romaji: 'da'),
        _KanaEntry(character: 'ぢ', romaji: 'ji'),
        _KanaEntry(character: 'づ', romaji: 'zu'),
        _KanaEntry(character: 'で', romaji: 'de'),
        _KanaEntry(character: 'ど', romaji: 'do'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ば', romaji: 'ba'),
        _KanaEntry(character: 'び', romaji: 'bi'),
        _KanaEntry(character: 'ぶ', romaji: 'bu'),
        _KanaEntry(character: 'べ', romaji: 'be'),
        _KanaEntry(character: 'ぼ', romaji: 'bo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ぱ', romaji: 'pa'),
        _KanaEntry(character: 'ぴ', romaji: 'pi'),
        _KanaEntry(character: 'ぷ', romaji: 'pu'),
        _KanaEntry(character: 'ぺ', romaji: 'pe'),
        _KanaEntry(character: 'ぽ', romaji: 'po'),
      ],
    ),
  ];

  static const List<_KanaRow> katakanaDakuonRows = [
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ガ', romaji: 'ga'),
        _KanaEntry(character: 'ギ', romaji: 'gi'),
        _KanaEntry(character: 'グ', romaji: 'gu'),
        _KanaEntry(character: 'ゲ', romaji: 'ge'),
        _KanaEntry(character: 'ゴ', romaji: 'go'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ザ', romaji: 'za'),
        _KanaEntry(character: 'ジ', romaji: 'ji'),
        _KanaEntry(character: 'ズ', romaji: 'zu'),
        _KanaEntry(character: 'ゼ', romaji: 'ze'),
        _KanaEntry(character: 'ゾ', romaji: 'zo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ダ', romaji: 'da'),
        _KanaEntry(character: 'ヂ', romaji: 'ji'),
        _KanaEntry(character: 'ヅ', romaji: 'zu'),
        _KanaEntry(character: 'デ', romaji: 'de'),
        _KanaEntry(character: 'ド', romaji: 'do'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'バ', romaji: 'ba'),
        _KanaEntry(character: 'ビ', romaji: 'bi'),
        _KanaEntry(character: 'ブ', romaji: 'bu'),
        _KanaEntry(character: 'ベ', romaji: 'be'),
        _KanaEntry(character: 'ボ', romaji: 'bo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'パ', romaji: 'pa'),
        _KanaEntry(character: 'ピ', romaji: 'pi'),
        _KanaEntry(character: 'プ', romaji: 'pu'),
        _KanaEntry(character: 'ペ', romaji: 'pe'),
        _KanaEntry(character: 'ポ', romaji: 'po'),
      ],
    ),
  ];

  static const List<_KanaRow> hiraganaYoonRows = [
    _KanaRow(
      kana: [
        _KanaEntry(character: 'きゃ', romaji: 'kya'),
        _KanaEntry(character: 'きゅ', romaji: 'kyu'),
        _KanaEntry(character: 'きょ', romaji: 'kyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ぎゃ', romaji: 'gya'),
        _KanaEntry(character: 'ぎゅ', romaji: 'gyu'),
        _KanaEntry(character: 'ぎょ', romaji: 'gyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'しゃ', romaji: 'sha'),
        _KanaEntry(character: 'しゅ', romaji: 'shu'),
        _KanaEntry(character: 'しょ', romaji: 'sho'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'じゃ', romaji: 'ja'),
        _KanaEntry(character: 'じゅ', romaji: 'ju'),
        _KanaEntry(character: 'じょ', romaji: 'jo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ちゃ', romaji: 'cha'),
        _KanaEntry(character: 'ちゅ', romaji: 'chu'),
        _KanaEntry(character: 'ちょ', romaji: 'cho'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ぢゃ', romaji: 'ja'),
        _KanaEntry(character: 'ぢゅ', romaji: 'ju'),
        _KanaEntry(character: 'ぢょ', romaji: 'jo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'にゃ', romaji: 'nya'),
        _KanaEntry(character: 'にゅ', romaji: 'nyu'),
        _KanaEntry(character: 'にょ', romaji: 'nyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ひゃ', romaji: 'hya'),
        _KanaEntry(character: 'ひゅ', romaji: 'hyu'),
        _KanaEntry(character: 'ひょ', romaji: 'hyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'びゃ', romaji: 'bya'),
        _KanaEntry(character: 'びゅ', romaji: 'byu'),
        _KanaEntry(character: 'びょ', romaji: 'byo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ぴゃ', romaji: 'pya'),
        _KanaEntry(character: 'ぴゅ', romaji: 'pyu'),
        _KanaEntry(character: 'ぴょ', romaji: 'pyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'みゃ', romaji: 'mya'),
        _KanaEntry(character: 'みゅ', romaji: 'myu'),
        _KanaEntry(character: 'みょ', romaji: 'myo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'りゃ', romaji: 'rya'),
        _KanaEntry(character: 'りゅ', romaji: 'ryu'),
        _KanaEntry(character: 'りょ', romaji: 'ryo'),
      ],
    ),
  ];

  static const List<_KanaRow> katakanaYoonRows = [
    _KanaRow(
      kana: [
        _KanaEntry(character: 'キャ', romaji: 'kya'),
        _KanaEntry(character: 'キュ', romaji: 'kyu'),
        _KanaEntry(character: 'キョ', romaji: 'kyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ギャ', romaji: 'gya'),
        _KanaEntry(character: 'ギュ', romaji: 'gyu'),
        _KanaEntry(character: 'ギョ', romaji: 'gyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'シャ', romaji: 'sha'),
        _KanaEntry(character: 'シュ', romaji: 'shu'),
        _KanaEntry(character: 'ショ', romaji: 'sho'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ジャ', romaji: 'ja'),
        _KanaEntry(character: 'ジュ', romaji: 'ju'),
        _KanaEntry(character: 'ジョ', romaji: 'jo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'チャ', romaji: 'cha'),
        _KanaEntry(character: 'チュ', romaji: 'chu'),
        _KanaEntry(character: 'チョ', romaji: 'cho'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ヂャ', romaji: 'ja'),
        _KanaEntry(character: 'ヂュ', romaji: 'ju'),
        _KanaEntry(character: 'ヂョ', romaji: 'jo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ニャ', romaji: 'nya'),
        _KanaEntry(character: 'ニュ', romaji: 'nyu'),
        _KanaEntry(character: 'ニョ', romaji: 'nyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ヒャ', romaji: 'hya'),
        _KanaEntry(character: 'ヒュ', romaji: 'hyu'),
        _KanaEntry(character: 'ヒョ', romaji: 'hyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ビャ', romaji: 'bya'),
        _KanaEntry(character: 'ビュ', romaji: 'byu'),
        _KanaEntry(character: 'ビョ', romaji: 'byo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ピャ', romaji: 'pya'),
        _KanaEntry(character: 'ピュ', romaji: 'pyu'),
        _KanaEntry(character: 'ピョ', romaji: 'pyo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'ミャ', romaji: 'mya'),
        _KanaEntry(character: 'ミュ', romaji: 'myu'),
        _KanaEntry(character: 'ミョ', romaji: 'myo'),
      ],
    ),
    _KanaRow(
      kana: [
        _KanaEntry(character: 'リャ', romaji: 'rya'),
        _KanaEntry(character: 'リュ', romaji: 'ryu'),
        _KanaEntry(character: 'リョ', romaji: 'ryo'),
      ],
    ),
  ];

  @override
  State<KanaPage> createState() => _KanaPageState();
}

class _KanaPageState extends State<KanaPage> {
  bool showKatakana = false;
  bool isSelectingKana = false;

  final Set<String> selectedKanaCharacters = <String>{};

  void _setScript(bool katakana) {
    if (showKatakana == katakana) return;

    setState(() {
      showKatakana = katakana;
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      if (isSelectingKana) {
        isSelectingKana = false;
        selectedKanaCharacters.clear();
      } else {
        isSelectingKana = true;
      }
    });
  }

  void _handleKanaTap(_KanaEntry kana) {
    if (!isSelectingKana) {
      _openKanaDetail(kana);
      return;
    }

    setState(() {
      if (!selectedKanaCharacters.add(kana.character)) {
        selectedKanaCharacters.remove(kana.character);
      }
    });
  }

  List<KanaStudyItem> _selectedStudyItems() {
    final items = <KanaStudyItem>[];

    for (final entry in _allKanaForScript(katakana: false)) {
      if (selectedKanaCharacters.contains(entry.character)) {
        items.add(
          KanaStudyItem(
            character: entry.character,
            romaji: entry.romaji,
            isKatakana: false,
          ),
        );
      }
    }

    for (final entry in _allKanaForScript(katakana: true)) {
      if (selectedKanaCharacters.contains(entry.character)) {
        items.add(
          KanaStudyItem(
            character: entry.character,
            romaji: entry.romaji,
            isKatakana: true,
          ),
        );
      }
    }

    return items;
  }

  List<KanaStudyItem> _allStudyItems() {
    return [
      ..._allKanaForScript(katakana: false).map(
        (entry) => KanaStudyItem(
          character: entry.character,
          romaji: entry.romaji,
          isKatakana: false,
        ),
      ),
      ..._allKanaForScript(katakana: true).map(
        (entry) => KanaStudyItem(
          character: entry.character,
          romaji: entry.romaji,
          isKatakana: true,
        ),
      ),
    ];
  }

  void _startSelectedKanaStudy() {
    final items = _selectedStudyItems();
    if (items.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => KanaStudyPage(
          items: items,
          answerPool: _allStudyItems(),
        ),
      ),
    );
  }

  Widget _topBarSelectionControl() {
    return SizedBox(
      width: 88,
      height: GakujiTopBar.buttonSize,
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _toggleSelectionMode,
          style: TextButton.styleFrom(
            foregroundColor: GakujiColors.reading,
            minimumSize: const Size(80, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: Text(
            isSelectingKana ? 'Cancel' : 'Select',
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  List<_KanaEntry> _flattenKanaRows(List<_KanaRow> rows) {
    return rows
        .expand((row) => row.kana)
        .whereType<_KanaEntry>()
        .toList(growable: false);
  }

  List<_KanaEntry> _allKanaForScript({required bool katakana}) {
    final rows = katakana
        ? [
            ...KanaPage.katakanaRows,
            ...KanaPage.katakanaDakuonRows,
            ...KanaPage.katakanaYoonRows,
          ]
        : [
            ...KanaPage.hiraganaRows,
            ...KanaPage.hiraganaDakuonRows,
            ...KanaPage.hiraganaYoonRows,
          ];

    return _flattenKanaRows(rows);
  }

  void _openKanaDetail(_KanaEntry selectedKana) {
    final kanaEntries = _allKanaForScript(katakana: showKatakana);
    final counterpartEntries = _allKanaForScript(katakana: !showKatakana);

    final initialIndex = kanaEntries.indexWhere(
      (entry) =>
          entry.character == selectedKana.character &&
          entry.romaji == selectedKana.romaji,
    );

    if (initialIndex < 0 || counterpartEntries.length != kanaEntries.length) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.56),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.80,
          child: _KanaDetailSheet(
            kanaEntries: kanaEntries,
            counterpartEntries: counterpartEntries,
            initialIndex: initialIndex,
            isKatakana: showKatakana,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final basicRows =
        showKatakana ? KanaPage.katakanaRows : KanaPage.hiraganaRows;
    final dakuonRows = showKatakana
        ? KanaPage.katakanaDakuonRows
        : KanaPage.hiraganaDakuonRows;
    final yoonRows =
        showKatakana ? KanaPage.katakanaYoonRows : KanaPage.hiraganaYoonRows;

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: GakujiColors.warmBackground,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                GakujiTopBar(
                  leftIcon: GakujiTopBar.backIcon,
                  leftIconSize: GakujiTopBar.backIconSize,
                  leftIconColor: GakujiColors.darkGray,
                  onLeftTap: () => Navigator.of(context).pop(),
                  rightWidget: _topBarSelectionControl(),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _KanaScriptSwitcher(
                    showKatakana: showKatakana,
                    onHiraganaTap: () => _setScript(false),
                    onKatakanaTap: () => _setScript(true),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      top: 22,
                      bottom: GakujiSpacing.pageBottom +
                          (isSelectingKana ? 92 : 0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeOut,
                          child: Column(
                            key: ValueKey(showKatakana),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _KanaSectionHeader(
                                label: 'Gojūon (basic kana)',
                              ),
                              const SizedBox(height: 15),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _KanaChart(
                                  rows: basicRows,
                                  selectionMode: isSelectingKana,
                                  selectedCharacters: selectedKanaCharacters,
                                  onKanaTap: _handleKanaTap,
                                ),
                              ),
                              const SizedBox(height: 28),
                              const _KanaSectionHeader(
                                label: 'Dakuon & Handakuon',
                              ),
                              const SizedBox(height: 15),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _KanaChart(
                                  rows: dakuonRows,
                                  selectionMode: isSelectingKana,
                                  selectedCharacters: selectedKanaCharacters,
                                  onKanaTap: _handleKanaTap,
                                ),
                              ),
                              const SizedBox(height: 28),
                              const _KanaSectionHeader(label: 'Yōon'),
                              const SizedBox(height: 15),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _KanaChart(
                                  rows: yoonRows,
                                  centerRows: true,
                                  selectionMode: isSelectingKana,
                                  selectedCharacters: selectedKanaCharacters,
                                  onKanaTap: _handleKanaTap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: 20,
              right: 20,
              bottom: isSelectingKana ? bottomInset + 14 : -96,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: isSelectingKana ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !isSelectingKana,
                  child: _KanaStudyActionButton(
                    itemCount: selectedKanaCharacters.length,
                    onTap: _startSelectedKanaStudy,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanaStudyActionButton extends StatelessWidget {
  final int itemCount;
  final VoidCallback onTap;

  const _KanaStudyActionButton({
    required this.itemCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = itemCount > 0;
    const foregroundColor = Colors.white;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.42,
      child: SizedBox(
        width: double.infinity,
        height: 66,
        child: Material(
          color: GakujiColors.reading,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            splashColor: foregroundColor.withValues(alpha: 0.10),
            highlightColor: foregroundColor.withValues(alpha: 0.05),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Study',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: foregroundColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KanaScriptSwitcher extends StatelessWidget {
  final bool showKatakana;
  final VoidCallback onHiraganaTap;
  final VoidCallback onKatakanaTap;

  const _KanaScriptSwitcher({
    required this.showKatakana,
    required this.onHiraganaTap,
    required this.onKatakanaTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final indicatorWidth = constraints.maxWidth / 2;

        return SizedBox(
          height: 58,
          child: Stack(
            children: [
              Positioned.fill(
                bottom: 6,
                child: Row(
                  children: [
                    Expanded(
                      child: _KanaScriptTab(
                        label: 'Hiragana',
                        isSelected: !showKatakana,
                        onTap: onHiraganaTap,
                      ),
                    ),
                    Expanded(
                      child: _KanaScriptTab(
                        label: 'Katakana',
                        isSelected: showKatakana,
                        onTap: onKatakanaTap,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 2,
                  color: GakujiColors.softBorder,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: showKatakana
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: indicatorWidth,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GakujiColors.reading,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanaScriptTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _KanaScriptTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          style: GakujiText.large.copyWith(
            fontSize: 27,
            color: isSelected ? GakujiColors.reading : GakujiColors.darkGray,
          ),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}

class _KanaSectionHeader extends StatelessWidget {
  final String label;

  const _KanaSectionHeader({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1,
              color: GakujiColors.darkGray,
            ),
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            thickness: 1,
            color: GakujiColors.softBorder,
          ),
        ],
      ),
    );
  }
}

class _KanaChart extends StatelessWidget {
  final List<_KanaRow> rows;
  final bool centerRows;
  final bool selectionMode;
  final Set<String> selectedCharacters;
  final ValueChanged<_KanaEntry> onKanaTap;

  const _KanaChart({
    super.key,
    required this.rows,
    this.centerRows = false,
    required this.selectionMode,
    required this.selectedCharacters,
    required this.onKanaTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const rowGap = 12.0;
        const kanaDominoScale = 0.88;

        return Column(
          children: List.generate(rows.length, (rowIndex) {
            final row = rows[rowIndex];

            return Padding(
              padding: EdgeInsets.only(
                bottom: rowIndex == rows.length - 1 ? 0 : rowGap,
              ),
              child: Row(
                mainAxisAlignment: centerRows
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: List.generate(row.kana.length, (columnIndex) {
                  final kana = row.kana[columnIndex];

                  return Padding(
                    padding: centerRows
                        ? EdgeInsets.only(
                            right: columnIndex == row.kana.length - 1 ? 0 : 12,
                          )
                        : EdgeInsets.zero,
                    child: SizedBox(
                      width: GakujiDomino.width,
                      height: GakujiDomino.height,
                      child: kana == null
                          ? const SizedBox.shrink()
                          : Center(
                              child: Transform.scale(
                                scale: kanaDominoScale,
                                child: GakujiDomino(
                                  text: kana.character,
                                  footerText: kana.romaji,
                                  selected: selectionMode &&
                                      selectedCharacters.contains(
                                        kana.character,
                                      ),
                                  selectionColor: GakujiColors.reading,
                                  onTap: () => onKanaTap(kana),
                                ),
                              ),
                            ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }
}


class _KanaDetailSheet extends StatefulWidget {
  final List<_KanaEntry> kanaEntries;
  final List<_KanaEntry> counterpartEntries;
  final int initialIndex;
  final bool isKatakana;

  const _KanaDetailSheet({
    required this.kanaEntries,
    required this.counterpartEntries,
    required this.initialIndex,
    required this.isKatakana,
  });

  @override
  State<_KanaDetailSheet> createState() => _KanaDetailSheetState();
}

class _KanaDetailSheetState extends State<_KanaDetailSheet> {
  late int currentIndex;
  late bool showingKatakana;

  bool isWritingMode = false;
  bool showReference = true;
  bool showStrokeAnimation = false;
  int animationRunId = 0;

  final List<List<WritingPoint>> practiceStrokes = [];

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    showingKatakana = widget.isKatakana;
  }

  List<_KanaEntry> get _currentEntries {
    return showingKatakana == widget.isKatakana
        ? widget.kanaEntries
        : widget.counterpartEntries;
  }

  List<_KanaEntry> get _counterpartEntries {
    return showingKatakana == widget.isKatakana
        ? widget.counterpartEntries
        : widget.kanaEntries;
  }

  void _showPreviousKana() {
    if (isWritingMode) return;

    setState(() {
      currentIndex =
          (currentIndex - 1 + _currentEntries.length) % _currentEntries.length;
      animationRunId++;
    });
  }

  void _showNextKana() {
    if (isWritingMode) return;

    setState(() {
      currentIndex = (currentIndex + 1) % _currentEntries.length;
      animationRunId++;
    });
  }

  void _showCounterpart() {
    if (isWritingMode) return;

    setState(() {
      showingKatakana = !showingKatakana;
      animationRunId++;
    });
  }

  void _toggleWritingMode() {
    setState(() {
      isWritingMode = !isWritingMode;
      practiceStrokes.clear();
      showStrokeAnimation = false;

      if (isWritingMode) {
        showReference = true;
      }
    });
  }

  void _toggleReference() {
    if (!isWritingMode) return;

    setState(() {
      showReference = !showReference;
    });
  }

  void _clearPracticeStrokes() {
    if (!isWritingMode || practiceStrokes.isEmpty) return;

    setState(() {
      practiceStrokes.clear();
    });
  }

  void _playStrokeAnimation() {
    if (!isWritingMode) return;

    setState(() {
      showStrokeAnimation = true;
      animationRunId++;
    });
  }

  void _finishStrokeAnimation() {
    if (!mounted || !showStrokeAnimation) return;

    setState(() {
      showStrokeAnimation = false;
    });
  }

  void _addPracticeStroke(Offset point, {bool isStart = false}) {
    final writingPoint = WritingPoint.fromOffset(
      x: point.dx,
      y: point.dy,
      time: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      if (isStart || practiceStrokes.isEmpty) {
        practiceStrokes.add(<WritingPoint>[writingPoint]);
      } else {
        practiceStrokes.last.add(writingPoint);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final kana = _currentEntries[currentIndex];
    final counterpart = _counterpartEntries[currentIndex];
    final scriptLabel = showingKatakana ? 'Katakana' : 'Hiragana';
    final counterpartLabel = showingKatakana ? 'Hiragana' : 'Katakana';

    final mediaQuery = MediaQuery.of(context);
    final bottomSafePadding =
        mediaQuery.padding.bottom > 0 ? mediaQuery.padding.bottom + 14.0 : 24.0;

    return Material(
      color: GakujiColors.warmBackground,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 9, 20, bottomSafePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _closeButton(context),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                scriptLabel,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: GakujiColors.mediumGray,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  child: Column(
                    key: ValueKey(
                      '${isWritingMode ? 'write' : 'demo'}_'
                      '${showingKatakana}_${kana.character}',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isWritingMode)
                        _KanaWritingPracticeCanvas(
                          character: kana.character,
                          strokes: practiceStrokes,
                          showReference: showReference,
                          showStrokeAnimation: showStrokeAnimation,
                          animationRunId: animationRunId,
                          onStrokeAnimationComplete: _finishStrokeAnimation,
                          onStrokeStart: (point) {
                            _addPracticeStroke(point, isStart: true);
                          },
                          onStrokeUpdate: _addPracticeStroke,
                        )
                      else
                        _fontCharacter(kana.character),
                      const SizedBox(height: 14),
                      Text(
                        kana.romaji,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: GakujiColors.mediumGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _detailActionRow(
              counterpartLabel: counterpartLabel,
              counterpart: counterpart,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 56,
              child: isWritingMode
                  ? const SizedBox.expand()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _navigationButton(
                          icon: Icons.chevron_left_rounded,
                          onTap: _showPreviousKana,
                        ),
                        _navigationButton(
                          icon: Icons.chevron_right_rounded,
                          onTap: _showNextKana,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailActionRow({
    required String counterpartLabel,
    required _KanaEntry counterpart,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 50,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!isWritingMode) ...[
              Expanded(
                child: _counterpartButton(
                  label: '$counterpartLabel → ${counterpart.character}',
                  onTap: _showCounterpart,
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              _modeControlButton(
                icon: Icons.refresh_rounded,
                active: false,
                onTap: _clearPracticeStrokes,
              ),
              const Spacer(),
              _modeControlButton(
                icon: Icons.play_arrow_rounded,
                active: showStrokeAnimation,
                onTap: _playStrokeAnimation,
              ),
              const SizedBox(width: 2),
              _modeControlButton(
                icon: showReference
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                active: showReference,
                onTap: _toggleReference,
              ),
              const SizedBox(width: 2),
            ],
            _modeControlButton(
              icon: Icons.edit_rounded,
              active: isWritingMode,
              onTap: _toggleWritingMode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeControlButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          splashColor: GakujiColors.reading.withValues(alpha: 0.08),
          highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
          child: Icon(
            icon,
            size: 29,
            color: active
                ? GakujiColors.reading
                : GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }

  Widget _fontCharacter(String character) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Center(
        child: SizedBox(
          width: 220,
          height: 220,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              character,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: character.runes.length > 1 ? 112 : 170,
                height: 1,
                fontWeight: FontWeight.w400,
                color: GakujiColors.darkGray,
                fontFamily: GakujiFonts.japanese,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _counterpartButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: GakujiColors.reading.withValues(alpha: 0.08),
        highlightColor: GakujiColors.reading.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 18,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: GakujiColors.reading,
              fontFamily: GakujiFonts.japanese,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: GakujiColors.softGray,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isWritingMode
              ? _toggleWritingMode
              : () => Navigator.of(context).pop(),
          child: Icon(
            isWritingMode
                ? Icons.chevron_left_rounded
                : Icons.close_rounded,
            size: isWritingMode ? 40 : 34,
            color: GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }

  Widget _navigationButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            size: 52,
            color: GakujiColors.mediumGray,
          ),
        ),
      ),
    );
  }
}

class _KanaWritingPracticeCanvas extends StatelessWidget {
  final String character;
  final List<List<WritingPoint>> strokes;
  final bool showReference;
  final bool showStrokeAnimation;
  final int animationRunId;
  final VoidCallback onStrokeAnimationComplete;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;

  const _KanaWritingPracticeCanvas({
    required this.character,
    required this.strokes,
    required this.showReference,
    required this.showStrokeAnimation,
    required this.animationRunId,
    required this.onStrokeAnimationComplete,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Container(
        decoration: BoxDecoration(
          color: GakujiColors.whiteCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: GakujiColors.warmDivider,
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Opacity(
                      opacity: showReference ? 1 : 0,
                      child: _KanaStaticReference(character: character),
                    ),
                  ),
                ),
              ),
              if (showStrokeAnimation)
                Positioned.fill(
                  child: Center(
                    child: _KanaStrokeAnimation(
                      key: ValueKey(
                        'practice_stroke_${character}_$animationRunId',
                      ),
                      character: character,
                      showGuide: !showReference,
                      onCompleted: onStrokeAnimationComplete,
                    ),
                  ),
                ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        final box = context.findRenderObject() as RenderBox;
                        final point = box.globalToLocal(details.globalPosition);
                        onStrokeStart(point);
                      },
                      onPanUpdate: (details) {
                        final box = context.findRenderObject() as RenderBox;
                        final point = box.globalToLocal(details.globalPosition);
                        onStrokeUpdate(point);
                      },
                      child: CustomPaint(
                        painter: _KanaWritingPracticePainter(strokes),
                        child: const SizedBox.expand(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KanaWritingPracticePainter extends CustomPainter {
  final List<List<WritingPoint>> strokes;

  const _KanaWritingPracticePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = GakujiColors.darkGray
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final grid = Paint()
      ..color = GakujiColors.warmDivider
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      grid,
    );

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      grid,
    );

    for (final stroke in strokes) {
      for (var index = 0; index < stroke.length - 1; index++) {
        canvas.drawLine(
          Offset(stroke[index].x, stroke[index].y),
          Offset(stroke[index + 1].x, stroke[index + 1].y),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KanaWritingPracticePainter oldDelegate) => true;
}

class _KanaStaticReference extends StatefulWidget {
  final String character;

  const _KanaStaticReference({required this.character});

  @override
  State<_KanaStaticReference> createState() => _KanaStaticReferenceState();
}

class _KanaStaticReferenceState extends State<_KanaStaticReference> {
  List<KanjiStrokeData> strokeData = const [];
  bool isLoading = true;
  int loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadStrokeData();
  }

  @override
  void didUpdateWidget(covariant _KanaStaticReference oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.character != widget.character) {
      _loadStrokeData();
    }
  }

  Future<void> _loadStrokeData() async {
    final requestId = ++loadRequestId;

    if (mounted) {
      setState(() {
        isLoading = true;
        strokeData = const [];
      });
    }

    final loaded = <KanjiStrokeData>[];

    for (final rune in widget.character.runes) {
      final character = String.fromCharCode(rune);
      final data = await DictionaryService.getCharacterStrokeData(character);

      if (requestId != loadRequestId) return;

      if (data == null || data.isEmpty) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
          strokeData = const [];
        });
        return;
      }

      loaded.add(data);
    }

    if (!mounted || requestId != loadRequestId) return;

    setState(() {
      isLoading = false;
      strokeData = loaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox.expand();
    }

    if (strokeData.isEmpty) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.character,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: widget.character.runes.length > 1 ? 105 : 165,
              height: 1,
              fontWeight: FontWeight.w400,
              color: GakujiColors.mediumGray.withValues(alpha: 0.20),
              fontFamily: GakujiFonts.japanese,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: strokeData.map((data) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: strokeData.length > 1 ? 2 : 0,
            ),
            child: CustomPaint(
              painter: _KanaStrokePainter(
                data: data,
                localTimeline: -1,
                strokeTimelineUnits: 1.15,
                showGuide: true,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _KanaStrokeAnimation extends StatefulWidget {
  final String character;
  final bool showGuide;
  final VoidCallback? onCompleted;

  const _KanaStrokeAnimation({
    super.key,
    required this.character,
    this.showGuide = true,
    this.onCompleted,
  });

  @override
  State<_KanaStrokeAnimation> createState() => _KanaStrokeAnimationState();
}

class _KanaStrokeAnimationState extends State<_KanaStrokeAnimation>
    with SingleTickerProviderStateMixin {
  static const double _strokeTimelineUnits = 1.15;
  static const int _strokeDrawMilliseconds = 820;
  static const int _strokePauseMilliseconds = 120;
  static const Duration _startPause = Duration(milliseconds: 260);
  static const Duration _endPause = Duration(milliseconds: 420);

  late final AnimationController _controller;

  List<KanjiStrokeData> strokeData = const [];
  bool isLoading = true;
  int loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadStrokeData();
  }

  @override
  void didUpdateWidget(covariant _KanaStrokeAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.character != widget.character) {
      _loadStrokeData();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStrokeData() async {
    final requestId = ++loadRequestId;

    _controller.stop();
    _controller.value = 0;

    if (mounted) {
      setState(() {
        isLoading = true;
        strokeData = const [];
      });
    }

    final loaded = <KanjiStrokeData>[];

    for (final rune in widget.character.runes) {
      final character = String.fromCharCode(rune);
      final data = await DictionaryService.getCharacterStrokeData(character);

      if (requestId != loadRequestId) return;

      if (data == null || data.isEmpty) {
        if (!mounted) return;

        setState(() {
          isLoading = false;
          strokeData = const [];
        });

        widget.onCompleted?.call();
        return;
      }

      loaded.add(data);
    }

    if (!mounted || requestId != loadRequestId) return;

    final totalStrokes = loaded.fold<int>(
      0,
      (total, data) => total + data.strokeCount,
    );
    final pauseCount = (totalStrokes - 1).clamp(0, totalStrokes).toInt();
    final totalDuration =
        (totalStrokes * _strokeDrawMilliseconds) +
        (pauseCount * _strokePauseMilliseconds);

    setState(() {
      isLoading = false;
      strokeData = loaded;
    });

    _controller.duration = Duration(milliseconds: totalDuration);

    await Future<void>.delayed(_startPause);

    if (!mounted || requestId != loadRequestId) return;

    await _controller.forward(from: 0);

    if (!mounted || requestId != loadRequestId) return;

    await Future<void>.delayed(_endPause);

    if (!mounted || requestId != loadRequestId) return;

    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 220,
        height: 220,
      );
    }

    if (strokeData.isEmpty) {
      return _fallbackCharacter(color: GakujiColors.darkGray);
    }

    final totalStrokes = strokeData.fold<int>(
      0,
      (total, data) => total + data.strokeCount,
    );
    final totalTimeline = totalStrokes <= 1
        ? 1.0
        : ((totalStrokes - 1) * _strokeTimelineUnits) + 1.0;

    return SizedBox(
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final timelineProgress = _controller.value * totalTimeline;
          var timelineOffset = 0.0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: strokeData.map((data) {
              final localTimeline = timelineProgress - timelineOffset;
              timelineOffset += data.strokeCount * _strokeTimelineUnits;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: strokeData.length > 1 ? 2 : 0,
                  ),
                  child: CustomPaint(
                    painter: _KanaStrokePainter(
                      data: data,
                      localTimeline: localTimeline,
                      strokeTimelineUnits: _strokeTimelineUnits,
                      showGuide: widget.showGuide,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _fallbackCharacter({required Color color}) {
    return SizedBox(
      width: 220,
      height: 220,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.character,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: widget.character.runes.length > 1 ? 112 : 170,
            height: 1,
            fontWeight: FontWeight.w400,
            color: color,
            fontFamily: GakujiFonts.japanese,
          ),
        ),
      ),
    );
  }
}

class _KanaStrokePainter extends CustomPainter {
  static const Color _strokeColor = Color(0xFF111111);
  static const Color _strokeDotColor = Color(0xFFC51F1A);

  final KanjiStrokeData data;
  final double localTimeline;
  final double strokeTimelineUnits;
  final bool showGuide;

  const _KanaStrokePainter({
    required this.data,
    required this.localTimeline,
    required this.strokeTimelineUnits,
    required this.showGuide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final viewBox = _parseViewBox(data.viewBox);
    final scale = (size.width / viewBox.width) < (size.height / viewBox.height)
        ? size.width / viewBox.width
        : size.height / viewBox.height;
    final drawWidth = viewBox.width * scale;
    final drawHeight = viewBox.height * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, scale);
    canvas.translate(-viewBox.left, -viewBox.top);

    final guidePaint = Paint()
      ..color = GakujiColors.mediumGray.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final strokePaint = Paint()
      ..color = _strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = _strokeDotColor
      ..style = PaintingStyle.fill;

    final parsedPaths = data.strokes
        .map((stroke) => _SvgPathParser.parse(stroke.pathData))
        .toList(growable: false);

    if (showGuide) {
      for (final path in parsedPaths) {
        canvas.drawPath(path, guidePaint);
      }
    }

    Offset? activeDot;

    for (var index = 0; index < parsedPaths.length; index++) {
      final path = parsedPaths[index];
      final strokeStart = index * strokeTimelineUnits;
      final fraction = (localTimeline - strokeStart).clamp(0.0, 1.0).toDouble();

      if (fraction <= 0) continue;

      if (fraction >= 1) {
        canvas.drawPath(path, strokePaint);
        continue;
      }

      final partial = _extractPartialPath(path, fraction);
      canvas.drawPath(partial.path, strokePaint);
      activeDot = partial.endPoint;
    }

    if (activeDot != null) {
      canvas.drawCircle(activeDot, 3.25, dotPaint);
    }

    canvas.restore();
  }

  _KanaPartialPath _extractPartialPath(Path path, double fraction) {
    final metrics = path.computeMetrics(forceClosed: false).toList();

    if (metrics.isEmpty) {
      return _KanaPartialPath(path: Path(), endPoint: null);
    }

    final totalLength = metrics.fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    var remaining = totalLength * fraction;
    final partial = Path();
    Offset? endPoint;

    for (final metric in metrics) {
      if (remaining <= 0) break;

      final take = remaining.clamp(0.0, metric.length).toDouble();
      partial.addPath(metric.extractPath(0, take), Offset.zero);

      if (take > 0) {
        endPoint = metric.getTangentForOffset(take)?.position;
      }

      remaining -= take;
    }

    return _KanaPartialPath(path: partial, endPoint: endPoint);
  }

  Rect _parseViewBox(String rawViewBox) {
    final values = rawViewBox
        .trim()
        .split(RegExp(r'[ ,]+'))
        .map(double.tryParse)
        .whereType<double>()
        .toList(growable: false);

    if (values.length != 4 || values[2] <= 0 || values[3] <= 0) {
      return const Rect.fromLTWH(0, 0, 109, 109);
    }

    return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
  }

  @override
  bool shouldRepaint(covariant _KanaStrokePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.localTimeline != localTimeline ||
        oldDelegate.strokeTimelineUnits != strokeTimelineUnits ||
        oldDelegate.showGuide != showGuide;
  }
}

class _KanaPartialPath {
  final Path path;
  final Offset? endPoint;

  const _KanaPartialPath({
    required this.path,
    required this.endPoint,
  });
}

class _SvgPathParser {
  static final RegExp _tokenPattern = RegExp(
    r'[AaCcHhLlMmQqSsTtVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  );

  static Path parse(String pathData) {
    final tokens = _tokenPattern
        .allMatches(pathData)
        .map((match) => match.group(0)!)
        .toList(growable: false);

    final path = Path();
    var index = 0;
    var command = '';
    var current = Offset.zero;
    var subPathStart = Offset.zero;
    Offset? lastCubicControl;
    Offset? lastQuadraticControl;
    String? previousCommand;

    bool isCommand(String token) {
      return token.length == 1 && RegExp(r'[A-Za-z]').hasMatch(token);
    }

    double nextNumber() {
      if (index >= tokens.length || isCommand(tokens[index])) return 0;
      return double.tryParse(tokens[index++]) ?? 0;
    }

    Offset point(double x, double y, bool relative) {
      return relative ? current + Offset(x, y) : Offset(x, y);
    }

    while (index < tokens.length) {
      if (isCommand(tokens[index])) {
        command = tokens[index++];
      } else if (command.isEmpty) {
        index++;
        continue;
      }

      final relative = command == command.toLowerCase();
      final upper = command.toUpperCase();

      switch (upper) {
        case 'M':
          if (index + 1 >= tokens.length) break;
          final next = point(nextNumber(), nextNumber(), relative);
          path.moveTo(next.dx, next.dy);
          current = next;
          subPathStart = next;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          command = relative ? 'l' : 'L';
          break;
        case 'L':
          if (index + 1 >= tokens.length) break;
          final next = point(nextNumber(), nextNumber(), relative);
          path.lineTo(next.dx, next.dy);
          current = next;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'H':
          final x = nextNumber();
          current = Offset(relative ? current.dx + x : x, current.dy);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'V':
          final y = nextNumber();
          current = Offset(current.dx, relative ? current.dy + y : y);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'C':
          final control1 = point(nextNumber(), nextNumber(), relative);
          final control2 = point(nextNumber(), nextNumber(), relative);
          final next = point(nextNumber(), nextNumber(), relative);
          path.cubicTo(
            control1.dx,
            control1.dy,
            control2.dx,
            control2.dy,
            next.dx,
            next.dy,
          );
          current = next;
          lastCubicControl = control2;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'S':
          final hasPreviousCubic = previousCommand != null &&
              const {'C', 'c', 'S', 's'}.contains(previousCommand);
          final reflectedControl = hasPreviousCubic && lastCubicControl != null
              ? (current * 2) - lastCubicControl!
              : current;
          final control2 = point(nextNumber(), nextNumber(), relative);
          final next = point(nextNumber(), nextNumber(), relative);
          path.cubicTo(
            reflectedControl.dx,
            reflectedControl.dy,
            control2.dx,
            control2.dy,
            next.dx,
            next.dy,
          );
          current = next;
          lastCubicControl = control2;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'Q':
          final control = point(nextNumber(), nextNumber(), relative);
          final next = point(nextNumber(), nextNumber(), relative);
          path.quadraticBezierTo(control.dx, control.dy, next.dx, next.dy);
          current = next;
          lastQuadraticControl = control;
          lastCubicControl = null;
          previousCommand = command;
          break;
        case 'T':
          final hasPreviousQuadratic = previousCommand != null &&
              const {'Q', 'q', 'T', 't'}.contains(previousCommand);
          final control = hasPreviousQuadratic && lastQuadraticControl != null
              ? (current * 2) - lastQuadraticControl!
              : current;
          final next = point(nextNumber(), nextNumber(), relative);
          path.quadraticBezierTo(control.dx, control.dy, next.dx, next.dy);
          current = next;
          lastQuadraticControl = control;
          lastCubicControl = null;
          previousCommand = command;
          break;
        case 'A':
          nextNumber();
          nextNumber();
          nextNumber();
          nextNumber();
          nextNumber();
          final next = point(nextNumber(), nextNumber(), relative);
          path.lineTo(next.dx, next.dy);
          current = next;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          break;
        case 'Z':
          path.close();
          current = subPathStart;
          lastCubicControl = null;
          lastQuadraticControl = null;
          previousCommand = command;
          command = '';
          break;
        default:
          command = '';
          break;
      }
    }

    return path;
  }
}

class _KanaRow {
  final List<_KanaEntry?> kana;

  const _KanaRow({
    required this.kana,
  });
}

class _KanaEntry {
  final String character;
  final String romaji;

  const _KanaEntry({
    required this.character,
    required this.romaji,
  });
}
