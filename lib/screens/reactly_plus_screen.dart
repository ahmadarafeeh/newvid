import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:Ratedly/services/iap_service.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class ReactlyPlusScreen extends StatefulWidget {
  const ReactlyPlusScreen({Key? key}) : super(key: key);

  @override
  State<ReactlyPlusScreen> createState() => _ReactlyPlusScreenState();
}

class _ReactlyPlusScreenState extends State<ReactlyPlusScreen> {
  final IAPService _iap = IAPService();
  ProductDetails? _product;
  bool _isLoading = true;
  bool _isPurchased = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToPurchaseUpdates();
  }

  Future<void> _loadData() async {
    _isPurchased = await _iap.isPurchased();
    final product = await _iap.getProduct();
    if (mounted) {
      setState(() {
        _product = product;
        _isLoading = false;
      });
    }
  }

  void _listenToPurchaseUpdates() {
    _iap.purchaseStream.listen((List<PurchaseDetails> purchases) async {
      for (var purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          // ✅ Successful purchase or restore
          if (purchase.productID == IAPService.productId) {
            await _iap.setPurchased(true);
            if (mounted) {
              setState(() => _isPurchased = true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reactly+ activated! Thank you.')),
              );
            }
          }
          // Complete the purchase (required)
          await InAppPurchase.instance.completePurchase(purchase);
        } else if (purchase.status == PurchaseStatus.error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Purchase failed: ${purchase.error}')),
            );
          }
          await InAppPurchase.instance.completePurchase(purchase);
        } else if (purchase.status == PurchaseStatus.canceled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Purchase cancelled')),
            );
          }
        }
        if (mounted) setState(() => _isProcessing = false);
      }
    });
  }

  Future<void> _handlePurchase() async {
    if (_isProcessing) return;
    if (_product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Product not available. Try again later.')),
      );
      return;
    }
    setState(() => _isProcessing = true);
    await _iap.buyProduct(_product!);
  }

  Future<void> _handleRestore() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    await _iap.restorePurchases();
    // The stream will handle the update
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = isDark ? Colors.grey[900]! : Colors.grey[100]!;
    final cardColor = isDark ? Colors.grey[850]! : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Reactly+'),
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: textColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.workspace_premium,
                      size: 80, color: Colors.amber),
                  const SizedBox(height: 16),
                  Text(
                    'Unlock Premium Features',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 32),
_buildBenefitTile(
  context,
  icon: Icons.block, // ✅ Replaced Icons.ad_off with Icons.block
  title: 'No Ads',
  description: 'Enjoy an ad‑free experience',
  textColor: textColor,
  cardColor: cardColor,
),
                  _buildBenefitTile(
                    context,
                    icon: Icons.public,
                    title: 'Change Your Country',
                    description: 'Update your country setting anytime',
                    textColor: textColor,
                    cardColor: cardColor,
                  ),
                  _buildBenefitTile(
                    context,
                    icon: Icons.verified,
                    title: 'Apply for Verification',
                    description:
                        'Get the blue checkmark (reviewed by our team)',
                    textColor: textColor,
                    cardColor: cardColor,
                  ),
                  const SizedBox(height: 48),
                  if (_isPurchased)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Reactly+ Active',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _handlePurchase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _product != null
                                    ? 'Upgrade for ${_product!.price}'
                                    : 'Upgrade for \$0.99',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isProcessing ? null : _handleRestore,
                      child: const Text('Restore Purchases'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'One‑time payment – lifetime access',
                    style: TextStyle(color: textColor.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBenefitTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String description,
      required Color textColor,
      required Color cardColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.amber, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColor)),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        fontSize: 14, color: textColor.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
