import 'dart:convert';

/// UBL 2.1 JSON / MyInvois Invoice 1.0. All calculations use sale snapshots.
/// No products, prices or original sales are updated by this mapper.
class InvoiceMapper {
  static List<Map<String, dynamic>> value(Object v, [Map<String, dynamic> attributes = const {}]) => [{'_': v, ...attributes}];
  static List<Map<String, dynamic>> money(int cents) => value(cents / 100, {'currencyID': 'MYR'});
  static String requiredText(Map<String, dynamic> input, String key, {int max = 300}) {
    final s = '${input[key] ?? ''}'.trim();
    if (s.isEmpty || s.length > max) throw FormatException('$key 必填，最多 $max 字');
    return s;
  }
  static Map<String, dynamic> party(Map<String, dynamic> p, {required bool supplier}) {
    final name = requiredText(p, 'name');
    final tin = requiredText(p, 'tin', max: 14);
    final idType = supplier ? 'BRN' : requiredText(p, 'id_type');
    if (!['BRN', 'NRIC', 'PASSPORT', 'ARMY'].contains(idType)) throw const FormatException('Invalid buyer ID type');
    final id = requiredText(p, supplier ? 'brn' : 'id_number', max: idType == 'BRN' ? 20 : 12);
    final phone = requiredText(p, 'phone', max: 20);
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone)) throw const FormatException('电话须为 E.164 格式，例如 +60123456789');
    final state = requiredText(p, 'state', max: 2);
    if (!RegExp(r'^(0[1-9]|1[0-7])$').hasMatch(state)) throw const FormatException('Malaysia state code 须为 01–17');
    return {'Party': [{
      if (supplier) 'IndustryClassificationCode': value(requiredText(p, 'msic', max: 5), {'name': requiredText(p, 'activity')}),
      'PartyIdentification': [
        {'ID': value(tin, {'schemeID': 'TIN'})}, {'ID': value(id, {'schemeID': idType})},
        {'ID': value('${p['sst'] ?? 'NA'}', {'schemeID': 'SST'})},
        if (supplier) {'ID': value('${p['ttx'] ?? 'NA'}', {'schemeID': 'TTX'})},
      ],
      'PartyLegalEntity': [{'RegistrationName': value(name)}],
      'PostalAddress': [{
        'CityName': value(requiredText(p, 'city', max: 50)), 'CountrySubentityCode': value(state),
        if ('${p['postcode'] ?? ''}'.isNotEmpty) 'PostalZone': value(p['postcode']),
        'AddressLine': [{'Line': value(requiredText(p, 'address', max: 150))}],
        'Country': [{'IdentificationCode': value('MYS', {'listID': 'ISO3166-1', 'listAgencyID': '6'})}],
      }],
      'Contact': [{'Telephone': value(phone), if ('${p['email'] ?? ''}'.isNotEmpty) 'ElectronicMail': value(p['email'])}],
    }]};
  }
  Map<String, dynamic> mapSale(Map<String, Object?> sale, {required Map<String, dynamic> supplier, required Map<String, dynamic> buyer, required DateTime issuedAt}) {
    if (sale['voided'] == 1) throw const FormatException('已作废销售不能生成发票');
    final number = requiredText(Map<String, dynamic>.from(sale), 'receipt_no', max: 50);
    if (!RegExp(r'^\d{5}$').hasMatch('${supplier['msic'] ?? ''}')) throw const FormatException('MSIC 必须为五位数字');
    final classification = requiredText(supplier, 'classification', max: 3);
    if (!RegExp(r'^\d{3}$').hasMatch(classification)) throw const FormatException('商品分类须为三位 MyInvois classification code');
    final taxCode = requiredText(supplier, 'tax_type', max: 2);
    if (!['01','02','03','04','05','06','E'].contains(taxCode)) throw const FormatException('Invalid tax type');
    final rate = supplier['tax_rate_basis_points'] as int? ?? 0;
    if (rate < 0 || rate > 10000 || (['06','E'].contains(taxCode) && rate != 0)) throw const FormatException('Invalid tax rate');
    if (!['06','E'].contains(taxCode) && rate == 0) throw const FormatException('请输入适用税率');
    final exemption = taxCode == 'E' ? requiredText(supplier, 'exemption_reason') : '';
    final raw = jsonDecode(sale['lines_json'] as String) as List;
    if (raw.isEmpty) throw const FormatException('销售没有明细');
    int n(Object? v) { if (v is! int) throw const FormatException('Invalid monetary snapshot'); return v; }
    final orderDiscount = n(sale['order_discount_cents'] ?? 0);
    final rounding = n(sale['rounding_cents'] ?? 0);
    final total = n(sale['total_cents']);
    var grossSum = 0, discountSum = 0;
    final lines = <Map<String, dynamic>>[];
    for (final item in raw) {
      final line = Map<String, dynamic>.from(item as Map);
      final qty = n(line['qty']), unit = n(line['unitPriceCents']);
      final discount = n(line['lineDiscountCents'] ?? line['discountCents'] ?? 0);
      if (qty <= 0 || unit < 0 || discount < 0 || discount > qty * unit) throw const FormatException('Invalid line snapshot');
      final gross = qty * unit;
      if (line['lineTotalCents'] != null && n(line['lineTotalCents']) != gross - discount) throw const FormatException('明细金额不一致');
      grossSum += gross; discountSum += discount;
      lines.add({...line, 'gross': gross, 'net': gross-discount});
    }
    final net = grossSum - discountSum;
    if (orderDiscount < 0 || orderDiscount > net || total != net-orderDiscount+rounding || grossSum != n(sale['subtotal_cents']) || discountSum != n(sale['item_discount_cents'] ?? discountSum)) throw const FormatException('销售合计不一致，不能提交');
    var allocated = 0, cumulative = 0, taxableSum = 0, taxSum = 0;
    Map<String, dynamic> tax(int taxable, int amount) => {
      'TaxAmount': money(amount), 'TaxSubtotal': [{
        'TaxableAmount': money(taxable), 'TaxAmount': money(amount),
        if (rate > 0) 'Percent': value(rate / 100),
        'TaxCategory': [{'ID': value(taxCode), if (exemption.isNotEmpty) 'TaxExemptionReason': value(exemption),
          'TaxScheme': [{'ID': value('OTH', {'schemeID': 'UN/ECE 5153', 'schemeAgencyID': '6'})}]}],
      }],
    };
    final mapped = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i]; cumulative += l['net'] as int;
      final next = net == 0 ? 0 : (orderDiscount * cumulative ~/ net);
      final inclusive = (l['net'] as int) - (next-allocated); allocated = next;
      final exclusive = (inclusive * 10000 / (10000 + rate)).round();
      final taxAmount = inclusive-exclusive;
      final grossExclusive = ((l['gross'] as int)*10000 / (10000+rate)).round();
      taxableSum += exclusive; taxSum += taxAmount;
      mapped.add({
        'ID': value('${i+1}'), 'InvoicedQuantity': value(l['qty']),
        'LineExtensionAmount': money(exclusive), 'TaxTotal': [tax(exclusive, taxAmount)],
        'Item': [{'Description': value(requiredText({'description': '${l['nameEn'] ?? ''}'.trim().isEmpty ? l['nameZh'] : l['nameEn']}, 'description')),
          'CommodityClassification': [{'ItemClassificationCode': value(classification, {'listID': 'CLASS'})}]}],
        'Price': [{'PriceAmount': value((l['unitPriceCents'] as int) / (100 + rate/100), {'currencyID': 'MYR'})}],
        'ItemPriceExtension': [{'Amount': money(grossExclusive)}],
        if (grossExclusive != exclusive) 'AllowanceCharge': [{'ChargeIndicator': value(false), 'AllowanceChargeReason': value('POS line and allocated order discount'), 'Amount': money(grossExclusive-exclusive)}],
      });
    }
    final utc = issuedAt.toUtc().toIso8601String();
    return {'_D': 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2', '_A': 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2', '_B': 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2', 'Invoice': [{
      'ID': value(number), 'IssueDate': value(utc.substring(0,10)), 'IssueTime': value('${utc.substring(11,19)}Z'),
      'InvoiceTypeCode': value('01', {'listVersionID': '1.0'}), 'DocumentCurrencyCode': value('MYR'),
      'AccountingSupplierParty': [party(supplier, supplier: true)],
      'AccountingCustomerParty': [party({...buyer, 'name': buyer['name'] ?? sale['customer_name'], 'phone': buyer['phone'] ?? sale['customer_phone']}, supplier: false)],
      'InvoiceLine': mapped, 'TaxTotal': [tax(taxableSum, taxSum)],
      'LegalMonetaryTotal': [{'LineExtensionAmount': money(taxableSum), 'TaxExclusiveAmount': money(taxableSum), 'TaxInclusiveAmount': money(taxableSum+taxSum), 'PayableRoundingAmount': money(rounding), 'PayableAmount': money(total)}],
    }]};
  }
}
