import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../data/plans.dart';
import '../services/drive_sync.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/choices.dart' show FormatOption;
import '../widgets/common.dart' show AccentButton;

/// The pretend checkout for a tAsikaso+ plan (test mode, while Google Play
/// Billing isn't connected): pay with GCash (mobile number, then a one-time
/// code) or a credit or debit card, review, a moment of "processing", then
/// a receipt. No money moves and nothing typed here is kept: only the plan
/// starts. Returns true when the "payment" went through.
///
/// Test inputs: any GCash number and code work, except the code 000000,
/// which fails; any valid card number works (4242 4242 4242 4242), except
/// 4000 0000 0000 0002, which is declined.
Future<bool> openCheckout(BuildContext context, PlusPlan plan,
    {bool switching = false}) async {
  // A message still showing would sit over the checkout's buttons.
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  final paid = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
        builder: (_) => CheckoutScreen(plan: plan, switching: switching)),
  );
  return paid ?? false;
}

enum PayMethod { gcash, card }

enum _Step { method, gcashNumber, gcashCode, card, review, processing, done, failed }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.plan, this.switching = false});

  final PlusPlan plan;
  final bool switching;

  /// How long "Confirming your payment…" shows.
  static Duration processing = const Duration(milliseconds: 1600);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  _Step _step = _Step.method;
  PayMethod _method = PayMethod.gcash;

  final _mobile = TextEditingController();
  final _code = TextEditingController();
  final _cardName = TextEditingController();
  final _cardNumber = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();

  /// Where the (pretend) receipt goes: the Google account's email when
  /// signed in, else what the user types.
  final _email = TextEditingController(
      text: (DriveSync.instance.email ?? '').contains('@')
          ? DriveSync.instance.email
          : '');
  String? _error;

  /// Filled in when the payment goes through.
  String _reference = '';
  DateTime? _paidAt;

  PlusPlan get _plan => widget.plan;

  /// "₱349.00".
  String get _amount => '${_plan.price}.00';

  @override
  void dispose() {
    for (final c in [_mobile, _code, _cardName, _cardNumber, _expiry, _cvc, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Step step) => setState(() {
        _error = null;
        _step = step;
      });

  /// Back goes one step back; out of the checkout only from the first step
  /// or the receipt.
  void _back() {
    switch (_step) {
      case _Step.method:
        Navigator.of(context).pop(false);
      case _Step.done:
        Navigator.of(context).pop(true);
      case _Step.gcashNumber || _Step.card || _Step.failed:
        _go(_Step.method);
      case _Step.gcashCode:
        _go(_Step.gcashNumber);
      case _Step.review:
        _go(_method == PayMethod.gcash ? _Step.gcashCode : _Step.card);
      case _Step.processing:
        break; // wait for it
    }
  }

  // ---- Checks ----------------------------------------------------------------

  String get _mobileDigits => _mobile.text.replaceAll(RegExp(r'\D'), '');
  String get _cardDigits => _cardNumber.text.replaceAll(RegExp(r'\D'), '');

  void _sendCode() {
    final d = _mobileDigits;
    if (d.length != 10 || !d.startsWith('9')) {
      setState(() => _error = 'Enter your 10-digit GCash number, like 917 123 4567.');
      return;
    }
    _code.clear();
    _go(_Step.gcashCode);
  }

  void _verifyCode() {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    _go(_Step.review);
  }

  void _checkCard() {
    final digits = _cardDigits;
    String? error;
    if (_cardName.text.trim().isEmpty) {
      error = 'Enter the name on the card.';
    } else if (digits.length < 15 || digits.length > 16 || !_luhn(digits)) {
      error = 'That card number doesn\'t look right.';
    } else if (!_expiryOk(_expiry.text)) {
      error = 'Enter an expiry date in the future, like 08/29.';
    } else if (!RegExp(r'^\d{3,4}$').hasMatch(_cvc.text)) {
      error = 'Enter the 3 or 4 digits on the back of the card.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _go(_Step.review);
  }

  static bool _luhn(String digits) {
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      var d = int.parse(digits[digits.length - 1 - i]);
      if (i.isOdd) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return sum % 10 == 0;
  }

  static bool _expiryOk(String text) {
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(text);
    if (m == null) return false;
    final month = int.parse(m[1]!);
    final year = 2000 + int.parse(m[2]!);
    if (month < 1 || month > 12) return false;
    final now = clock.now();
    return DateTime(year, month + 1).isAfter(DateTime(now.year, now.month));
  }

  /// "Visa", "Mastercard", "JCB", "Amex" or "Card".
  String get _brand {
    final d = _cardDigits;
    if (d.startsWith('4')) return 'Visa';
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(d)) return 'Mastercard';
    if (d.startsWith('35')) return 'JCB';
    if (RegExp(r'^3[47]').hasMatch(d)) return 'Amex';
    return 'Card';
  }

  /// "GCash +63 9•• ••• 4567" or "Visa •••• 4242".
  String get _paidWith {
    if (_method == PayMethod.gcash) {
      final d = _mobileDigits;
      return 'GCash +63 ${d.isEmpty ? '' : d[0]}•• ••• ${d.length >= 4 ? d.substring(d.length - 4) : ''}';
    }
    final d = _cardDigits;
    return '$_brand •••• ${d.length >= 4 ? d.substring(d.length - 4) : ''}';
  }

  String get _receiptEmail => _email.text.trim();

  Future<void> _pay() async {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_receiptEmail)) {
      setState(() => _error = 'Enter the email to send your receipt to.');
      return;
    }
    FocusScope.of(context).unfocus();
    _go(_Step.processing);
    await Future<void>.delayed(CheckoutScreen.processing);
    if (!mounted) return;
    final declined = _method == PayMethod.card
        ? _cardDigits == '4000000000000002'
        : _code.text == '000000';
    if (declined) {
      _go(_Step.failed);
      return;
    }
    final random = math.Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    _reference =
        'TSK-${List.generate(8, (_) => chars[random.nextInt(chars.length)]).join()}';
    _paidAt = clock.now();
    AppStore.instance.startPlan(_plan);
    _go(_Step.done);
  }

  // ---- Screens ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.method => 'Checkout',
      _Step.gcashNumber || _Step.gcashCode => 'Pay with GCash',
      _Step.card => 'Card Details',
      _Step.review => 'Review and Pay',
      _Step.processing => 'Paying',
      _Step.done => 'Receipt',
      _Step.failed => 'Payment Declined',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: subPageAppBar(title),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                _Step.method => _methodStep(),
                _Step.gcashNumber => _gcashNumberStep(),
                _Step.gcashCode => _gcashCodeStep(),
                _Step.card => _cardStep(),
                _Step.review => _reviewStep(),
                _Step.processing => _processingStep(),
                _Step.done => _doneStep(),
                _Step.failed => _failedStep(),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// A step: its content, scrolling, with the button(s) under it.
  Widget _page(List<Widget> children, {required List<Widget> bottom}) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: children,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: bottom),
        ),
      ],
    );
  }

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!,
              style: TextStyle(fontSize: 12.5, color: AppColors.streakText)),
        );

  Widget _methodStep() => _page([
        const _TestPaymentNote(),
        const SizedBox(height: 16),
        _OrderSummary(plan: _plan, switching: widget.switching),
        const SizedBox(height: 22),
        Text('Pay With', style: AppText.sectionTitle),
        const SizedBox(height: 10),
        FormatOption(
          icon: AppIcons.wallet,
          title: 'GCash',
          subtitle: 'Pay from your GCash wallet',
          selected: _method == PayMethod.gcash,
          onTap: () => setState(() => _method = PayMethod.gcash),
        ),
        const SizedBox(height: 8),
        FormatOption(
          icon: AppIcons.card,
          title: 'Credit or Debit Card',
          subtitle: 'Visa, Mastercard, JCB or Amex',
          selected: _method == PayMethod.card,
          onTap: () => setState(() => _method = PayMethod.card),
        ),
      ], bottom: [
        AccentButton(
          label: 'Continue',
          onPressed: () =>
              _go(_method == PayMethod.gcash ? _Step.gcashNumber : _Step.card),
        ),
      ]);

  Widget _gcashNumberStep() => _page([
        const _TestPaymentNote(),
        const SizedBox(height: 18),
        const _StepHeader(
          icon: AppIcons.phone,
          title: 'Your GCash number',
          text: "We'll send a one-time code to confirm it's you.",
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _mobile,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: (_) => _sendCode(),
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            prefixText: '+63 ',
            hintText: '917 123 4567',
            border: OutlineInputBorder(),
          ),
        ),
        _errorText(),
        const SizedBox(height: 10),
        Text('Test mode: no text message is sent.',
            style: AppText.statLabel.copyWith(fontSize: 11.5)),
      ], bottom: [
        AccentButton(label: 'Send Code', onPressed: _sendCode),
      ]);

  Widget _gcashCodeStep() {
    final d = _mobileDigits;
    return _page([
      const _TestPaymentNote(),
      const SizedBox(height: 18),
      _StepHeader(
        icon: AppIcons.locked,
        title: 'Enter the code',
        text: 'We sent a 6-digit code to +63 ${d.substring(0, 3)} '
            '${d.substring(3, 6)} ${d.substring(6)}.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 10),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        onSubmitted: (_) => _verifyCode(),
        decoration: const InputDecoration(
          hintText: '······',
          border: OutlineInputBorder(),
        ),
      ),
      _errorText(),
      const SizedBox(height: 10),
      Text('Test mode: any 6 digits work. 000000 shows a failed payment.',
          style: AppText.statLabel.copyWith(fontSize: 11.5)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
                content: Text('Test mode: a new code would be sent now.'))),
          child: const Text('Send a New Code'),
        ),
      ),
    ], bottom: [
      AccentButton(label: 'Verify', onPressed: _verifyCode),
    ]);
  }

  Widget _cardStep() => _page([
        const _TestPaymentNote(),
        const SizedBox(height: 18),
        TextField(
          controller: _cardName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Name on card', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cardNumber,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(16),
            _GroupsFormatter(4, ' '),
          ],
          onChanged: (_) => setState(() {}), // the brand
          decoration: InputDecoration(
            labelText: 'Card number',
            hintText: '4242 4242 4242 4242',
            border: const OutlineInputBorder(),
            suffixText: _cardDigits.isEmpty ? null : _brand,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _expiry,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  _GroupsFormatter(2, '/', max: 2),
                ],
                decoration: const InputDecoration(
                    labelText: 'Expiry',
                    hintText: 'MM/YY',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _cvc,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                    labelText: 'CVC', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        _errorText(),
        const SizedBox(height: 10),
        Text(
            'Test mode: try 4242 4242 4242 4242 (goes through) or '
            '4000 0000 0000 0002 (declined). Card details are never saved.',
            style: AppText.statLabel.copyWith(fontSize: 11.5, height: 1.4)),
      ], bottom: [
        AccentButton(label: 'Continue', onPressed: _checkCard),
      ]);

  Widget _reviewStep() => _page([
        const _TestPaymentNote(),
        const SizedBox(height: 16),
        _OrderSummary(plan: _plan, switching: widget.switching),
        const SizedBox(height: 16),
        _Card(
          child: Row(
            children: [
              Icon(_method == PayMethod.gcash ? AppIcons.wallet : AppIcons.card,
                  size: 22, color: AppColors.primaryDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paying with', style: AppText.statLabel),
                    const SizedBox(height: 2),
                    Text(_paidWith, style: AppText.itemTitle),
                  ],
                ),
              ),
              TextButton(
                  onPressed: () => _go(_Step.method),
                  child: const Text('Change')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Email for your receipt',
            hintText: 'you@example.com',
            prefixIcon: Icon(AppIcons.email, size: 20, color: AppColors.textSecondary),
            border: const OutlineInputBorder(),
          ),
        ),
        _errorText(),
        const SizedBox(height: 14),
        Text(
          'Your plan renews every ${_plan.per} at ${_plan.price} until you '
          'cancel. Test mode: no money is taken.',
          style: AppText.statLabel.copyWith(fontSize: 11.5, height: 1.4),
        ),
      ], bottom: [
        AccentButton(label: 'Pay $_amount', onPressed: _pay),
      ]);

  Widget _processingStep() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                  strokeWidth: 3.5, color: AppColors.primaryDeep),
            ),
            const SizedBox(height: 18),
            Text('Confirming your payment…', style: AppText.sectionTitle),
            const SizedBox(height: 6),
            Text(_paidWith, style: AppText.statLabel),
          ],
        ),
      );

  Widget _doneStep() {
    final sub = AppStore.instance.subscription;
    String date(DateTime d) => formatNoteDate(d);
    return _page([
      const SizedBox(height: 12),
      Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
              color: AppColors.primarySoft, shape: BoxShape.circle),
          child: Icon(AppIcons.doneCircle, size: 44, color: AppColors.primaryDeep),
        ),
      ),
      const SizedBox(height: 16),
      Text('Payment Successful',
          textAlign: TextAlign.center,
          style: AppText.screenTitle.copyWith(fontSize: 22)),
      const SizedBox(height: 6),
      Text('Welcome to $kPlusName ${_plan.title}!',
          textAlign: TextAlign.center, style: AppText.statLabel.copyWith(fontSize: 13.5)),
      const SizedBox(height: 22),
      _Card(
        child: Column(
          children: [
            _ReceiptRow('Plan', '$kPlusName ${_plan.title}'),
            _ReceiptRow('Amount', _amount),
            _ReceiptRow('Paid with', _paidWith),
            if (_paidAt != null) _ReceiptRow('Date', date(_paidAt!)),
            if (sub?.endsAt != null) _ReceiptRow('Active until', date(sub!.endsAt!)),
            _ReceiptRow('Reference', _reference, last: true),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _Card(
        child: Row(
          children: [
            Icon(AppIcons.email, size: 22, color: AppColors.primaryDeep),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Receipt sent', style: AppText.itemTitle),
                  const SizedBox(height: 2),
                  Text('A copy of this receipt was sent to $_receiptEmail.',
                      style: AppText.statLabel.copyWith(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text('Test payment: no money was taken and no email was really sent.',
          textAlign: TextAlign.center,
          style: AppText.statLabel.copyWith(fontSize: 11.5)),
    ], bottom: [
      AccentButton(
        label: 'Start Using $kPlusName',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ]);
  }

  Widget _failedStep() => _page([
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration:
                BoxDecoration(color: AppColors.streakSoft, shape: BoxShape.circle),
            child: Icon(AppIcons.failed, size: 44, color: AppColors.streakText),
          ),
        ),
        const SizedBox(height: 16),
        Text('Payment Declined',
            textAlign: TextAlign.center,
            style: AppText.screenTitle.copyWith(fontSize: 22)),
        const SizedBox(height: 8),
        Text(
          _method == PayMethod.card
              ? 'Your card was declined, so no money was taken. Try another '
                  'card or pay with GCash.'
              : "GCash couldn't confirm the payment, so no money was taken. "
                  'Try again or pay with a card.',
          textAlign: TextAlign.center,
          style: AppText.statLabel.copyWith(fontSize: 13.5, height: 1.45),
        ),
      ], bottom: [
        AccentButton(label: 'Try Another Way', onPressed: () => _go(_Step.method)),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ]);
}

/// "Test payment: no real money is charged."
class _TestPaymentNote extends StatelessWidget {
  const _TestPaymentNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(AppIcons.suggest, size: 15, color: AppColors.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Test payment: this checkout is pretend. No real money is '
              'charged.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// The plan, its price and when it renews, with the total.
class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.plan, required this.switching});

  final PlusPlan plan;
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final renews = formatNoteDate(plan.endFrom(clock.now()));
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$kPlusName ${plan.title}',
                    style: TextStyle(
                      fontFamily: kHeadingFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    )),
              ),
              Text('${plan.price} / ${plan.per}', style: AppText.itemTitle),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${switching ? 'Switches your plan now. ' : ''}Renews on $renews. '
            'Cancel anytime.',
            style: AppText.statLabel,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Total today', style: AppText.itemTitle)),
              Text('${plan.price}.00',
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

/// An icon, a title and a line, at the top of a step.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 22, color: AppColors.primaryDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.sectionTitle),
              const SizedBox(height: 3),
              Text(text, style: AppText.statLabel.copyWith(height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.label, this.value, {this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: AppText.statLabel)),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right, style: AppText.itemTitle),
          ),
        ],
      ),
    );
  }
}

/// Puts [separator] after every [size] digits ("4242 4242", "08/29"); with
/// [max], only that many times.
class _GroupsFormatter extends TextInputFormatter {
  _GroupsFormatter(this.size, this.separator, {this.max = 99});

  final int size;
  final String separator;
  final int max;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final out = StringBuffer();
    var groups = 0;
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % size == 0 && groups < max) {
        out.write(separator);
        groups++;
      }
      out.write(digits[i]);
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
