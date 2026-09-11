import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/setlists/models/setlist_song.dart';
import 'package:bandroadie/features/setlists/widgets/reorderable_song_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

const _sharedWidths = SongMetricsSharedWidths(
  bpmWidth: 70,
  durationWidth: 50,
  keyWidth: 50,
  tuningWidth: 100,
);

Future<void> _pumpCard(WidgetTester tester, SetlistSong song) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: FTheme(
        data: AppTheme.foruiTheme(Brightness.dark),
        child: Scaffold(
          body: ReorderableSongCard(
            key: const ValueKey('song-card'),
            song: song,
            index: 0,
            sharedWidths: _sharedWidths,
            isDraggable: false,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('removes tuning badge when the song tuning is cleared',
      (tester) async {
    const tunedSong = SetlistSong(
      id: 'song-1',
      title: 'Test Song',
      artist: 'Test Artist',
      tuning: 'standard_e',
      durationSeconds: 180,
      position: 0,
    );

    await _pumpCard(tester, tunedSong);
    expect(find.text('Standard'), findsOneWidget);

    const clearedSong = SetlistSong(
      id: 'song-1',
      title: 'Test Song',
      artist: 'Test Artist',
      durationSeconds: 180,
      position: 0,
    );
    await _pumpCard(tester, clearedSong);

    expect(find.text('Standard'), findsNothing);
  });
}
