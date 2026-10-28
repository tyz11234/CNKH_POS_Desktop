/// EMVCo payload tools for DuitNow QR codes.
///
/// A merchant/personal DuitNow QR is an EMV TLV string. A static code
/// (tag 01 = "11") carries no amount, so the customer types it by hand —
/// and can type it wrong. Re-issuing the same payload as a dynamic code
/// (tag 01 = "12") with tag 54 set to the exact amount due locks the
/// amount in the customer's banking app, which prevents underpayment.
/// The CRC (tag 63) is CRC-16/CCITT-FALSE over the whole payload.
///
/// Verified 2026-10-28 against the shop's real Public Bank merchant QR
/// (CHOP NG KIM HUAT, PBB202400117349): parse + rebuild + CRC validate,
/// and the shop owner confirmed a generated RM 1.00 dynamic code showed
/// the amount locked and correct in his banking app.
class DuitNowQr {
  /// Parses a TLV payload into [tag, value] pairs, or null if malformed.
  static List<List<String>>? parse(String payload) {
    if (payload.length < 12) return null;
    final out = <List<String>>[];
    var i = 0;
    while (i < payload.length) {
      if (i + 4 > payload.length) return null;
      final tag = payload.substring(i, i + 2);
      final len = int.tryParse(payload.substring(i + 2, i + 4));
      if (len == null || i + 4 + len > payload.length) return null;
      out.add([tag, payload.substring(i + 4, i + 4 + len)]);
      i += 4 + len;
    }
    return out;
  }

  /// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), 4 uppercase hex chars.
  static String crc16(String data) {
    var crc = 0xFFFF;
    for (final unit in data.codeUnits) {
      crc ^= (unit << 8) & 0xFFFF;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// True when [payload] is a well-formed EMV payload with a valid CRC.
  /// (No fixed prefix check: Malaysian National QR payloads begin with
  /// tag 00 value "02", not the "01" seen elsewhere — the CRC is the
  /// reliable validity test.)
  static bool isValid(String payload) {
    final tags = parse(payload);
    if (tags == null || tags.isEmpty || tags.last[0] != '63') return false;
    final body = payload.substring(0, payload.length - 4);
    return crc16(body) == payload.substring(payload.length - 4);
  }

  static String? tagValue(String payload, String tag) {
    final tags = parse(payload);
    if (tags == null) return null;
    for (final pair in tags) {
      if (pair[0] == tag) return pair[1];
    }
    return null;
  }

  /// The payee name (tag 59), for display in Settings.
  static String? payeeName(String payload) => tagValue(payload, '59');

  /// Rebuilds [staticPayload] as a dynamic QR payload with the amount
  /// locked to [amountCents]. Returns null when the source payload is
  /// not a valid EMV payload or the amount is not positive.
  static String? buildDynamic(String staticPayload, int amountCents) {
    if (amountCents <= 0) return null;
    if (!isValid(staticPayload)) return null;
    final tags = parse(staticPayload)!;
    final amount = (amountCents / 100).toStringAsFixed(2);
    final buf = StringBuffer();
    var wroteAmount = false;
    for (final pair in tags) {
      final tag = pair[0];
      var value = pair[1];
      if (tag == '63') continue; // CRC is recomputed below.
      if (tag == '01') value = '12'; // static -> dynamic
      if (tag == '54') {
        value = amount; // replace an existing amount
        wroteAmount = true;
      }
      buf.write(tag);
      buf.write(value.length.toString().padLeft(2, '0'));
      buf.write(value);
      if (tag == '53' && !wroteAmount) {
        // Tag 54 belongs immediately after the currency tag (53).
        buf.write('54');
        buf.write(amount.length.toString().padLeft(2, '0'));
        buf.write(amount);
        wroteAmount = true;
      }
    }
    if (!wroteAmount) return null;
    final body = '${buf}6304';
    return body + crc16(body);
  }
}
