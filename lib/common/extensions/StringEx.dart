
extension StringEx on String? {
  bool isNotBlank() {
    return !isBlank();
  }

  bool isBlank() {
    return this != null && this!.trim().isEmpty;
  }

  bool isNullEmptyOrBlank() {
    return this == null || isEmptyOrBlank();
  }

  bool isNotEmptyOrBlank() {
    return this != null && this!.isNotEmpty && isNotBlank();
  }

  bool isNotNullEmptyOrBlank() {
    return this != null && isEmptyOrBlank();
  }

  bool isEmptyOrBlank() {
    return this!.isEmpty || isBlank();
  }

  String firstLetterToUpper() {
    if (isNullEmptyOrBlank()) return "";

    var length = this!.length;
    var firstLetter = "";

    for (int i = 0; i < length; i++) {
      if (this![i] != " ") firstLetter = this![i];
    }

    return this!.replaceFirst(firstLetter, firstLetter.toUpperCase());
  }

  String orEmpty() {
    return this ?? "";
  }
}
