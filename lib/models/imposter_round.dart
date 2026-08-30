import 'package:gakuji/models/term.dart';

class IdentityFile {
  final String reading;
  final String definition;
  final String partOfSpeech;

  const IdentityFile({
    required this.reading,
    required this.definition,
    required this.partOfSpeech,
  });
}

class ImposterRound {
  final Term visitor;
  final IdentityFile file;
  final bool isValid;

  const ImposterRound({
    required this.visitor,
    required this.file,
    required this.isValid,
  });
}