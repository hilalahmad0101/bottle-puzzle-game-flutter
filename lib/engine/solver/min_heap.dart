/// Minimal binary min-heap of (priority, id). Ties break on lower id (FIFO).
final class MinHeap {
  final List<double> _f = [];
  final List<int> _id = [];

  bool get isEmpty => _id.isEmpty;

  void push(double f, int id) {
    _f.add(f);
    _id.add(id);
    var i = _id.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_less(i, p)) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _id.first;
    final lastF = _f.removeLast();
    final lastId = _id.removeLast();
    if (_id.isNotEmpty) {
      _f[0] = lastF;
      _id[0] = lastId;
      var i = 0;
      final n = _id.length;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < n && _less(l, m)) m = l;
        if (r < n && _less(r, m)) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  bool _less(int a, int b) =>
      _f[a] < _f[b] || (_f[a] == _f[b] && _id[a] < _id[b]);

  void _swap(int a, int b) {
    final tf = _f[a];
    _f[a] = _f[b];
    _f[b] = tf;
    final ti = _id[a];
    _id[a] = _id[b];
    _id[b] = ti;
  }
}
