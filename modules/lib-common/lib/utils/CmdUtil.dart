import 'dart:convert';
import 'dart:io';

typedef CmdResult = ({bool success, String response, String error});

class CmdUtil {
  Future<CmdResult?> executeCommand(String command, List<String> args) async {
    try {
      // 将命令和参数拼接成一个完整的字符串
      final String fullCommand = [command, ...args].join(' ');

      // 使用 cmd.exe /c 来执行一个命令链
      // 'chcp 65001 > nul' 会将当前代码页切换到 UTF-8，并丢弃 "Active code page: 65001" 这条输出
      // '&&' 会在前一条命令成功后执行后一条命令
      final result = await Process.run(
        'cmd.exe',
        ['/c', 'chcp 65001 > nul && $fullCommand'],
        // 因为我们强制了输出为 UTF-8，所以这里必须用 utf8 解码
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      return (
        success: result.exitCode == 0,
        response: result.stdout as String,
        error: result.stderr as String,
      );

    } catch (e) {
      // _showSnackBar('执行 $actionName 命令时出错: $e', isError: true);
      return (success: false, response: "", error: e.toString());
    }
  }
}
