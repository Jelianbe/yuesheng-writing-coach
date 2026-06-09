-- 016: CHECK 约束保障（通过触发器实现）
-- SQLite 不支持 ALTER TABLE ADD CHECK，使用 BEFORE INSERT/UPDATE 触发器替代：
--   - diagnosis_results.confidence 必须为 [0, 100]

CREATE TRIGGER IF NOT EXISTS trg_diagnosis_confidence_insert
BEFORE INSERT ON diagnosis_results
FOR EACH ROW
WHEN NEW.confidence < 0 OR NEW.confidence > 100
BEGIN
    SELECT RAISE(ABORT, 'diagnosis_results.confidence must be between 0 and 100');
END;

CREATE TRIGGER IF NOT EXISTS trg_diagnosis_confidence_update
BEFORE UPDATE OF confidence ON diagnosis_results
FOR EACH ROW
WHEN NEW.confidence < 0 OR NEW.confidence > 100
BEGIN
    SELECT RAISE(ABORT, 'diagnosis_results.confidence must be between 0 and 100');
END;
