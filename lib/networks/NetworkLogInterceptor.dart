import 'package:dio/dio.dart';
import 'package:lib_common/log/Logger.dart';

class NetworkLogInterceptor extends Interceptor {
  final String _tag = "dio";

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    StringBuffer sb = StringBuffer();
    sb.write("L === dio request ===\n");
    sb.write("| ${options.method} ${options.baseUrl} ${options.path} \n");
    sb.write("| Header: ${options.headers.toString()} \n");
    sb.write("| Body: ${_describeBody(options.data)} \n");
    sb.write(
      "L______________________________________________________________|",
    );
    Logger.dLog(_tag, sb.toString());
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    StringBuffer sb = StringBuffer();
    sb.write("L === dio error === \n");
    sb.write("| ExceptionType:${err.type.name} \n");
    sb.write("| ErrorMsg: ${err.message} \n");
    sb.write("| Code: ${err.response?.statusCode} \n");
    sb.write("| Code: ${err.response?.statusMessage} \n");
    sb.write(
      "L______________________________________________________________|",
    );
    Logger.eLog(_tag, sb.toString(), error: err, stackTrace: err.stackTrace);
    handler.next(err);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    StringBuffer sb = StringBuffer();
    sb.write("L === dio response === \n");
    sb.write(
      "| ${response.requestOptions.method} ${response.requestOptions.baseUrl} ${response.requestOptions.path}",
    );
    sb.write("| Code: ${response.statusCode} \n");
    sb.write("| Code: ${response.statusMessage} \n");
    sb.write("| Header: ${response.requestOptions.headers.toString()} \n");

    sb.write("| Body: ${_describeBody(response.data)} \n");

    sb.write(
      "L______________________________________________________________|",
    );
    Logger.dLog(_tag, sb.toString());
    handler.next(response);
  }

  String _describeBody(Object? data) {
    if (data == null) {
      return 'empty';
    }
    if (data is FormData) {
      return 'FormData(fields=${data.fields.length}, files=${data.files.length})';
    }
    if (data is List) {
      return 'List(records=${data.length})';
    }
    if (data is Map) {
      return 'Map(fields=${data.length})';
    }
    if (data is String) {
      return 'String(characters=${data.length})';
    }
    return data.runtimeType.toString();
  }
}
