-- ============================================================
-- SOAL 1.2 - Skema General Ledger + Integritas (PostgreSQL)
-- ============================================================
DROP TABLE IF EXISTS journal_lines, journal_headers, chart_of_accounts CASCADE;

CREATE TABLE chart_of_accounts (
    account_id      SERIAL PRIMARY KEY,
    account_code    VARCHAR(20)  NOT NULL UNIQUE,
    account_name    VARCHAR(100) NOT NULL,
    normal_balance  CHAR(1)      NOT NULL CHECK (normal_balance IN ('D','K')),
    report_class    VARCHAR(20)  NOT NULL
        CHECK (report_class IN ('ASET','LIABILITAS','EKUITAS','PENDAPATAN','BEBAN'))
);

CREATE TABLE journal_headers (
    header_id       SERIAL PRIMARY KEY,
    trx_date        DATE         NOT NULL,
    reference_no    VARCHAR(50)  NOT NULL UNIQUE,   -- nomor bukti
    description     TEXT,
    status_posting  VARCHAR(10)  NOT NULL DEFAULT 'DRAFT'
        CHECK (status_posting IN ('DRAFT','POSTED'))
);

CREATE TABLE journal_lines (
    line_id     SERIAL PRIMARY KEY,
    header_id   INT NOT NULL
        REFERENCES journal_headers(header_id) ON DELETE RESTRICT,
    account_id  INT NOT NULL
        REFERENCES chart_of_accounts(account_id) ON DELETE RESTRICT,
    debit       NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (debit  >= 0),
    credit      NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    -- tidak boleh nol-nol, dan tidak boleh dua-duanya terisi
    CONSTRAINT chk_not_both_zero CHECK (NOT (debit = 0 AND credit = 0)),
    CONSTRAINT chk_one_side_only CHECK (debit = 0 OR credit = 0)
);
CREATE INDEX idx_lines_header  ON journal_lines(header_id);
CREATE INDEX idx_lines_account ON journal_lines(account_id);

-- ------------------------------------------------------------
-- BONUS: penegakan Debit = Kredit di level database
-- (CHECK biasa tidak bisa, karena butuh agregat lintas baris).
-- Constraint trigger DEFERRED: dicek saat COMMIT.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_journal_balanced() RETURNS trigger AS $$
DECLARE
    v_header INT := COALESCE(NEW.header_id, OLD.header_id);
    v_debit  NUMERIC; v_credit NUMERIC; v_cnt INT;
BEGIN
    SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0), COUNT(*)
      INTO v_debit, v_credit, v_cnt
      FROM journal_lines WHERE header_id = v_header;
    IF v_cnt > 0 AND v_debit <> v_credit THEN
        RAISE EXCEPTION 'Jurnal % tidak seimbang: debit=% kredit=%',
                        v_header, v_debit, v_credit;
    END IF;
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_journal_balanced
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balanced();

-- Data master contoh (dipakai Soal 2 & 3)
INSERT INTO chart_of_accounts(account_code, account_name, normal_balance, report_class) VALUES
 ('1-1100','Kas',                      'D','ASET'),
 ('1-1300','Persediaan Barang Dagang', 'D','ASET'),
 ('2-1100','Utang Usaha',              'K','LIABILITAS'),
 ('4-1100','Pendapatan Penjualan',     'K','PENDAPATAN'),
 ('5-1100','Beban Pokok Pendapatan',   'D','BEBAN'),
 ('6-1100','Beban Listrik',            'D','BEBAN');
