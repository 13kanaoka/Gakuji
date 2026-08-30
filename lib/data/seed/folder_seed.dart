import 'package:gakuji/domain/folder.dart';

List<Folder> buildSampleFolders() {
  return [
    Folder(id: 'f1', name: 'JLPT', deckIds: ['d1', 'd2']),
    Folder(id: 'f2', name: 'School', deckIds: []),
    Folder(id: 'f3', name: 'Work', deckIds: []),
    Folder(id: 'f4', name: 'Favorites', deckIds: []),
    Folder(id: 'f5', name: 'Archive', deckIds: []),
    Folder(id: 'f6', name: 'Custom', deckIds: []),
  ];
}

final List<Folder> folders = buildSampleFolders();
