class AiChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory AiChatMessage.fromMap(Map<dynamic, dynamic> map) {
    return AiChatMessage(
      id: map['id']?.toString() ?? '',
      role: map['role']?.toString() ?? 'assistant',
      content: map['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class AiChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiChatMessage> messages;

  const AiChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  factory AiChatSession.fromMap(Map<dynamic, dynamic> map) {
    final rawMessages = map['messages'];
    return AiChatSession(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'New chat',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map>()
              .map(AiChatMessage.fromMap)
              .where((message) => message.id.isNotEmpty)
              .toList()
          : <AiChatMessage>[],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((message) => message.toMap()).toList(),
    };
  }

  AiChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<AiChatMessage>? messages,
  }) {
    return AiChatSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }
}
