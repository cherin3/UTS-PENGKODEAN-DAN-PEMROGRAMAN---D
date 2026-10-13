-- ============================================================
-- SOAL 3.2 - Audit trail & immutability (butuh soal1_schema.sql)
-- ============================================================
ALTER TABLE journal_headers
    ADD COLUMN IF NOT EXISTS created_by    TEXT        NOT NULL DEFAULT current_user,
    ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS posted_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hash_checksum CHAR(64),
    ADD COLUMN IF NOT EXISTS reversal_of   INT UNIQUE REFERENCES journal_headers(header_id) ON DELETE RESTRICT;
    -- UNIQUE pada reversal_of: satu jurnal hanya bisa di-storno sekali

CREATE TABLE IF NOT EXISTS audit_log (
    log_id      BIGSERIAL PRIMARY KEY,
    table_name  TEXT NOT NULL,
    record_id   INT  NOT NULL,
    action      TEXT NOT NULL,
    old_data    JSONB,
    new_data    JSONB,
    changed_by  TEXT NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- audit_log sendiri append-only
CREATE OR REPLACE FUNCTION fn_audit_append_only() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'audit_log bersifat append-only'; END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_audit_immutable ON audit_log;
CREATE TRIGGER trg_audit_immutable BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_append_only();

-- Hash: SHA-256 atas isi header + seluruh baris (urut tetap)
CREATE OR REPLACE FUNCTION fn_compute_hash(p_header INT) RETURNS TEXT AS $$
    SELECT encode(sha256(convert_to(
        h.header_id||'|'||h.trx_date||'|'||h.reference_no||'|'||COALESCE(h.description,'')
        ||'|'||h.created_by||'|'||COALESCE(h.reversal_of::text,'')||'|'||
        COALESCE((SELECT string_agg(l.account_id||':'||l.debit||':'||l.credit, ';' ORDER BY l.line_id)
                    FROM journal_lines l WHERE l.header_id = h.header_id),''),
        'UTF8')), 'hex')
    FROM journal_headers h WHERE h.header_id = p_header;
$$ LANGUAGE sql STABLE;

-- ---- Penjaga HEADER ----
CREATE OR REPLACE FUNCTION fn_guard_header() RETURNS trigger AS $$
DECLARE v_d NUMERIC; v_k NUMERIC; v_n INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status_posting = 'POSTED' THEN
            RAISE EXCEPTION 'Jurnal % sudah POSTED: tidak boleh dihapus. Buat jurnal pembalik (storno).', OLD.reference_no;
        END IF;
        RETURN OLD;
    END IF;
    -- UPDATE
    IF OLD.status_posting = 'POSTED' THEN
        RAISE EXCEPTION 'Jurnal % sudah POSTED: tidak boleh diubah. Buat jurnal pembalik (storno).', OLD.reference_no;
    END IF;
    IF NEW.status_posting = 'POSTED' THEN          -- transisi DRAFT -> POSTED
        SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0), COUNT(*)
          INTO v_d, v_k, v_n FROM journal_lines WHERE header_id = OLD.header_id;
        IF v_n < 2 OR v_d <> v_k THEN
            RAISE EXCEPTION 'Tidak bisa POST: baris=% debit=% kredit=%', v_n, v_d, v_k;
        END IF;
        NEW.posted_at := now();
        NEW.hash_checksum := fn_compute_hash(OLD.header_id);  -- hash dihitung dari data yang tersimpan
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_guard_header ON journal_headers;
CREATE TRIGGER trg_guard_header BEFORE UPDATE OR DELETE ON journal_headers
    FOR EACH ROW EXECUTE FUNCTION fn_guard_header();

-- ---- Penjaga LINES: jurnal POSTED tak boleh disentuh ----
CREATE OR REPLACE FUNCTION fn_guard_lines() RETURNS trigger AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT status_posting INTO v_status FROM journal_headers
     WHERE header_id = COALESCE(NEW.header_id, OLD.header_id);
    IF v_status = 'POSTED' THEN
        RAISE EXCEPTION 'Baris jurnal milik jurnal POSTED tidak boleh di-% . Gunakan storno.', TG_OP;
    END IF;
    RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_guard_lines ON journal_lines;
CREATE TRIGGER trg_guard_lines BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW EXECUTE FUNCTION fn_guard_lines();

-- ---- Log audit header ----
CREATE OR REPLACE FUNCTION fn_log_header() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit_log(table_name, record_id, action, old_data, new_data)
    VALUES ('journal_headers', COALESCE(NEW.header_id, OLD.header_id), TG_OP,
            CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END);
    RETURN NULL;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_log_header ON journal_headers;
CREATE TRIGGER trg_log_header AFTER INSERT OR UPDATE OR DELETE ON journal_headers
    FOR EACH ROW EXECUTE FUNCTION fn_log_header();

-- ---- RPC: post jurnal ----
CREATE OR REPLACE FUNCTION post_journal(p_header INT) RETURNS TEXT AS $$
    UPDATE journal_headers SET status_posting='POSTED' WHERE header_id=p_header
    RETURNING hash_checksum;
$$ LANGUAGE sql;

-- ---- RPC: jurnal pembalik (storno) ----
CREATE OR REPLACE FUNCTION reverse_journal(p_header INT, p_user TEXT DEFAULT current_user)
RETURNS INT AS $$
DECLARE v_old journal_headers%ROWTYPE; v_new INT;
BEGIN
    SELECT * INTO v_old FROM journal_headers WHERE header_id = p_header FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Jurnal % tidak ada', p_header; END IF;
    IF v_old.status_posting <> 'POSTED' THEN
        RAISE EXCEPTION 'Hanya jurnal POSTED yang di-storno (ini masih %)', v_old.status_posting;
    END IF;
    IF EXISTS (SELECT 1 FROM journal_headers WHERE reversal_of = p_header) THEN
        RAISE EXCEPTION 'Jurnal % sudah pernah di-storno', v_old.reference_no;
    END IF;
    INSERT INTO journal_headers(trx_date, reference_no, description, created_by, reversal_of)
    VALUES (CURRENT_DATE, 'REV-'||v_old.reference_no, 'Storno '||v_old.reference_no, p_user, p_header)
    RETURNING header_id INTO v_new;          -- unique(reversal_of) menolak storno ganda
    INSERT INTO journal_lines(header_id, account_id, debit, credit)
    SELECT v_new, account_id, credit, debit  -- debit & kredit DITUKAR
      FROM journal_lines WHERE header_id = p_header;
    PERFORM post_journal(v_new);
    RETURN v_new;
END $$ LANGUAGE plpgsql;

-- ---- Verifikasi integritas semua jurnal POSTED ----
CREATE OR REPLACE VIEW v_integrity_check AS
SELECT header_id, reference_no, hash_checksum,
       fn_compute_hash(header_id) AS recomputed,
       hash_checksum = fn_compute_hash(header_id) AS intact
  FROM journal_headers WHERE status_posting='POSTED';
