-- ============================================================
-- SOAL 2.2 - Race condition: stok 1, dua kasir menjual 1 unit
-- ============================================================
DROP TABLE IF EXISTS stok_demo;
CREATE TABLE stok_demo(item_id text primary key, qty int not null CHECK (qty >= 0));
INSERT INTO stok_demo VALUES ('X',1);

-- ---------- VERSI NAIF (SALAH): baca lalu tulis tanpa kunci ----------
-- Kasir A & B sama-sama menjalankan:
--   BEGIN;
--   SELECT qty FROM stok_demo WHERE item_id='X';      -- keduanya lihat qty=1
--   -- aplikasi memutuskan "1 >= 1, boleh jual"
--   INSERT INTO penjualan(...);                        -- keduanya sukses
--   COMMIT;                                            -- terjual 2, stok cuma 1

-- ---------- SOLUSI 1: SELECT ... FOR UPDATE (pessimistic lock) ----------
CREATE OR REPLACE PROCEDURE jual_barang(p_item text, p_qty int, p_delay float DEFAULT 0)
LANGUAGE plpgsql AS $$
DECLARE v_qty int;
BEGIN
    SELECT qty INTO v_qty FROM stok_demo WHERE item_id = p_item FOR UPDATE; -- kasir kedua MENUNGGU di sini
    PERFORM pg_sleep(p_delay);        -- simulasi proses lambat
    IF v_qty < p_qty THEN
        RAISE EXCEPTION 'Stok habis (tersisa %)', v_qty;
    END IF;
    UPDATE stok_demo SET qty = qty - p_qty WHERE item_id = p_item;
END $$;

-- ---------- SOLUSI 2: Isolasi SERIALIZABLE (optimistic) ----------
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
--   SELECT qty ...; UPDATE ...; COMMIT;
--   -- salah satu transaksi gagal: SQLSTATE 40001 (serialization_failure)
--   -- APLIKASI WAJIB retry transaksi yang gagal.
