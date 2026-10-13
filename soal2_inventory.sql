-- ============================================================
-- SOAL 2 - Trigger persediaan perpetual (butuh soal1_schema.sql
-- untuk bagian jurnal otomatis)
-- ============================================================
DROP TABLE IF EXISTS inventory_transactions, inventory_items CASCADE;

CREATE TABLE inventory_items (
    item_id    VARCHAR(10) PRIMARY KEY,
    item_name  VARCHAR(100),
    stock_qty  INT NOT NULL DEFAULT 0,
    unit_cost  NUMERIC(15,2) NOT NULL
);
CREATE TABLE inventory_transactions (
    trx_id    SERIAL PRIMARY KEY,
    item_id   VARCHAR(10) REFERENCES inventory_items(item_id),
    trx_type  VARCHAR(10) CHECK (trx_type IN ('PURCHASE','SALE','ADJUSTMENT')),
    qty       INT NOT NULL,
    trx_date  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Konvensi qty:
--   PURCHASE  : qty positif  -> stok bertambah
--   SALE      : qty positif  -> stok berkurang
--   ADJUSTMENT: qty bertanda -> (+) selisih lebih, (-) selisih kurang (opname)
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal() RETURNS trigger AS $$
DECLARE
    v_stock    INT;
    v_cost     NUMERIC(15,2);
    v_delta    INT;
    v_amount   NUMERIC(18,2);
    v_header   INT;
    v_acc_inv  INT; v_acc_cogs INT; v_acc_cash INT;
BEGIN
    -- (a) kunci baris item: transaksi lain pada item ini menunggu (anti race)
    SELECT stock_qty, unit_cost INTO v_stock, v_cost
      FROM inventory_items WHERE item_id = NEW.item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % tidak ditemukan', NEW.item_id;
    END IF;

    v_delta := CASE NEW.trx_type
                 WHEN 'PURCHASE'   THEN  NEW.qty
                 WHEN 'SALE'       THEN -NEW.qty
                 ELSE                    NEW.qty   -- ADJUSTMENT bertanda
               END;
    IF NEW.trx_type IN ('PURCHASE','SALE') AND NEW.qty <= 0 THEN
        RAISE EXCEPTION 'qty % harus > 0 untuk %', NEW.qty, NEW.trx_type;
    END IF;

    -- (b) anti-negative inventory
    IF v_stock + v_delta < 0 THEN
        RAISE EXCEPTION 'Stok % tidak cukup: tersedia %, diminta % (%)',
                        NEW.item_id, v_stock, ABS(v_delta), NEW.trx_type;
    END IF;

    UPDATE inventory_items SET stock_qty = stock_qty + v_delta
     WHERE item_id = NEW.item_id;

    -- Jurnal otomatis (nilai = qty x unit_cost, metode biaya tetap)
    v_amount := ABS(v_delta) * v_cost;
    SELECT account_id INTO v_acc_inv  FROM chart_of_accounts WHERE account_code='1-1300';
    SELECT account_id INTO v_acc_cogs FROM chart_of_accounts WHERE account_code='5-1100';
    SELECT account_id INTO v_acc_cash FROM chart_of_accounts WHERE account_code='2-1100';

    IF v_amount > 0 THEN
        INSERT INTO journal_headers(trx_date, reference_no, description)
        VALUES (NEW.trx_date::date, 'INV-'||NEW.trx_id,
                NEW.trx_type||' '||NEW.item_id||' qty '||NEW.qty)
        RETURNING header_id INTO v_header;

        IF NEW.trx_type = 'PURCHASE' OR (NEW.trx_type='ADJUSTMENT' AND v_delta > 0) THEN
            -- Dr Persediaan / Cr Utang Usaha
            INSERT INTO journal_lines(header_id,account_id,debit,credit) VALUES
              (v_header, v_acc_inv, v_amount, 0),
              (v_header, v_acc_cash, 0, v_amount);
        ELSE
            -- SALE / ADJUSTMENT(-): Dr HPP / Cr Persediaan
            INSERT INTO journal_lines(header_id,account_id,debit,credit) VALUES
              (v_header, v_acc_cogs, v_amount, 0),
              (v_header, v_acc_inv, 0, v_amount);
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_after_insert
    AFTER INSERT ON inventory_transactions
    FOR EACH ROW EXECUTE FUNCTION trg_update_stock_and_journal();

INSERT INTO inventory_items VALUES ('BRG001','Laptop Kantor',1,8000000);
