import 'dart:collection';

extension IterableUtils<T> on Iterable<T> {
  List<T> operator -(Iterable<T> elements) => except(elements).toList();

  Iterable<T> except(Iterable<T> elements) sync* {
    for (final current in this) {
      if (!elements.contains(current)) yield current;
    }
  }

  Iterable<List<T>> windowed(
    int size, {
    int step = 1,
    bool partialWindows = false,
  }) sync* {
    final gap = step - size;
    if (gap >= 0) {
      var buffer = <T>[];
      var skip = 0;
      for (final element in this) {
        if (skip > 0) {
          skip -= 1;
          continue;
        }
        buffer.add(element);
        if (buffer.length == size) {
          yield buffer;
          buffer = <T>[];
          skip = gap;
        }
      }
      if (buffer.isNotEmpty && (partialWindows || buffer.length == size)) {
        yield buffer;
      }
    } else {
      final buffer = ListQueue<T>(size);
      for (final element in this) {
        buffer.add(element);
        if (buffer.length == size) {
          yield buffer.toList();
          for (var i = 0; i < step; i++) {
            buffer.removeFirst();
          }
        }
      }
      if (partialWindows) {
        while (buffer.length > step) {
          yield buffer.toList();
          for (var i = 0; i < step; i++) {
            buffer.removeFirst();
          }
        }
        if (buffer.isNotEmpty) {
          yield buffer.toList();
        }
      }
    }
  }
}
