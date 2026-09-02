import 'dart:math';

/// Deterministic 5x5 Bingo board used by the offline game protocol.
///
/// The generation algorithm intentionally preserves the original Bingo app
/// behavior: shuffle 1..75 with a seed derived from game/player IDs, take the
/// first 24 values, and reserve the center cell as FREE. Changing this would
/// change existing reproducible boards for the same game/player pair.
class BingoBoard {
  BingoBoard._({required this.cells, required this.marked});

  factory BingoBoard.generate({required int gameId, required int playerId}) {
    final random = Random(gameId * 1000 + playerId);
    final numbers = List<int>.generate(75, (index) => index + 1)
      ..shuffle(random);
    final picked = numbers.take(24).toList(growable: false);
    var cursor = 0;
    final cells = List<List<int?>>.generate(
      5,
      (row) => List<int?>.generate(5, (column) {
        if (row == 2 && column == 2) return null;
        return picked[cursor++];
      }),
    );
    final marked = List<List<bool>>.generate(
      5,
      (_) => List<bool>.filled(5, false),
    );
    marked[2][2] = true;
    return BingoBoard._(cells: cells, marked: marked);
  }

  final List<List<int?>> cells;
  final List<List<bool>> marked;

  bool mark(int number) {
    var changed = false;
    for (var row = 0; row < 5; row++) {
      for (var column = 0; column < 5; column++) {
        if (cells[row][column] == number && !marked[row][column]) {
          marked[row][column] = true;
          changed = true;
        }
      }
    }
    return changed;
  }

  bool get hasBingo {
    for (var row = 0; row < 5; row++) {
      if (marked[row].every((value) => value)) return true;
    }
    for (var column = 0; column < 5; column++) {
      var complete = true;
      for (var row = 0; row < 5; row++) {
        complete = complete && marked[row][column];
      }
      if (complete) return true;
    }
    var mainDiagonal = true;
    var antiDiagonal = true;
    for (var index = 0; index < 5; index++) {
      mainDiagonal = mainDiagonal && marked[index][index];
      antiDiagonal = antiDiagonal && marked[index][4 - index];
    }
    return mainDiagonal || antiDiagonal;
  }
}
