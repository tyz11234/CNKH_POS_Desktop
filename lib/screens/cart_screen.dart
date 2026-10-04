import 'dart:io';
import 'package:flutter/material.dart';

import '../widgets/completed_dialog.dart';

import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../services/pos_repository.dart';
import '../theme/cnkh_theme.dart';
import '../widgets/money_text.dart';
import 'barcode_scan_screen.dart';
import '../services/lan_sync.dart';

class CartScreen extends StatefulWidget {
  final CartState cart;
  final AppUser user;
  final PosRepository repo;
  final VoidCallback onChanged;
  final VoidCallback onCheckout;
  final Future<void> Function() onHold;
  final bool isHolding;
  final int refreshToken;
  final Future<void> Function() onResume;
  final void Function(LanSyncConfig config)? onPairing;

  /// Desktop: product grid LEFT, cart+checkout RIGHT.
  final bool desktopTwoPane;

  const CartScreen({
    super.key,
    required this.cart,
    required this.user,
    required this.repo,
    required this.onChanged,
    required this.onCheckout,
    required this.onHold,
    this.isHolding = false,
    this.refreshToken = 0,
    required this.onResume,
    this.onPairing,
    this.desktopTwoPane = false,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _search = TextEditingController();
  List<Product> _results = [];
  List<Category> _categories = [];
  String _category = ''; // empty = 全部
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _searchGeneration = 0;
  static const int _productPageSize = 80;
  bool _imagesOn = false;

  @override
  void initState() {
    super.initState();
    _reload('');
    _search.addListener(() => _reload(_search.text));
    widget.repo.listCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    });
    widget.repo.productImagesEnabled().then((v) {
      if (mounted) setState(() => _imagesOn = v);
    });
  }

  @override
  void didUpdateWidget(covariant CartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refreshDirectory();
    }
  }

  Future<void> _refreshDirectory() async {
    final results = await Future.wait<Object>([
      widget.repo.listCategories(),
      widget.repo.productImagesEnabled(),
    ]);
    if (!mounted) return;
    final categories = results[0] as List<Category>;
    final imagesOn = results[1] as bool;
    final categoryStillExists =
        _category.isEmpty ||
        categories.any((category) => category.name == _category);
    setState(() {
      _categories = categories;
      _imagesOn = imagesOn;
      if (!categoryStillExists) _category = '';
    });
    // CartItem.product is a checkout-time price snapshot. Refresh the catalog
    // grid without repricing cart lines or resetting their manual discounts.
    await _reload(_search.text);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload(String q) async {
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _results = [];
      _hasMore = false;
    });
    final list = await widget.repo.searchProducts(
      q,
      limit: _productPageSize,
      category: _category.isEmpty ? null : _category,
    );
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _results = list;
      _hasMore = list.length == _productPageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final generation = _searchGeneration;
    setState(() => _loadingMore = true);
    final next = await widget.repo.searchProducts(
      _search.text,
      limit: _productPageSize,
      offset: _results.length,
      category: _category.isEmpty ? null : _category,
    );
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      final known = _results.map((product) => product.id).toSet();
      _results.addAll(next.where((product) => known.add(product.id)));
      _hasMore = next.length == _productPageSize;
      _loadingMore = false;
    });
  }

  Future<bool> _add(Product p, {int addQty = 1}) async {
    final existing = widget.cart.find(p.id);
    final nextQty = (existing?.qty ?? 0) + addQty;
    final stock = p.stock;
    if (nextQty > stock) {
      final policy = await widget.repo.stockPolicy();
      if (!mounted) return false;
      if (policy == 'block') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('库存不足 / Insufficient stock (有 $stock)'),
            backgroundColor: CnkhColors.danger,
          ),
        );
        return false;
      }
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('库存不足 / Low stock'),
          content: Text('${p.nameZh}\n需要 $nextQty · 库存 $stock\n仍要加购？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (cont != true) return false;
    }
    if (existing != null) {
      existing.qty += addQty;
      existing.discountCents = clampDiscountCents(
        existing.discountCents,
        existing.grossCents,
      );
    } else {
      widget.cart.items.add(CartItem(product: p, qty: addQty));
    }
    widget.onChanged();
    return true;
  }

  void _adjust(CartItem item, int delta) {
    item.qty += delta;
    if (item.qty <= 0) {
      widget.cart.items.remove(item);
    } else {
      item.discountCents = clampDiscountCents(
        item.discountCents,
        item.grossCents,
      );
    }
    widget.onChanged();
  }

  void _remove(CartItem item) {
    widget.cart.items.remove(item);
    widget.onChanged();
  }

  Future<void> _editLineDiscount(CartItem item) async {
    if (!widget.user.canDiscount) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('行折扣 / Line discount'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'rm'),
            child: const Text('金额 RM'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'pct'),
            child: const Text('百分比 %'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'clear'),
            child: const Text('清除折扣 / Clear'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == 'clear') {
      item.discountCents = 0;
      widget.onChanged();
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showCompletedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mode == 'rm' ? '折扣 RM' : '折扣 %'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: mode == 'rm' ? 'RM ' : '',
            suffixText: mode == 'pct' ? '%' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final v = double.tryParse(text);
    final cents = mode == 'rm' ? tryParseRmCents(text) : null;
    if (v == null || !v.isFinite || v < 0 || (mode == 'rm' && cents == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('折扣格式无效 / Invalid discount'),
          backgroundColor: CnkhColors.danger,
        ),
      );
      return;
    }
    final oldDisc = item.discountCents;
    if (mode == 'rm') {
      item.discountCents = clampDiscountCents(cents!, item.grossCents);
    } else {
      item.discountCents = percentDiscountCents(item.grossCents, v);
    }
    await widget.repo.logAudit(
      username: widget.user.username,
      role: widget.user.isAdmin ? 'ADMIN' : 'STAFF',
      action: 'line_discount',
      productId: item.product.id,
      productName: item.product.nameZh,
      context: 'cart',
      oldValue: '$oldDisc',
      newValue: '${item.discountCents}',
      reason: mode,
    );
    widget.onChanged();
  }

  Future<void> _editOrderDiscount() async {
    if (!widget.user.canDiscount) return;
    final ctrl = TextEditingController(
      text: centsToRm(widget.cart.orderDiscountCents).toStringAsFixed(2),
    );
    final ok = await showCompletedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('整单折扣 RM / Order discount'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: 'RM '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final parsed = tryParseRmCents(ctrl.text);
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (parsed == null || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('折扣格式无效 / Invalid discount'),
          backgroundColor: CnkhColors.danger,
        ),
      );
      return;
    }
    final oldOrder = widget.cart.orderDiscountCents;
    widget.cart.orderDiscountCents = parsed;
    await widget.repo.logAudit(
      username: widget.user.username,
      role: widget.user.isAdmin ? 'ADMIN' : 'STAFF',
      action: 'order_discount',
      context: 'cart',
      oldValue: '$oldOrder',
      newValue: '${widget.cart.orderDiscountCents}',
    );
    widget.onChanged();
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BarcodeScanScreen(
          repo: widget.repo,
          onProduct: (p) async {
            final accepted = await _add(p);
            if (mounted) setState(() {});
            return accepted;
          },
          onPairing: widget.onPairing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final due = cart.payableCents(isCredit: false);

    if (widget.desktopTwoPane) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: _buildProductPane(context)),
          const VerticalDivider(width: 1),
          SizedBox(width: 420, child: _buildCartPane(context, cart, due)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripH = constraints.maxHeight < 560 ? 72.0 : 120.0;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '收银台 / POS',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  _searchField(),
                  const SizedBox(height: 6),
                  _categoryChips(),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: CnkhColors.navy,
                      ),
                      onPressed: _openScanner,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text(
                        '扫码加购 / Scan barcode',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _holdResumeRow(cart),
                ],
              ),
            ),
            SizedBox(
              height: stripH,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _results.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        if (i == _results.length) {
                          return SizedBox(
                            width: 104,
                            child: OutlinedButton(
                              onPressed: _loadingMore ? null : _loadMore,
                              child: Text(_loadingMore ? '加载中…' : '更多商品'),
                            ),
                          );
                        }
                        final p = _results[i];
                        return _ProductChip(
                          product: p,
                          showImage: _imagesOn,
                          onTap: () {
                            _add(p);
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    '购物车 (${cart.itemCount})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: cart.items.isEmpty ? null : _editOrderDiscount,
                    child: Text(
                      cart.orderDiscountApplied > 0
                          ? '整单折扣 −${formatRm(cart.orderDiscountApplied)}'
                          : '整单折扣',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _cartList(cart)),
            _checkoutBar(cart, due),
          ],
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      decoration: const InputDecoration(
        hintText: '搜索 名称 / SKU / 条码',
        prefixIcon: Icon(Icons.search),
        isDense: true,
      ),
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: const Text('全部'),
              selected: _category.isEmpty,
              onSelected: (_) {
                setState(() => _category = '');
                _reload(_search.text);
              },
            ),
          ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(c.name),
                selected: _category == c.name,
                onSelected: (_) {
                  setState(() => _category = c.name);
                  _reload(_search.text);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _holdResumeRow(CartState cart) {
    return Row(
      children: [
        Flexible(
          child: OutlinedButton.icon(
            onPressed: cart.items.isEmpty || widget.isHolding
                ? null
                : widget.onHold,
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: const Text('挂单'),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: OutlinedButton.icon(
            onPressed: widget.onResume,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('取单'),
          ),
        ),
        TextButton(
          onPressed: cart.items.isEmpty
              ? null
              : () {
                  cart.items.clear();
                  cart.orderDiscountCents = 0;
                  widget.onChanged();
                },
          child: const Text('清空'),
        ),
      ],
    );
  }

  Widget _cartList(CartState cart) {
    if (cart.items.isEmpty) {
      return const Center(
        child: Text(
          '购物车为空\n搜索并点选商品',
          textAlign: TextAlign.center,
          style: TextStyle(color: CnkhColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: cart.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = cart.items[i];
        return _CartTile(
          item: item,
          onMinus: () => _adjust(item, -1),
          onPlus: () => _adjust(item, 1),
          onRemove: () => _remove(item),
          onDiscount: () => _editLineDiscount(item),
        );
      },
    );
  }

  Widget _checkoutBar(CartState cart, int due) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '合计 / Total · ${cart.itemCount} 件',
                      style: const TextStyle(
                        color: CnkhColors.muted,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        amountCents: due,
                        fontSize: 26,
                        hero: true,
                      ),
                    ),
                    if (cart.itemDiscountsCents + cart.orderDiscountApplied > 0)
                      Text(
                        '折扣 −${formatRm(cart.itemDiscountsCents + cart.orderDiscountApplied)}',
                        style: const TextStyle(
                          color: CnkhColors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: CnkhColors.success,
                      disabledBackgroundColor: CnkhColors.border,
                    ),
                    onPressed: cart.items.isEmpty ? null : widget.onCheckout,
                    child: const Text(
                      '结账\nCheckout',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '商品 / Products',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _searchField()),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: CnkhColors.navy,
                      ),
                      onPressed: _openScanner,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫码'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _categoryChips(),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: _results.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _results.length) {
                      return OutlinedButton.icon(
                        onPressed: _loadingMore ? null : _loadMore,
                        icon: _loadingMore
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more),
                        label: Text(_loadingMore ? '加载中…' : '加载更多商品'),
                      );
                    }
                    final p = _results[i];
                    return _ProductChip(
                      product: p,
                      showImage: _imagesOn,
                      onTap: () {
                        _add(p);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCartPane(BuildContext context, CartState cart, int due) {
    return ColoredBox(
      color: const Color(0xFFF7FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  '购物车 (${cart.itemCount})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                TextButton(
                  onPressed: cart.items.isEmpty ? null : _editOrderDiscount,
                  child: Text(
                    cart.orderDiscountApplied > 0
                        ? '整单 −${formatRm(cart.orderDiscountApplied)}'
                        : '整单折扣',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _holdResumeRow(cart),
          ),
          const Divider(height: 16),
          Expanded(child: _cartList(cart)),
          // Clean summary rows — no overlap
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: CnkhColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sumRow('小计 / Subtotal', formatRm(cart.subtotalGrossCents)),
                if (cart.itemDiscountsCents + cart.orderDiscountApplied > 0)
                  _sumRow(
                    '折扣 / Discount',
                    '−${formatRm(cart.itemDiscountsCents + cart.orderDiscountApplied)}',
                    valueColor: CnkhColors.success,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      '应付 / Due',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    MoneyText(amountCents: due, fontSize: 28, hero: true),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: CnkhColors.success,
                      disabledBackgroundColor: CnkhColors.border,
                    ),
                    onPressed: cart.items.isEmpty ? null : widget.onCheckout,
                    child: const Text(
                      '结账 / Checkout',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: CnkhColors.muted, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductChip extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final bool showImage;
  const _ProductChip({
    required this.product,
    required this.onTap,
    this.showImage = false,
  });
  @override
  Widget build(BuildContext context) {
    final hasImg =
        showImage &&
        product.imagePath.isNotEmpty &&
        File(product.imagePath).existsSync();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CnkhColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImg)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(product.imagePath),
                    height: 36,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              Text(
                product.nameZh,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                product.sku,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CnkhColors.muted, fontSize: 11),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: MoneyText(
                      amountCents: product.priceCents,
                      fontSize: 14,
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: CnkhColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;
  final VoidCallback onDiscount;

  const _CartTile({
    required this.item,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
    required this.onDiscount,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.nameZh,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    item.lineDiscountCents > 0
                        ? '${formatRm(item.grossCents)} → ${formatRm(item.lineTotalCents)} (−${formatRm(item.lineDiscountCents)})'
                        : formatRm(item.lineTotalCents),
                    style: const TextStyle(fontSize: 13),
                  ),
                  TextButton(
                    onPressed: onDiscount,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '行折扣 / Discount',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, color: CnkhColors.danger),
            ),
            _QtyBtn(icon: Icons.remove, onTap: onMinus),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${item.qty}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _QtyBtn(icon: Icons.add, onTap: onPlus),
          ],
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: CnkhColors.softBlue,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: CnkhColors.navy),
        ),
      ),
    );
  }
}
