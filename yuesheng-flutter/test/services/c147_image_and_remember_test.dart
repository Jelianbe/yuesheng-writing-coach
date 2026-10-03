// ─────────────────────────────────────────────────────────────
// c147_image_and_remember_test — C147 图片直读链 + 记一下落库测试
//
// 覆盖：
//   1. isImageFile：图片扩展名识别 / 文档扩展名拒绝
//   2. pendingAttachmentsProvider：add → drain 一次性消费并清空
//   3. record_entry.proposePending 不传 targetSection → 默认 ''（C143 向后兼容）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/record_entry_repository.dart';
import 'package:writingcoach/providers/chat_attachment_provider.dart';
import 'package:writingcoach/services/file_parser.dart';
import 'package:writingcoach/services/llm_client.dart';

void main() {
  test('#1 isImageFile：图片识别 / 文档拒绝', () {
    expect(isImageFile('场景.png'), isTrue);
    expect(isImageFile('照片.JPG'), isTrue);
    expect(isImageFile('插画.jpeg'), isTrue);
    expect(isImageFile('图.gif'), isTrue);
    expect(isImageFile('稿.txt'), isFalse);
    expect(isImageFile('章节.md'), isFalse);
    expect(isImageFile('小说.docx'), isFalse);
    expect(isImageFile('无扩展名'), isFalse);
  });

  test('#2 pendingAttachmentsProvider：add → drain 一次性消费并清空', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(pendingAttachmentsProvider.notifier);
    expect(c.read(pendingAttachmentsProvider), isEmpty);

    notifier.add(const ChatContentBlock.imageUrl('data:image/png;base64,AAA'));
    notifier.add(const ChatContentBlock.imageUrl('data:image/jpeg;base64,BBB'));
    expect(c.read(pendingAttachmentsProvider).length, 2);

    final drained = notifier.drain();
    expect(drained.length, 2);
    // drain 后清空（发送一次性消费）
    expect(c.read(pendingAttachmentsProvider), isEmpty);
  });

  test('#3 proposePending 不传 targetSection → 默认 ""（C143 向后兼容）', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = RecordEntryRepository(db);
    // C143 既有调用形态（无 targetSection）：不得因 v45 改动而回归
    final e = await repo.proposePending(manuscriptId: 'm1', excerpt: '阿禾推开门。');
    expect(e.targetSection, '');
    expect(e.status, RecordEntryStatus.pending);
  });
}
