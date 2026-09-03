



extension IntNullableExtensions on int? {
  int orZero() {
    return this ?? 0;
  }
}