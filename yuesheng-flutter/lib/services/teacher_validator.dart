// ─────────────────────────────────────────────────────────────
// Teacher Validator
// 复刻 yuesheng-android/src/services/teacher-validator.ts
//
// Schema 校验 + 业务一致性（decision↔task、判决词、症候ID泄漏）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';

part 'teacher_validator_types.dart';
part 'teacher_validator_schema.dart';
part 'teacher_validator_consistency.dart';
