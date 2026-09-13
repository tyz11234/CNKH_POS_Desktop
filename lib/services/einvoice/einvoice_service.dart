/// CNKH POS e-Invoice service layer scaffold.
///
/// This module is intentionally isolated from sales UI and database logic.
/// The first implementation phase adds configuration, queue handling and
/// MyInvois integration without changing existing checkout flows.
class EInvoiceService {
  const EInvoiceService();

  Future<void> initialize() async {
    // TODO: load e-Invoice settings and prepare API client.
  }

  Future<String> submitPendingInvoice(String saleId) async {
    // TODO: convert POS sale data to MyInvois document format and submit.
    throw UnimplementedError('e-Invoice submission will be enabled in the next commit: $saleId');
  }
}
