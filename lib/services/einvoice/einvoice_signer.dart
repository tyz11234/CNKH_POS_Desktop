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

  Future<void> validateCertificate(List<int> pfx, String password) async {
    if (pfx.isEmpty || pfx.length > 5 * 1024 * 1024) throw ArgumentError('证书文件大小须小于 5 MB');
    final bundle = Pkcs12.load(Uint8List.fromList(pfx), password);
    final key = bundle.privateKey;
    if (key is! RSAPrivateKey || key.modulus!.bitLength < 2048) throw StateError('MyInvois 需要至少 2048 位 RSA 数字证书');
    _certificateInfo(bundle.certificatePem);
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
    if (type is! List || type.isEmpty || (type.first as Map?)?['listVersionID'] != '1.1' ||
        signature is! List || signature.isEmpty || extensions is! List || extensions.isEmpty) {
      throw StateError('此待提交发票是旧版未签名单据，请重新生成后再提交');
    }
    try {
      final rootSignature = signature.first as Map;
      final rootMethod = rootSignature['SignatureMethod'][0]['_'];
      final extension = (extensions.first as Map)['UBLExtension'][0] as Map;
      final extensionUri = extension['ExtensionURI'][0]['_'];
      final information = extension['ExtensionContent'][0]['UBLDocumentSignatures'][0]['SignatureInformation'][0] as Map;
      final signed = information['Signature'][0] as Map;
      final value = signed['SignatureValue'][0]['_'];
      final signedInfo = signed['SignedInfo'][0] as Map;
      final signingMethod = signedInfo['SignatureMethod'][0]['Algorithm'];
      final references = signedInfo['Reference'] as List;
      final props = references[0] as Map;
      final document = references[1] as Map;
      final certificate = signed['KeyInfo'][0]['X509Data'][0]['X509Certificate'][0]['_'];
      final sha256Method = (props['DigestMethod'] as List).first['Algorithm'];
      final documentSha256Method = (document['DigestMethod'] as List).first['Algorithm'];
      final propsDigest = (props['DigestValue'] as List).first['_'];
      final documentDigest = (document['DigestValue'] as List).first['_'];
      if (rootMethod != _signatureUri || extensionUri != _signatureUri || signingMethod != _rsaSha256 ||
          props['Type'] != _signedPropertiesType || props['URI'] != '#$_propsId' ||
          document['Type'] != '' || document['URI'] != '' ||
          sha256Method != _sha256 || documentSha256Method != _sha256 ||
          value is! String || base64Decode(value).isEmpty || references.length != 2 ||
          certificate is! String || base64Decode(certificate).isEmpty ||
          propsDigest is! String || base64Decode(propsDigest).isEmpty ||
          documentDigest is! String || base64Decode(documentDigest).isEmpty) {
        throw const FormatException();
      }
    } catch (_) {
      throw StateError('发票数字签名结构无效，请重新生成');
    }
  }

  Future<String> sign(String invoiceJson, {required List<int> pfx, required String password}) async {
    if (pfx.isEmpty || pfx.length > 5 * 1024 * 1024) throw ArgumentError('证书文件大小须小于 5 MB');
    final data = jsonDecode(invoiceJson);
    if (data is! Map<String, dynamic> || data['Invoice'] is! List || (data['Invoice'] as List).length != 1) {
      throw const FormatException('Invoice JSON 结构无效');
    }
    final invoice = data['Invoice'][0] as Map<String, dynamic>;
    if (invoice['UBLExtensions'] != null || invoice['Signature'] != null) throw StateError('发票已有签名扩展，拒绝重复签名');
    final p12 = Pkcs12.load(Uint8List.fromList(pfx), password);
    final privateKey = p12.privateKey;
    if (privateKey is! RSAPrivateKey || privateKey.modulus!.bitLength < 2048) throw StateError('MyInvois 需要至少 2048 位 RSA 数字证书');
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
    final root = _DerReader(_pemBytes(pem)).read();
    final cert = root.children;
    if (cert.length < 1) throw const FormatException('证书格式无效');
    final tbs = cert.first.children;
    var index = tbs.first.tag == 0xa0 ? 1 : 0;
    if (tbs.length < index + 6) throw const FormatException('证书缺少必需字段');
    final serial = BigInt.parse(tbs[index].value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16).toString();
    final issuer = _name(tbs[index + 2]);
    final subject = _name(tbs[index + 4]);
    return _CertInfo(issuer, subject, serial);
  }
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

class _CertInfo { const _CertInfo(this.issuer, this.subject, this.serial); final String issuer, subject, serial; }
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
