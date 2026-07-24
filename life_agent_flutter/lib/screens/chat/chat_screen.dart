import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/chat_models.dart';
import '../../models/memory_models.dart';
import '../../providers/navigation_provider.dart';
import '../../services/adaptive_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_text.dart';
import '../../utils/error_handler.dart';
import '../../widgets/auth_modal.dart';
import '../../widgets/chat_message_bubble.dart';
import '../../widgets/assistant_status_pill.dart';
import '../../widgets/guided_entry_panel.dart';
import '../../widgets/app_settings_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;

  String? _activeConversationId;

  // Save-as-plan state
  bool _savingPlan = false;
  String? _creatingPlanId;

  // Phase-1 extracted fields waiting for Phase-2 answers
  ExtractedPlanFields? _pendingExtractedFields;
  // ID of the MCQ bubble currently displayed (so we can replace it)
  String? _mcqBubbleId;
  // Spinner shown inside the MCQ card's Build button
  bool _mcqGenerating = false;

  // Guided entry
  GuidedEntryTab _activeTab = GuidedEntryTab.career;

  // Toast
  String? _toastMsg;

  // Inline editing
  int? _editingIndex;

  // Track last loaded conversation to avoid double-loading
  String? _lastLoadedConvId;

  String _llmProvider = 'mistral';

  @override
  void initState() {
    super.initState();
    _loadLlmProvider();
    // Check for pending chat message on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingMessage();
    });
  }

  void _checkPendingMessage() {
    final pending = ref.read(pendingChatMessageProvider);
    if (pending != null) {
      ref.read(pendingChatMessageProvider.notifier).state = null;
      _sendMessage(pending, source: 'today');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadLlmProvider() async {
    try {
      final res = await ApiService().getJson('/api/settings/llm');
      if (mounted) {
        setState(() {
          _llmProvider = res['provider'] ?? 'mistral';
        });
      }
    } catch (_) {}
  }

  Future<void> _updateLlmProvider(String provider) async {
    try {
      await ApiService().postJson('/api/settings/llm', {
        'provider': provider,
        'model': provider == 'openai' ? 'gpt-4o-mini' : (provider == 'gemini' ? 'gemini-2.0-flash' : 'mistral-small-latest'),
      });
      if (mounted) {
        setState(() {
          _llmProvider = provider;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Switched to ${provider.toUpperCase()}')));
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Widget _buildModelSelector() {
    return PopupMenuButton<String>(
      initialValue: _llmProvider,
      tooltip: 'Select AI Model',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.smart_toy_outlined, size: 14, color: context.colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              _llmProvider.toUpperCase(),
              style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: context.colors.textSecondary),
          ],
        ),
      ),
      onSelected: (val) {
        if (val == 'settings') {
          showAppSettingsDialog(context);
        } else {
          _updateLlmProvider(val);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'mistral', child: Text('Mistral', style: TextStyle(fontSize: 13))),
        PopupMenuItem(value: 'openai', child: Text('OpenAI', style: TextStyle(fontSize: 13))),
        PopupMenuItem(value: 'gemini', child: Text('Gemini', style: TextStyle(fontSize: 13))),
        PopupMenuItem(value: 'groq', child: Text('Groq', style: TextStyle(fontSize: 13))),
        PopupMenuItem(value: 'ollama', child: Text('Ollama', style: TextStyle(fontSize: 13))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings, size: 16), SizedBox(width: 8), Text('API Keys...', style: TextStyle(fontSize: 13))])),
      ],
    );
  }

  Future<void> _sendMessage(String content, {String source = 'chat'}) async {
    if (content.trim().isEmpty) return;

    // Require auth before talking with AI
    final authed = await requireAuth(context, ref, () {});
    if (!authed) return;

    final userMsg = ChatMessage(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: content.trim(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, userMsg];
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      // Build history for context (previous messages)
      final history = _messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final sessionContext = SessionContext(activeTab: 'chat');
      final res = await sendMessage(
        content.trim(),
        sessionContext,
        conversationId: _activeConversationId,
        history: history,
        source: source,
      );

      final replyContent = normalizeReplyText(res['reply']);

      final botMsg = ChatMessage(
        id: 'bot-${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: replyContent,
        createdAt: DateTime.now(),
        actions: (res['actions'] as List?)
            ?.map((a) => ChatAction.fromJson(a as Map<String, dynamic>))
            .toList(),
        mentionedPlan: res['mentioned_plan'] as String?,
      );

      final updatedMessages = [..._messages, botMsg];
      setState(() => _messages = updatedMessages);
      _scrollToBottom();



      // Auto-save conversation
      _saveConversation(updatedMessages, content.trim());
    } catch (e) {
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: 'err-${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            content: 'Error: $e',
            createdAt: DateTime.now(),
          ),
        ];
      });
      _scrollToBottom();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEditSubmit(int index, String newText) async {
    if (newText.trim().isEmpty) {
      setState(() => _editingIndex = null);
      return;
    }

    final authed = await requireAuth(context, ref, () {});
    if (!authed) return;

    setState(() {
      _editingIndex = null;
      // Update the user message
      final editedMsg = ChatMessage(
        id: _messages[index].id,
        role: 'user',
        content: newText.trim(),
        createdAt: _messages[index].createdAt,
      );
      // Truncate list up to the edited message
      _messages = _messages.sublist(0, index);
      _messages.add(editedMsg);
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final history = _messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final sessionContext = SessionContext(activeTab: 'chat');
      final res = await sendMessage(
        newText.trim(),
        sessionContext,
        conversationId: _activeConversationId,
        history: history,
        source: 'chat',
      );

      final replyContent = normalizeReplyText(res['reply']);
      final botMsg = ChatMessage(
        id: 'bot-${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: replyContent,
        createdAt: DateTime.now(),
        actions: (res['actions'] as List?)
            ?.map((a) => ChatAction.fromJson(a as Map<String, dynamic>))
            .toList(),
        mentionedPlan: res['mentioned_plan'] as String?,
      );

      final updatedMessages = [..._messages, botMsg];
      setState(() => _messages = updatedMessages);
      _scrollToBottom();

      _saveConversation(updatedMessages, newText.trim());
    } catch (e) {
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: 'err-${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            content: 'Error: $e',
            createdAt: DateTime.now(),
          ),
        ];
      });
      _scrollToBottom();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConversation(
    List<ChatMessage> msgs,
    String firstContent,
  ) async {
    try {
      if (_activeConversationId == null) {
        final title =
            firstContent.split(' ').take(6).join(' ') +
            (firstContent.split(' ').length > 6 ? '...' : '');
        final conv = await createConversation(title: title);
        _activeConversationId = conv.id;
      }
      // Save messages to backend via PATCH
      final messagesPayload = msgs
          .map(
            (m) => <String, dynamic>{
              'id': m.id,
              'role': m.role,
              'content': m.content,
            },
          )
          .toList();
      await ApiService().patchJson(
        '/api/conversations/$_activeConversationId',
        {'messages': messagesPayload},
      );
    } catch (_) {}
  }

  // ── Save as Plan handler (two-phase) ──────────────────────────────────────

  Future<void> _handleSaveAsPlan() async {
    if (_messages.isEmpty) return;

    // Require auth before generating plan with AI
    final authed = await requireAuth(context, ref, () {});
    if (!authed) return;

    setState(() => _savingPlan = true);

    try {
      // Phase 1 — extract only from user messages
      final userMessages = _messages
          .where((m) => m.role == 'user')
          .map((m) => m.content)
          .toList();

      final extraction = await extractFieldsFromChat(userMessages);

      if (extraction.ready) {
        // All fields found — go straight to plan generation
        await _generatePlanFromFields(
          GenerateFromChatPayload.fromFields(extraction.extracted, {}),
        );
      } else {
        // Some fields missing — inject an inline MCQ card bubble
        _pendingExtractedFields = extraction.extracted;
        final bubbleId = 'mcq-${DateTime.now().millisecondsSinceEpoch}';
        _mcqBubbleId = bubbleId;
        setState(() {
          _messages = [
            ..._messages,
            ChatMessage(
              id: bubbleId,
              role: 'assistant',
              content: '',
              createdAt: DateTime.now(),
              planFieldQuestions: extraction.missingFields,
              extractedPlanFields: extraction.extracted,
            ),
          ];
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      setState(() => _savingPlan = false);
    }
  }

  /// Called by PlanMcqCard when the user has answered all required missing fields.
  Future<void> _handleMcqComplete(Map<String, String> answers) async {
    if (_pendingExtractedFields == null) return;
    setState(() => _mcqGenerating = true);
    try {
      final payload = GenerateFromChatPayload.fromFields(
        _pendingExtractedFields!,
        answers,
      );
      await _generatePlanFromFields(payload);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _mcqGenerating = false);
    }
  }

  /// Phase-2: sends fully-filled wizard fields → creates plan → navigates.
  Future<void> _generatePlanFromFields(GenerateFromChatPayload payload) async {
    final result = await generatePlanFromChat(payload);
    if (!mounted) return;

    setState(() {
      // Replace MCQ bubble with a confirmation message
      _messages = [
        ..._messages.where((m) => m.id != _mcqBubbleId),
        ChatMessage(
          id: 'plan-${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: result.message.isNotEmpty
              ? result.message
              : 'Your plan is ready! Navigating now…',
          createdAt: DateTime.now(),
        ),
      ];
      _toastMsg = 'Plan created! View it in Plans →';
      _mcqBubbleId = null;
      _pendingExtractedFields = null;
    });

    ref.read(todayRefreshProvider.notifier).state++;
    _scrollToBottom();

    if (result.plan != null) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.push('/plans/${result.plan!.id}');
      });
    }
  }

  Future<void> _handleGeneratePlan(String memoryId) async {
    setState(() => _creatingPlanId = memoryId);
    try {
      final result = await generatePlan(memoryId);
      ref.read(todayRefreshProvider.notifier).state++;
      setState(() => _toastMsg = 'Plan created! View it in Today →');
      // Navigate to plan detail after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.push('/plans/${result.plan.id}');
        }
      });
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      setState(() => _creatingPlanId = null);
    }
  }

  void _handleQuestionSelect(String question) {
    // Auth check is done inside _sendMessage
    _sendMessage(question, source: 'guided');
  }

  Future<void> _loadConversation(String convId) async {
    _lastLoadedConvId = convId;
    ref.read(conversationToLoadProvider.notifier).state = null;
    setState(() => _isLoading = true);
    try {
      final detail = await getConversation(convId);
      setState(() {
        _activeConversationId = detail.id;
        _messages = detail.messages;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorSnackBar(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-dismiss toast
    if (_toastMsg != null) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _toastMsg = null);
      });
    }

    // Listen for conversation-to-load from drawer
    ref.listen<String?>(conversationToLoadProvider, (_, convId) {
      if (convId != null && convId != _lastLoadedConvId) {
        _loadConversation(convId);
      }
    });

    final width = MediaQuery.of(context).size.width;
    final isLargeDesktop = width >= 1200;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        leading: null,
        actions: [
          if (!isLargeDesktop)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => ref.read(sidebarOpenProvider.notifier).state =
                  !ref.read(sidebarOpenProvider),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            children: [
              // Top bar: New Chat + Save as Plan
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildModelSelector(),
                    Row(
                      children: [
                        if (_messages.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _messages = [];
                                _activeConversationId = null;
                                _lastLoadedConvId = null;
                              });
                            },
                            icon: const Icon(Icons.add_comment_outlined, size: 16),
                            label: const Text(
                              'New Chat',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        if (_messages.isNotEmpty)
                          TextButton.icon(
                            onPressed: _savingPlan ? null : _handleSaveAsPlan,
                            icon: _savingPlan
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined, size: 16),
                            label: Text(
                              _savingPlan ? 'Saving…' : 'Save as Plan',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Messages or guided entry
              Expanded(
                child: _messages.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GuidedEntryPanel(
                          activeTab: _activeTab,
                          disabled: _isLoading,
                          onQuestionSelect: _handleQuestionSelect,
                          onTabChange: (tab) =>
                              setState(() => _activeTab = tab),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const AssistantStatusPill(
                              status: AssistantStatus.thinking,
                            );
                          }

                          final msg = _messages[index];
                          return ChatMessageBubble(
                            message: msg,
                            onGeneratePlan: _handleGeneratePlan,
                            creatingPlanId: _creatingPlanId,
                            onViewMemory: () => context.push('/memory'),
                            onMcqComplete: msg.id == _mcqBubbleId
                                ? _handleMcqComplete
                                : null,
                            mcqGenerating:
                                msg.id == _mcqBubbleId && _mcqGenerating,
                            onRewrite: (_) {
                              setState(() => _editingIndex = index);
                            },
                            isEditing: _editingIndex == index,
                            onEditCancel: () =>
                                setState(() => _editingIndex = null),
                            onEditSubmit: (newText) =>
                                _handleEditSubmit(index, newText),
                          );
                        },
                      ),
              ),

              // Toast
              if (_toastMsg != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: context.colors.success.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: context.colors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _toastMsg!,
                          style: TextStyle(
                            color: context.colors.success,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/today'),
                        child: const Text(
                          'View',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Composer
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border(top: BorderSide(color: context.colors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Message Life Agent…',
                              hintStyle: TextStyle(
                                color: context.colors.textMuted,
                              ),
                              filled: true,
                              fillColor: context.colors.background,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: context.colors.accent,
                                ),
                              ),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty && !_isLoading) {
                                _sendMessage(value);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 44,
                        width: 44,
                        child: IconButton.filled(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  final text = _textController.text;
                                  if (text.trim().isNotEmpty) {
                                    _sendMessage(text);
                                  }
                                },
                          icon: const Icon(Icons.send, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
