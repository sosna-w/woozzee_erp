class BatchDetail {
  final int boxesCount;
  final int qtyInBox;

  BatchDetail({required this.boxesCount, required this.qtyInBox});

  int get total => boxesCount * qtyInBox;
}

class BatchEntry {
  int total = 0;
  final List<BatchDetail> details = [];

  void addDetail(BatchDetail detail) {
    details.add(detail);
    total += detail.total;
  }
}