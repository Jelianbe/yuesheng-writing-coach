# Working Example — Flutter LLM Coach Validation

Concrete Dart scaffolding distilled from a real Flutter writing-coach app
(yuesheng-flutter, Flutter + Riverpod + drift). The method generalizes to any
LLM-coach app; adapt the prompt/parser names to your project.

## 1. Corpus fixture format (`test/fixtures/corpus_A1_p003.txt`)

One file per case. Free-form natural language first (display + reasoning), then
the protocol blocks the model would emit:

```
（这里放学生原文 + 一段自然语言讲解，作为样本，不作断言）

[YS_DIAGNOSIS]
{ "syndromes": [ {"id":"P003","level":"L2",...} ], "primary":"P003",
  "confidence":0.9, "suggested_actions":[...] }

（教学反馈的自然语言，仅作样本）

[YS_TEACHER]
{ "teaching_decision":"train", "teaching_reason":"...",
  "natural_language":"（先肯定后改进，无判决词、无 P0xx 泄漏）",
  "training_task": { "target_syndrome_id":"P003", "task_type":"rewrite",
                     "difficulty":"medium", ... } }
```

Naming convention: `corpus_<id>_p<NNN>.txt` (single syndrome) or
`corpus_<id>_p<NNN>_p<MMM>.txt` (conflict pair). Keep the natural-language
blocks as *samples only* — never assert on them.

## 2. SequenceFakeLlmClient (replicates multi-round LLM calls)

The app parses the diagnosis, then re-calls the LLM for the teaching decision.
A plain fake that returns the same string breaks the flow. Return a different
queued response per call:

```dart
class SequenceFakeLlmClient extends LlmClient {
  final List<String> _responses;
  int _i = 0;
  SequenceFakeLlmClient(this._responses);
  @override
  Stream<ChatMessage> streamChat(/* args */) async* {
    final body = _responses[_i.clamp(0, _responses.length - 1)];
    if (_i < _responses.length - 1) _i++;
    yield ChatMessage(role: ChatRole.assistant, content: body);
  }
}
```

Build it with `[diagnosisResponse, teacherResponse]` split at the `[YS_TEACHER]`
marker so the teacher call receives only the teacher block.

## 3. In-memory DB + ChatService (data-flow test)

```dart
final db = AppDatabase.forTesting(NativeDatabase.memory());
final chat = buildChatService(db, SequenceFakeLlmClient([diag, teacher]));
await chat.sendMessage(sessionId, userText, subphase: 'diagnosis');
// assert: diagnosis committed, primary first, no fabricated syndrome
await chat.sendMessage(sessionId, userText, subphase: 'feedback');
// assert: onTrainingResult fired, training history written, subphase reset
```

## 4. Dual-mode live harness skeleton

```dart
void main() {
  group('self-check (offline)', () {
    test('case P003 exact', () async {
      // FakeLlmClient feeds fixture; assert structured + compliance, exact
    });
  });

  group('live real LLM', () {
    final key = Platform.environment['DEEPSEEK_API_KEY'];
    test('case P003 live', () async {
      if (key == null) {
        markTestSkipped('DEEPSEEK_API_KEY 未设置');
        return;
      }
      // real LlmClient; assert same structured fields, looser tolerance
    }, tags: ['live']);
  });
}
```

Mock `flutter_secure_storage` (inject the env key as `yuesheng_api_key`) and
`connectivity_plus` so the real client constructs in tests without network
dependency at build time.

## 5. Anti-hardcode guard (assert the injected prompt)

```dart
test('injected teacher prompt forbids fixed-script templates', () {
  final prompt = kTeacherSkillContent; // the string ACTUALLY sent to the LLM
  expect(prompt.contains('不使用固定话术模板'), isTrue);
  expect(prompt.contains('教原理而非标准答案'), isTrue);
  expect(prompt.contains('AI 自主组织话术'), isTrue);
});
```

Confirm the gap is real first: run with the directives absent → red; add them to
the actually-injected prompt (not a separate unused spec file) → green.

## 6. Snapshot baseline shape (structured only)

```json
{
  "cases": {
    "B6": {
      "diagnosis": { "parsed": true, "syndromeIds": ["P041","P012"],
                     "primarySyndromeId": "P041", "confidence": 0.9 },
      "teacher":   { "teachingDecision": "train", "hasTask": true,
                     "taskTargetSyndromeId": "P041", "taskType": "rewrite" },
      "consistency": { "passed": true, "violationCount": 0 },
      "compliance":  { "naturalLanguageLeaksP0xx": false }
    }
  }
}
```

Regenerate with `UPDATE_SNAPSHOTS=true flutter test ...`; default mode diffs and
fails on drift. Natural-language text is intentionally absent.
