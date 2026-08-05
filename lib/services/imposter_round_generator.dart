import 'dart:math';

import '../models/imposter_round.dart';
import '../models/term.dart';

class ImposterRoundGenerator {
  final Random _random = Random();

  ImposterRound generate({
    required Term visitor,
    required List<Term> deckTerms,
  }) {
    final usableTerms = deckTerms.where(_isUsableTerm).toList();

    final otherTerms = usableTerms.where((term) {
      return !_isSameTerm(term, visitor);
    }).toList();

    if (otherTerms.isEmpty) {
      return _validRound(visitor);
    }

    final shouldBeValid = _random.nextBool();

    if (shouldBeValid) {
      return _validRound(visitor);
    }

    return _invalidRound(
      visitor: visitor,
      otherTerms: otherTerms,
    );
  }

  ImposterRound _validRound(Term visitor) {
    return ImposterRound(
      visitor: visitor,
      isValid: true,
      file: IdentityFile(
        reading: _safeValue(visitor.reading),
        definition: _definitionText(visitor),
        partOfSpeech: _safeValue(visitor.partOfSpeech),
      ),
    );
  }

  ImposterRound _invalidRound({
    required Term visitor,
    required List<Term> otherTerms,
  }) {
    final wrongSource = _chooseCompatibleSource(
      visitor: visitor,
      otherTerms: otherTerms,
    );

    final visitorPartOfSpeech = _safeValue(visitor.partOfSpeech);
    final sourcePartOfSpeech = _safeValue(wrongSource.partOfSpeech);

    final replacePartOfSpeech = visitorPartOfSpeech != sourcePartOfSpeech;
    final replaceReading = _random.nextBool();

    return ImposterRound(
      visitor: visitor,
      isValid: false,
      file: IdentityFile(
        reading: replaceReading
            ? _safeValue(wrongSource.reading)
            : _safeValue(visitor.reading),
        definition: _definitionText(wrongSource),
        partOfSpeech: replacePartOfSpeech
            ? sourcePartOfSpeech
            : visitorPartOfSpeech,
      ),
    );
  }

  Term _chooseCompatibleSource({
    required Term visitor,
    required List<Term> otherTerms,
  }) {
    final visitorPartOfSpeech = _safeValue(visitor.partOfSpeech);

    final samePartOfSpeechTerms = otherTerms.where((term) {
      return _safeValue(term.partOfSpeech) == visitorPartOfSpeech;
    }).toList();

    if (samePartOfSpeechTerms.isNotEmpty) {
      return samePartOfSpeechTerms[
          _random.nextInt(samePartOfSpeechTerms.length)];
    }

    return otherTerms[_random.nextInt(otherTerms.length)];
  }

  bool _isUsableTerm(Term term) {
    return _termDisplayText(term).isNotEmpty &&
        _safeValue(term.reading) != '—' &&
        _definitionText(term) != '—';
  }

  bool _isSameTerm(Term first, Term second) {
    return first.id == second.id ||
        (first.kanji == second.kanji &&
            first.reading == second.reading &&
            first.meaning == second.meaning);
  }

  String _termDisplayText(Term term) {
    final kanji = term.kanji.trim();

    if (kanji.isNotEmpty) return kanji;

    return term.reading.trim();
  }

  String _definitionText(Term term) {
    final meaning = term.meaning.trim();

    if (meaning.isNotEmpty) return meaning;

    return _safeValue(term.cardMeaning);
  }

  String _safeValue(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return '—';

    return trimmed;
  }
}