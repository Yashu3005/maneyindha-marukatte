import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class _Msg {
  final bool fromUser;
  final String text;
  final List<Map> products;
  final List<Map> businesses;
  final bool isError;
  _Msg(this.fromUser, this.text, {this.products = const [], this.businesses = const [], this.isError = false});
}

const _suggestions = [
  'How do I track my order?',
  'Which coupons can I use?',
  'Show me home-made snacks',
  'How do badges work?',
];

/// Help assistant for customers. Every answer comes from the server's AI provider; when AI is not
/// configured the screen says so instead of inventing a reply.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    // Recent turns give the assistant context; error bubbles are not part of the conversation.
    final history = _msgs
        .where((m) => !m.isError && m.text.isNotEmpty)
        .toList()
        .reversed
        .take(10)
        .toList()
        .reversed
        .map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text.length > 1500 ? m.text.substring(0, 1500) : m.text})
        .toList();
    setState(() {
      _msgs.add(_Msg(true, text));
      _busy = true;
      _input.clear();
    });
    _toEnd();
    try {
      final res = await ApiClient.dio.post('/ai/assistant', data: {'message': text, 'history': history});
      final d = (res.data['data'] as Map?) ?? const {};
      setState(() => _msgs.add(_Msg(
            false,
            d['reply']?.toString() ?? '',
            products: ((d['products'] as List?) ?? const []).whereType<Map>().toList(),
            businesses: ((d['businesses'] as List?) ?? const []).whereType<Map>().toList(),
          )));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final errCode = (body is Map && body['error'] is Map) ? body['error']['code']?.toString() : null;
      setState(() => _msgs.add(_Msg(
            false,
            errCode == 'AI_NOT_CONFIGURED'
                ? 'The assistant is not switched on for this app yet.'
                : status == 429
                    ? 'You have asked a lot of questions in a short time. Please try again a little later.'
                    : apiError(e),
            isError: true,
          )));
    } catch (e) {
      setState(() => _msgs.add(_Msg(false, apiError(e), isError: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Help assistant')),
      body: !auth.isLoggedIn
          ? Center(
              child: FilledButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Sign in to chat with the assistant')),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(children: [
                  Expanded(
                    child: _msgs.isEmpty
                        ? ListView(controller: _scroll, padding: const EdgeInsets.all(20), children: [
                            const SizedBox(height: 24),
                            Text('Hi ${auth.name.split(' ').first}! 👋',
                                style: serif(26), textAlign: TextAlign.center),
                            const SizedBox(height: 6),
                            Text('Ask me about orders, coupons, badges, or what home-made treats are near you.',
                                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 20),
                            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                              for (final s in _suggestions)
                                ActionChip(label: Text(s), onPressed: () => _send(s)),
                            ]),
                          ])
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            itemCount: _msgs.length + (_busy ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _msgs.length) return const _Typing();
                              return _Bubble(msg: _msgs[i]);
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            maxLength: 500,
                            minLines: 1,
                            maxLines: 3,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(hintText: 'Type your question…', counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Send',
                          onPressed: _busy ? null : () => _send(),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final mine = msg.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? MMColors.deepOlive : (msg.isError ? MMColors.blush : MMColors.cream),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(msg.text,
              style: TextStyle(color: mine ? MMColors.cream : Colors.black87, height: 1.35)),
          if (msg.businesses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in msg.businesses)
                ActionChip(
                  avatar: const Icon(Icons.storefront_outlined, size: 16),
                  label: Text(b['name']?.toString() ?? 'Shop'),
                  onPressed: () => context.push('/business/${b['id']}'),
                ),
            ]),
          ],
          if (msg.products.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final p in msg.products)
              InkWell(
                onTap: () => context.push('/product/${p['id']}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(width: 44, height: 44, child: NetImage(p['image']?.toString())),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${rupees(p['price'])}${p['shop'] != null ? ' · ${p['shop']}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}
