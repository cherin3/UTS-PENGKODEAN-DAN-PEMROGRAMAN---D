-- RPC untuk Supabase: supabase.rpc('create_voucher', {...})
-- Header + semua baris + POST dalam SATU transaksi (atomik).
CREATE OR REPLACE FUNCTION create_voucher(
    p_date DATE, p_ref TEXT, p_desc TEXT, p_user TEXT, p_lines JSONB
) RETURNS JSONB AS $$
DECLARE v_id INT; v_hash TEXT;
BEGIN
    INSERT INTO journal_headers(trx_date, reference_no, description, created_by)
    VALUES (p_date, p_ref, p_desc, p_user) RETURNING header_id INTO v_id;

    INSERT INTO journal_lines(header_id, account_id, debit, credit)
    SELECT v_id, (x->>'account_id')::int,
           COALESCE((x->>'debit')::numeric,0), COALESCE((x->>'credit')::numeric,0)
      FROM jsonb_array_elements(p_lines) x;

    v_hash := post_journal(v_id);   -- gagal jika tidak seimbang -> semua di-rollback
    RETURN jsonb_build_object('header_id', v_id, 'reference_no', p_ref, 'hash_checksum', v_hash);
END $$ LANGUAGE plpgsql;
