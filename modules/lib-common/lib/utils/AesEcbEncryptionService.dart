import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:lib_common/log/Logger.dart';

/// 一个封装了 AES (ECB 模式) 加密和解密逻辑的服务类。
///
/// 这个类封装了密钥（Key）和加密器（Encrypter），
/// 提供了简单的方法来加密和解密字符串。
///
/// !!! 安全警告 !!!
/// ECB 模式通常不被推荐用于大多数应用场景，因为它不安全。
/// 相同的明文块会被加密成相同的密文块，这会暴露数据中的模式。
/// 只有在加密非常短且完全随机的数据时，或者在有特定协议要求时才应使用。
/// 对于大多数情况，请优先考虑使用 CBC, GCM 或 CTR 模式。
class AesEcbEncryptionService {
  // --- 安全警告 ---
  // 在真实的应用中, 绝对不要硬编码密钥。
  // 应该使用 flutter_secure_storage 等工具来安全地存储和管理密钥。
  //
  // 对于 AES-256, 密钥必须是 32 字节 (256位) 长。
  static const String _secretKeyString = 'EWDMR1QZVCF3HTWUBQENK0LMDCVAKBSD';

  // 加密器实例
  final encrypt.Encrypter _encrypter;

  /// 创建加密服务的实例。
  ///
  /// 初始化 Key, 以及使用 AES ECB 模式的加密器。
  AesEcbEncryptionService()
    : _encrypter = encrypt.Encrypter(
        encrypt.AES(
          encrypt.Key.fromUtf8(_secretKeyString),
          mode: encrypt.AESMode.ecb,
          padding: 'PKCS7', // 'PKCS7' 是一种常见的填充方式
        ),
      );

  /// 加密给定的明文。
  ///
  /// [plainText] 需要加密的文本。
  /// 返回一个 Base64 编码的加密后字符串。
  String encryptText(String plainText) {
    // ECB 模式不使用 IV
    final encrypted = _encrypter.encrypt(plainText);
    return encrypted.base64;
  }

  /// 解密给定的 Base64 编码的密文。
  ///
  /// [cipherText] 需要解密的 Base64 编码的文本。
  /// 返回原始的明文。
  String decryptText(String cipherText) {
    try {
      final encryptedData = encrypt.Encrypted.fromBase64(cipherText);
      // ECB 模式不使用 IV
      final decrypted = _encrypter.decrypt(encryptedData);
      return decrypted;
    } catch (e) {
      // 如果密钥或密文不正确，解密可能会失败
      Logger.eLog('AesEcbEncryptionService', '解密失败', error: e);
      return "解密错误";
    }
  }
}
