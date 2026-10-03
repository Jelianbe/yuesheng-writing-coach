// ─────────────────────────────────────────────────────────────
// llm_client 多模态 + 图片输入链路测试（C144 I1 · DoD #3 / #4）
//
// 覆盖：
//   1. ChatMessage 纯文本形态 toJson 逐字节不变（向后兼容锚点）
//   2. contentBlocks → 请求体 messages 元素为 content blocks 数组
//      （type:text / type:image_url，base64 data URI）—— 断言请求 JSON 形态
//   3. image_attachment：bytes→data URI→image_url content block
//   4. R-009/R-027：图片块不携带任何「看图总结/评判」注入文本（零新增 prompt 面）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/image_attachment.dart';
import 'package:writingcoach/services/llm_client.dart';

void main() {
  group('ChatMessage 向后兼容（text-only 形态逐字节不变）', () {
    test('#1 content 纯 String 时 toJson 与改造前一致', () {
      const m = ChatMessage(role: 'user', content: '你好');
      expect(m.toJson(), {'role': 'user', 'content': '你好'});
      // contentBlocks 缺省 → content 仍是 String（不是数组）
      expect(m.toJson()['content'], isA<String>());
    });

    test('#2 system / assistant 纯文本不受影响', () {
      const sys = ChatMessage(role: 'system', content: '规则');
      const asst = ChatMessage(role: 'assistant', content: '回复');
      expect(sys.toJson(), {'role': 'system', 'content': '规则'});
      expect(asst.toJson(), {'role': 'assistant', 'content': '回复'});
    });
  });

  group('多模态 content blocks（DoD #3 · 请求 JSON 形态）', () {
    final pngBytes = Uint8List.fromList(const <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);

    test('#3 图片块 → image_url content block，url 为 base64 data URI', () {
      final block = buildImageContentBlock(pngBytes, 'image/png');
      final json = block.toJson();

      expect(json['type'], 'image_url');
      final imageUrl = (json['image_url'] as Map)['url'] as String;
      expect(imageUrl, startsWith('data:image/png;base64,'));
      // data URI 后半段确为 base64 编码后的字节
      final b64 = imageUrl.split('base64,')[1];
      expect(base64Decode(b64), pngBytes);
    });

    test('#4 ChatMessage 图文消息 → messages 元素 content 为 blocks 数组', () {
      final imageBlock = buildImageContentBlock(pngBytes, 'image/png');
      final m = ChatMessage(
        role: 'user',
        content: '', // 纯文本通道保持空，图文走 contentBlocks
        contentBlocks: [const ChatContentBlock.text('这是我小说开头的截图'), imageBlock],
      );

      // 该消息进入 _buildChatCompletionBody / _buildStreamRequestBody 的
      // messages.map((m)=>m.toJson()) 后，content 必须是数组而非 String。
      final json = m.toJson();
      expect(json['role'], 'user');
      expect(json['content'], isA<List<dynamic>>());

      final blocks = (json['content'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(blocks[0]['type'], 'text');
      expect(blocks[0]['text'], '这是我小说开头的截图');
      expect(blocks[1]['type'], 'image_url');
      final url =
          (blocks[1]['image_url'] as Map<String, dynamic>)['url'] as String;
      expect(url, startsWith('data:image/png;base64,'));
    });

    test('#5 整段请求体 JSON round-trip：messages 含多模态结构', () {
      const m = ChatMessage(
        role: 'user',
        content: '',
        contentBlocks: [
          ChatContentBlock.text('请看这段对话截图'),
          ChatContentBlock.imageUrl('data:image/png;base64,AAA='),
        ],
      );
      // 模拟 body builder：messages.map(toJson) → jsonEncode
      final body = jsonEncode({
        'model': 'test-model',
        'messages': [m.toJson()],
        'stream': false,
      });
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final firstMsg =
          (decoded['messages'] as List<dynamic>).first as Map<String, dynamic>;
      final content = firstMsg['content'] as List<dynamic>;
      expect(content.length, 2);
      expect((content[0] as Map<String, dynamic>)['type'], 'text');
      expect((content[1] as Map<String, dynamic>)['type'], 'image_url');
    });
  });

  group('R-009 / R-027 边界（DoD #4 · 零新增看图 prompt 面）', () {
    final pngBytes = Uint8List.fromList(const <int>[0x89, 0x50, 0x4E, 0x47]);

    test('#6 图片块 JSON 不含 text 字段、不带任何评判性注入文本', () {
      final block = buildImageContentBlock(pngBytes, 'image/png');
      final json = block.toJson();

      // image_url 块只有 {type, image_url{url}}，没有 text 键
      expect(json.containsKey('text'), isFalse);
      expect(json['type'], 'image_url');
    });

    test('#7 仅挂图片的消息序列化后，全文不含「看图/总结/评判/分析这张」指令', () {
      final imageBlock = buildImageContentBlock(pngBytes, 'image/png');
      final m = ChatMessage(
        role: 'user',
        content: '',
        contentBlocks: [imageBlock], // 用户不打字，只甩一张图
      );
      final serialized = jsonEncode(m.toJson());

      // 护栏：图片链路不得夹带任何替作者「看图总结/评判」的指令文本
      expect(serialized.contains('看图'), isFalse);
      expect(serialized.contains('总结这张'), isFalse);
      expect(serialized.contains('评判'), isFalse);
      expect(serialized.contains('分析这张'), isFalse);
      // 且只有一个 image_url 块，没有额外 text 块
      final content = (jsonDecodeSerialized(m)['content']) as List<dynamic>;
      expect(content.length, 1);
      expect((content.first as Map<String, dynamic>)['type'], 'image_url');
    });
  });
}

/// 辅助：再解一次 toJson 便于断定语义结构
Map<String, dynamic> jsonDecodeSerialized(ChatMessage m) =>
    jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
