class JsonConverters {
  static bool boolFromInt(int? value) {
    return value == 1;
  }

  static int boolToInt(bool value) {
    return value ? 1 : 0;
  }

  static int intFromNullableInt(int? value) {
    return value ?? 0;
  }

  static int intToInt(int value) {
    return value;
  }

  static DateTime? dateTimeFromNullableString(String? value) {
    if (value == null) {
      return null;
    } else {
      return DateTime.tryParse(value);
    }
  }
}
