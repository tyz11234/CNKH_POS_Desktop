import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pkcs12_parser/pkcs12_parser.dart';
import 'package:pointycastle/export.dart';

/// Builds the UBL 2.1 JSON XAdES signature required by MyInvois Invoice 1.1.
class EInvoiceSigner {
  static const _sha256 = 'http://www.w3.org/2001/04/xmlenc#sha256';
  static const _rsaSha256 = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256';
  static const _signedPropertiesType = 'http://uri.etsi.org/01903/v1.3.2#SignedProperties';
  static const _signatureUri = 'urn:oasis:names:specification:ubl:dsig:enveloped:xades';
  static const _invoiceSignatureId = 'urn:oasis:names:specification:ubl:signature:Invoice';
  static const _sigId = 'signature';
  static const _propsId = 'id-xades-signed-props';
  static final _hash = Sha256();

  Future<void> validateCertificate(
    List<int> pfx,
    String password, {
    String? expectedTin,
    String? expectedBrn,
  }) async {
    if (pfx.isEmpty || pfx.length > 5 * 1024 * 1024) {
      throw ArgumentError('证书文件大小须小于 5 MB');
    }
    final bundle = Pkcs12.load(Uint8List.fromList(pfx), password);
    final privateKey = bundle.privateKey;
    final publicKey = bundle.publicKey;
    if (privateKey is! RSAPrivateKey ||
        privateKey.modulus!.bitLength < 2048 ||
        publicKey is! RSAPublicKey) {
      throw StateError('MyInvois 需要至少 2048 位 RSA 数字证书');
    }
    final certificate = _certificateInfo(bundle.certificatePem);
    _validateCertificateProfile(
      certificate,
      expectedTin: expectedTin,
      expectedBrn: expectedBrn,
    );
    if (certificate.publicKey.modulus != publicKey.modulus ||
        certificate.publicKey.publicExponent != publicKey.publicExponent) {
      throw StateError('PFX 私钥与证书公钥不匹配');
    }
  }

  static void requireSignedInvoice(Map<String, dynamic> payload) {
    final invoices = payload['Invoice'];
    if (invoices is! List || invoices.length != 1 || invoices.single is! Map) {
      throw StateError('Invoice JSON 结构无效');
    }
    final invoice = Map<String, dynamic>.from(invoices.single as Map);
    final type = invoice['InvoiceTypeCode'];
    final signature = invoice['Signature'];
    final extensions = invoice['UBLExtensions'];
    if (type is! List ||
        type.isEmpty ||
        (type.first as Map?)?['listVersionID'] != '1.1' ||
        signature is! List ||
        signature.length != 1 ||
        extensions is! List ||
        extensions.length != 1) {
      throw StateError('此待提交发票是旧版未签名单据，请重新生成后再提交');
    }
    try {
      final rootSignature = signature.single as Map;
      final rootMethod = rootSignature['SignatureMethod'][0]['_'];
      final extension = (extensions.single as Map)['UBLExtension'][0] as Map;
      final extensionUri = extension['ExtensionURI'][0]['_'];
      final information =
          extension['ExtensionContent'][0]['UBLDocumentSignatures'][0]
              ['SignatureInformation'][0] as Map;
      final signed = information['Signature'][0] as Map;
      final value = signed['SignatureValue'][0]['_'];
      final signedInfo = signed['SignedInfo'][0] as Map;
      final signingMethod = signedInfo['SignatureMethod'][0]['Algorithm'];
      final references = signedInfo['Reference'] as List;
      if (references.length != 2) throw const FormatException();
      final propertiesReference = references[0] as Map;
      final documentReference = references[1] as Map;
      final certificate =
          signed['KeyInfo'][0]['X509Data'][0]['X509Certificate'][0]['_'];
      final propertiesMethod =
          (propertiesReference['DigestMethod'] as List).first['Algorithm'];
      final documentMethod =
          (documentReference['DigestMethod'] as List).first['Algorithm'];
      final propertiesDigest =
          (propertiesReference['DigestValue'] as List).first['_'];
      final documentDigest =
          (documentReference['DigestValue'] as List).first['_'];
      if (rootMethod != _signatureUri ||
          extensionUri != _signatureUri ||
          signingMethod != _rsaSha256 ||
          propertiesReference['Type'] != _signedPropertiesType ||
          propertiesReference['URI'] != '#$_propsId' ||
          documentReference['Type'] != '' ||
          documentReference['URI'] != '' ||
          propertiesMethod != _sha256 ||
          documentMethod != _sha256 ||
          value is! String ||
          certificate is! String ||
          propertiesDigest is! String ||
          documentDigest is! String) {
        throw const FormatException();
      }

      final signatureBytes = base64Decode(value);
      final certificateDer = base64Decode(certificate);
      if (signatureBytes.isEmpty || certificateDer.isEmpty) {
        throw const FormatException();
      }
      final certPem = '-----BEGIN CERTIFICATE-----\n'
          '${base64Encode(certificateDer)}\n'
          '-----END CERTIFICATE-----';
      final certificateInfo = _certificateInfo(certPem);
      _ensureCertificateCurrent(certificateInfo);

      final canonicalInvoice = Map<String, dynamic>.from(invoice)
        ..remove('UBLExtensions')
        ..remove('Signature');
      canonicalInvoice['InvoiceTypeCode'] =
          (canonicalInvoice['InvoiceTypeCode'] as List).map((raw) {
        final code = Map<String, dynamic>.from(raw as Map);
        code['listVersionID'] = '1.0';
        return code;
      }).toList();
      final canonicalPayload = Map<String, dynamic>.from(payload)
        ..['Invoice'] = <Object?>[canonicalInvoice];
      final documentBytes = utf8.encode(jsonEncode(canonicalPayload));
      if (_digestBase64(documentBytes) != documentDigest) {
        throw const FormatException();
      }

      final object = signed['Object'] as List;
      final qualifyingProperties =
          (object.single as Map)['QualifyingProperties'][0] as Map;
      final signedProperties =
          qualifyingProperties['SignedProperties'] as List;
      if (signedProperties.length != 1 ||
          (signedProperties.single as Map)['Id'] != _propsId) {
        throw const FormatException();
      }
      final signedPropertiesBytes = utf8.encode(jsonEncode(<String, Object?>{
        'Target': _sigId,
        'SignedProperties': signedProperties,
      }));
      if (_digestBase64(signedPropertiesBytes) != propertiesDigest) {
        throw const FormatException();
      }
      final certDigest = (((signedProperties.single as Map)
                  ['SignedSignatureProperties'][0]['SigningCertificate'][0]
              ['Cert'][0]['CertDigest'][0]['DigestValue'][0]['_'])
          as String);
      if (_digestBase64(certificateDer) != certDigest) {
        throw const FormatException();
      }

      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(
          false,
          PublicKeyParameter<RSAPublicKey>(certificateInfo.publicKey),
        );
      if (!verifier.verifySignature(
        Uint8List.fromList(documentBytes),
        RSASignature(signatureBytes),
      )) {
        throw const FormatException();
      }
    } catch (_) {
      throw StateError('发票数字签名无效或已被修改，请重新生成');
    }
  }

  Future<String> sign(
    String invoiceJson, {
    required List<int> pfx,
    required String password,
    String? expectedTin,
    String? expectedBrn,
  }) async {
    await validateCertificate(
      pfx,
      password,
      expectedTin: expectedTin,
      expectedBrn: expectedBrn,
    );
    final data = jsonDecode(invoiceJson);
    if (data is! Map<String, dynamic> || data['Invoice'] is! List || (data['Invoice'] as List).length != 1) {
      throw const FormatException('Invoice JSON 结构无效');
    }
    final invoice = data['Invoice'][0] as Map<String, dynamic>;
    if (invoice['UBLExtensions'] != null || invoice['Signature'] != null) throw StateError('发票已有签名扩展，拒绝重复签名');
    final p12 = Pkcs12.load(Uint8List.fromList(pfx), password);
    final privateKey = p12.privateKey as RSAPrivateKey;
    final certPem = p12.certificatePem;
    final cert = _certificateInfo(certPem);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

    final canonicalInvoice = Map<String, dynamic>.from(invoice)
      ..remove('UBLExtensions')
      ..remove('Signature');
    final canonical = Map<String, dynamic>.from(data)..['Invoice'] = [canonicalInvoice];
    final documentBytes = utf8.encode(jsonEncode(canonical));
    final documentDigest = base64Encode((await _hash.hash(documentBytes)).bytes);
    final certDer = _pemBytes(certPem);
    final certDigest = base64Encode((await _hash.hash(certDer)).bytes);
    final signedProperties = <String, dynamic>{
      'Id': _propsId,
      'SignedSignatureProperties': [{
        'SigningTime': [{'_' : timestamp}],
        'SigningCertificate': [{ 'Cert': [{
          'CertDigest': [{'DigestMethod': [{'_' : '', 'Algorithm': _sha256}], 'DigestValue': [{'_' : certDigest}]}],
          'IssuerSerial': [{'X509IssuerName': [{'_' : cert.issuer}], 'X509SerialNumber': [{'_' : cert.serial}]}],
        }]}],
      }],
    };
    final propsDigest = base64Encode((await _hash.hash(utf8.encode(jsonEncode({'Target': _sigId, 'SignedProperties': [signedProperties]})))).bytes);
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = base64Encode((signer.generateSignature(Uint8List.fromList(documentBytes)) as RSASignature).bytes);
    final x509 = base64Encode(certDer);

    invoice['InvoiceTypeCode'] = (invoice['InvoiceTypeCode'] as List).map((e) => {...Map<String, dynamic>.from(e as Map), 'listVersionID': '1.1'}).toList();
    invoice['UBLExtensions'] = [{ 'UBLExtension': [{
      'ExtensionURI': [{'_' : _signatureUri}],
      'ExtensionContent': [{'UBLDocumentSignatures': [{'SignatureInformation': [{
        'ID': [{'_' : 'urn:oasis:names:specification:ubl:signature:1'}],
        'ReferencedSignatureID': [{'_' : _invoiceSignatureId}],
        'Signature': [{
          'Id': _sigId,
          'Object': [{'QualifyingProperties': [{'Target': _sigId, 'SignedProperties': [signedProperties]}]}],
          'KeyInfo': [{'X509Data': [{
            'X509Certificate': [{'_' : x509}], 'X509SubjectName': [{'_' : cert.subject}],
            'X509IssuerSerial': [{'X509IssuerName': [{'_' : cert.issuer}], 'X509SerialNumber': [{'_' : cert.serial}]}],
          }]}],
          'SignatureValue': [{'_' : signature}],
          'SignedInfo': [{
            'SignatureMethod': [{'_' : '', 'Algorithm': _rsaSha256}],
            'Reference': [
              {'Type': _signedPropertiesType, 'URI': '#$_propsId', 'DigestMethod': [{'_' : '', 'Algorithm': _sha256}], 'DigestValue': [{'_' : propsDigest}]},
              {'Type': '', 'URI': '', 'DigestMethod': [{'_' : '', 'Algorithm': _sha256}], 'DigestValue': [{'_' : documentDigest}]},
            ],
          }],
        }],
      }]}]}],
    }]}];
    invoice['Signature'] = [{'ID': [{'_' : _invoiceSignatureId}], 'SignatureMethod': [{'_' : _signatureUri}]}];
    return jsonEncode(data);
  }

  static Uint8List _pemBytes(String pem) => Uint8List.fromList(base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')));
  static _CertInfo _certificateInfo(String pem) {
    final der = _pemBytes(pem);
    final root = _DerReader(der).read();
    if (root.tag != 0x30 || root.children.length < 3) {
      throw const FormatException('证书格式无效');
    }
    final tbs = root.children.first.children;
    var index = tbs.first.tag == 0xa0 ? 1 : 0;
    if (tbs.length < index + 6) {
      throw const FormatException('证书缺少必需字段');
    }
    final serial = BigInt.parse(
      tbs[index].value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    ).toString();
    final issuerNode = tbs[index + 2];
    final validity = tbs[index + 3];
    final subjectNode = tbs[index + 4];
    final publicKeyInfo = tbs[index + 5];
    if (validity.children.length != 2 || publicKeyInfo.children.length < 2) {
      throw const FormatException('证书缺少有效期或 RSA 公钥');
    }
    final algorithm = publicKeyInfo.children.first.children;
    if (algorithm.isEmpty ||
        _oid(algorithm.first.value) != '1.2.840.113549.1.1.1') {
      throw const FormatException('证书公钥不是 RSA');
    }
    final bitString = publicKeyInfo.children[1];
    if (bitString.tag != 0x03 ||
        bitString.value.length < 2 ||
        bitString.value.first != 0) {
      throw const FormatException('RSA 公钥编码无效');
    }
    final rsaKey = _DerReader(bitString.value.sublist(1)).read();
    if (rsaKey.tag != 0x30 || rsaKey.children.length < 2) {
      throw const FormatException('RSA 公钥结构无效');
    }
    final publicKey = RSAPublicKey(
      _positiveInteger(rsaKey.children[0].value),
      _positiveInteger(rsaKey.children[1].value),
    );
    final attrs = _nameAttributes(subjectNode);
    final extensions = _certificateExtensions(tbs);
    return _CertInfo(
      issuer: _name(issuerNode),
      subject: _name(subjectNode),
      serial: serial,
      subjectAttributes: attrs,
      notBefore: _x509Time(validity.children[0]),
      notAfter: _x509Time(validity.children[1]),
      keyUsage: extensions.keyUsage,
      extendedKeyUsage: extensions.extendedKeyUsage,
      publicKey: publicKey,
    );
  }

  static BigInt _positiveInteger(List<int> value) {
    if (value.isEmpty) throw const FormatException('证书整数无效');
    final bytes = value.length > 1 && value.first == 0 ? value.sublist(1) : value;
    return BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  static Map<String, String> _nameAttributes(_DerNode name) {
    final result = <String, String>{};
    for (final rdn in name.children) {
      for (final attribute in rdn.children) {
        if (attribute.children.length < 2) continue;
        result[_oid(attribute.children.first.value)] =
            attribute.children[1].text.trim();
      }
    }
    return result;
  }

  static ({Set<int> keyUsage, Set<String> extendedKeyUsage})
      _certificateExtensions(List<_DerNode> tbs) {
    final keyUsage = <int>{};
    final extendedKeyUsage = <String>{};
    for (final wrapper in tbs.where((node) => node.tag == 0xa3)) {
      if (wrapper.children.length != 1) {
        throw const FormatException('证书扩展结构无效');
      }
      for (final extension in wrapper.children.single.children) {
        if (extension.children.length < 2) {
          throw const FormatException('证书扩展字段无效');
        }
        final oid = _oid(extension.children.first.value);
        var valueIndex = 1;
        if (extension.children[valueIndex].tag == 0x01) valueIndex++;
        if (valueIndex >= extension.children.length ||
            extension.children[valueIndex].tag != 0x04) {
          throw const FormatException('证书扩展值无效');
        }
        final value = _DerReader(extension.children[valueIndex].value).read();
        if (oid == '2.5.29.15') {
          if (value.tag != 0x03 || value.value.isEmpty) {
            throw const FormatException('Key Usage 扩展无效');
          }
          final unusedBits = value.value.first;
          final bitBytes = value.value.skip(1).toList(growable: false);
          final bitCount = bitBytes.length * 8 - unusedBits;
          for (var bit = 0; bit < bitCount; bit++) {
            if ((bitBytes[bit ~/ 8] & (0x80 >> (bit % 8))) != 0) {
              keyUsage.add(bit);
            }
          }
        } else if (oid == '2.5.29.37') {
          if (value.tag != 0x30) {
            throw const FormatException('Extended Key Usage 扩展无效');
          }
          for (final purpose in value.children) {
            extendedKeyUsage.add(_oid(purpose.value));
          }
        }
      }
    }
    return (keyUsage: keyUsage, extendedKeyUsage: extendedKeyUsage);
  }

  static DateTime _x509Time(_DerNode node) {
    final raw = node.text.trim();
    if (!raw.endsWith('Z')) {
      throw const FormatException('证书时间须为 UTC');
    }
    final digits = raw.substring(0, raw.length - 1);
    final match = node.tag == 0x17
        ? RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?$')
            .firstMatch(digits)
        : node.tag == 0x18
            ? RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.\d+)?$')
                .firstMatch(digits)
            : null;
    if (match == null) throw const FormatException('证书有效期格式无效');
    var offset = 1;
    int part() => int.parse(match.group(offset++)!);
    var year = part();
    if (node.tag == 0x17) year += year >= 50 ? 1900 : 2000;
    final month = part();
    final day = part();
    final hour = part();
    final minute = part();
    final second = match.group(offset) == null ? 0 : part();
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  static void _ensureCertificateCurrent(_CertInfo cert) {
    final now = DateTime.now().toUtc();
    if (now.isBefore(cert.notBefore) || !now.isBefore(cert.notAfter)) {
      throw StateError('数字证书已过期或尚未生效');
    }
  }

  static void _validateCertificateProfile(
    _CertInfo cert, {
    String? expectedTin,
    String? expectedBrn,
  }) {
    _ensureCertificateCurrent(cert);
    const requiredDn = <String, String>{
      '2.5.4.3': 'CN',
      '2.5.4.6': 'C',
      '2.5.4.10': 'O',
      '2.5.4.97': 'TIN',
      '2.5.4.5': 'BRN',
    };
    for (final entry in requiredDn.entries) {
      if ((cert.subjectAttributes[entry.key] ?? '').trim().isEmpty) {
        throw StateError('数字证书缺少必需字段 ${entry.value}');
      }
    }
    if (cert.subjectAttributes['2.5.4.6']?.toUpperCase() != 'MY') {
      throw StateError('MyInvois 数字证书必须属于马来西亚组织');
    }
    final tin = cert.subjectAttributes['2.5.4.97']!.trim().toUpperCase();
    final brn = cert.subjectAttributes['2.5.4.5']!.trim();
    if (expectedTin != null &&
        expectedTin.trim().isNotEmpty &&
        tin != expectedTin.trim().toUpperCase()) {
      throw StateError('证书 TIN 与当前 e-Invoice 公司资料不符');
    }
    if (expectedBrn != null &&
        expectedBrn.trim().isNotEmpty &&
        brn != expectedBrn.trim()) {
      throw StateError('证书 BRN 与当前 e-Invoice 公司资料不符');
    }
    if (!cert.keyUsage.contains(1)) {
      throw StateError('数字证书 Key Usage 必须包含 Non-Repudiation');
    }
    if (!cert.extendedKeyUsage.contains('1.3.6.1.4.1.311.10.3.12')) {
      throw StateError('数字证书 Enhanced Key Usage 必须包含 Document Signing');
    }
  }

  static String _digestBase64(List<int> bytes) =>
      base64Encode(SHA256Digest().process(Uint8List.fromList(bytes)));

  static String _name(_DerNode name) {
    const keys = {
      '2.5.4.3':'CN', '2.5.4.4':'SN', '2.5.4.5':'SERIALNUMBER', '2.5.4.6':'C',
      '2.5.4.7':'L', '2.5.4.8':'ST', '2.5.4.9':'STREET', '2.5.4.10':'O',
      '2.5.4.11':'OU', '2.5.4.12':'T', '2.5.4.97':'organizationIdentifier',
      '2.5.4.15':'businessCategory', '2.5.4.17':'postalCode', '2.5.4.18':'postOfficeBox',
      '2.5.4.19':'physicalDeliveryOfficeName', '2.5.4.20':'telephoneNumber',
      '2.5.4.42':'GN', '2.5.4.43':'initials', '2.5.4.44':'generationQualifier', '2.5.4.46':'dnQualifier',
      '1.2.840.113549.1.9.1':'emailAddress', '0.9.2342.19200300.100.1.25':'DC',
    };
    final parts = <String>[];
    for (final rdn in name.children.reversed) {
      for (final attr in rdn.children) {
        if (attr.children.length < 2) continue;
        final oid = _oid(attr.children.first.value);
        final key = keys[oid] ?? 'OID.$oid';
        final value = attr.children[1].text.replaceAll(r'\', r'\\').replaceAll(',', r'\,').replaceAll('+', r'\+');
        parts.add('$key=$value');
      }
    }
    if (parts.isEmpty) throw const FormatException('证书没有可读取的 X.509 名称');
    return parts.join(', ');
  }
  static String _oid(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final values = <int>[];
    var current = 0;
    for (final b in bytes) { current = (current << 7) | (b & 0x7f); if ((b & 0x80) == 0) { values.add(current); current = 0; } }
    if (values.isEmpty) return '';
    final first = values.removeAt(0);
    return '${first < 40 ? 0 : first < 80 ? 1 : 2}.${first - (first < 40 ? 0 : first < 80 ? 40 : 80)}${values.map((v) => '.$v').join()}';
  }
}

class _CertInfo {
  const _CertInfo({
    required this.issuer,
    required this.subject,
    required this.serial,
    required this.subjectAttributes,
    required this.notBefore,
    required this.notAfter,
    required this.keyUsage,
    required this.extendedKeyUsage,
    required this.publicKey,
  });
  final String issuer;
  final String subject;
  final String serial;
  final Map<String, String> subjectAttributes;
  final DateTime notBefore;
  final DateTime notAfter;
  final Set<int> keyUsage;
  final Set<String> extendedKeyUsage;
  final RSAPublicKey publicKey;
}
class _DerNode {
  const _DerNode(this.tag, this.value, this.children);
  final int tag; final List<int> value; final List<_DerNode> children;
  String get text => tag == 0x1e
      ? String.fromCharCodes([for (var i=0; i+1<value.length; i+=2) (value[i]<<8)|value[i+1]])
      : utf8.decode(value, allowMalformed: true);
}
class _DerReader {
  _DerReader(this.bytes);
  final List<int> bytes;
  _DerNode read([int start = 0]) {
    var offset = start;
    final tag = bytes[offset++];
    var length = bytes[offset++];
    if ((length & 0x80) != 0) { final count = length & 0x7f; if (count == 0 || count > 4) throw const FormatException('Unsupported certificate DER length'); length = 0; for (var i=0; i<count; i++) { length = (length << 8) | bytes[offset++]; } }
    final end = offset + length;
    if (end > bytes.length) throw const FormatException('Truncated certificate DER');
    final value = bytes.sublist(offset, end);
    final children = <_DerNode>[];
    if ((tag & 0x20) != 0) { var child = offset; while (child < end) { final node = read(child); children.add(node); child = nodeEnd(child); } }
    return _DerNode(tag, value, children);
  }
  int nodeEnd(int start) { var i=start+1, length=bytes[i++]; if ((length&0x80)!=0) { final count=length&0x7f; length=0; for(var n=0;n<count;n++) { length=(length<<8)|bytes[i++]; } } return i+length; }
}
