class StringUtil {
  /// 检查一个字符串是否以 IPv4 地址开头。 ///
  /// [input] 要检查的字符串。
  /// 返回 true 如果字符串以有效的 IPv4 地址开头，否则返回 false。
  static bool startsWithIpAddress(String input) {
    // IPv4 地址的正则表达式，匹配字符串开头
    //250-255
    //200-249

    final ipPattern = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );

    // 使用 hasMatch 方法来检查字符串是否匹配该模式

    return ipPattern.hasMatch(input);
  }

  /// 检查一个字符串是否是完整的 IPv4 地址 (不包含其他字符)。

  static bool isIpAddress(String input) {
    // 在上面的正则表达式末尾添加 $，表示匹配字符串的结尾
    final ipPattern = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );
    return ipPattern.hasMatch(input);
  }
}
