-- Testes dos índices (sql/03_indices.sql).
-- O que é conferido:
--   1. Estrutura: cada índice existe, na tabela certa, com as colunas na
--      ordem certa e com UNIQUE / WHERE quando for o caso.
--   2. Uso: cada índice consegue atender à consulta para a qual foi criado.
--      Para não depender do volume de dados nem das estatísticas, a
--      consulta é analisada (EXPLAIN) com o Seq Scan desligado e com os
--      outros índices da tabela escondidos; se o plano usar o índice, a
--      definição dele serve para aquela consulta.
--   3. Comportamento do índice único de e-mail.
--   4. Toda chave estrangeira tem um índice começando pela sua coluna.
-- Rodar manualmente:
--   docker compose exec db psql -f /docker-entrypoint-initdb.d/08_teste_indices.sql
\set ON_ERROR_STOP on
SET client_min_messages = notice;

-- Esconde os resultados dos SELECTs; só aparecem as linhas OK/FALHOU/AVISO e o \echo final
\o /dev/null

BEGIN;

-- Espera que a condição seja verdadeira
CREATE FUNCTION pg_temp.confere(p_nome text, p_cond boolean) RETURNS void AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FALHOU: %', p_nome;
    END IF;
    RAISE NOTICE 'OK: %', p_nome;
END;
$$ LANGUAGE plpgsql;

-- Espera que o comando FALHE (regra bloqueando corretamente)
CREATE FUNCTION pg_temp.espera_erro(p_nome text, p_sql text) RETURNS void AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK: % (bloqueado: %)', p_nome, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FALHOU: % (o comando deveria ter sido bloqueado)', p_nome;
END;
$$ LANGUAGE plpgsql;

-- Definição do índice, sem o nome e o schema, ex.: "agendamento USING btree (inicio)"
CREATE FUNCTION pg_temp.def(p_indice text) RETURNS text AS $$
    SELECT regexp_replace(pg_get_indexdef(p_indice::regclass),
                          '^CREATE (UNIQUE )?INDEX \S+ ON (\S+\.)?', '')
$$ LANGUAGE sql;

-- Plano (EXPLAIN) da consulta com Seq Scan desligado e com os outros
-- índices da mesma tabela removidos. Os índices de PK/UNIQUE/EXCLUDE ficam,
-- porque são de constraints. A remoção é desfeita ao sair do bloco (o
-- RAISE no final cancela a subtransação; a variável com o plano é mantida).
CREATE FUNCTION pg_temp.plano_so_com(p_indice text, p_sql text) RETURNS text AS $$
DECLARE
    v_plano text;
    r record;
BEGIN
    BEGIN
        FOR r IN
            SELECT i.indexrelid::regclass AS idx
            FROM pg_index i
            WHERE i.indrelid = (SELECT indrelid FROM pg_index WHERE indexrelid = p_indice::regclass)
              AND i.indexrelid <> p_indice::regclass
              AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
        LOOP
            EXECUTE 'DROP INDEX ' || r.idx;
        END LOOP;

        SET LOCAL enable_seqscan = off;
        v_plano := '';
        FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
            v_plano := v_plano || r."QUERY PLAN" || E'\n';
        END LOOP;

        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'desfaz';
    EXCEPTION WHEN SQLSTATE 'ZZ001' THEN
        NULL;   -- índices de volta, enable_seqscan restaurado
    END;
    RETURN v_plano;
END;
$$ LANGUAGE plpgsql;

-- O plano usa o índice? Formatos possíveis no EXPLAIN:
--   "Index Scan using <índice> on ...", "Index Only Scan using <índice> on ...",
--   "Bitmap Index Scan on <índice>"
CREATE FUNCTION pg_temp.plano_usa(p_plano text, p_indice text) RETURNS boolean AS $$
    SELECT p_plano ~ ('(using|Index Scan on) ' || p_indice || '( |\n|$)')
$$ LANGUAGE sql;

-- Espera que o índice atenda à consulta
CREATE FUNCTION pg_temp.usa_indice(p_nome text, p_indice text, p_sql text) RETURNS void AS $$
DECLARE
    v_plano text := pg_temp.plano_so_com(p_indice, p_sql);
BEGIN
    IF NOT pg_temp.plano_usa(v_plano, p_indice) THEN
        RAISE EXCEPTION E'FALHOU: % (o plano não usa %)\n%', p_nome, p_indice, v_plano;
    END IF;
    RAISE NOTICE 'OK: %', p_nome;
END;
$$ LANGUAGE plpgsql;

-- Espera que o índice NÃO atenda à consulta (consulta escrita de outro jeito)
CREATE FUNCTION pg_temp.nao_usa_indice(p_nome text, p_indice text, p_sql text) RETURNS void AS $$
DECLARE
    v_plano text := pg_temp.plano_so_com(p_indice, p_sql);
BEGIN
    IF pg_temp.plano_usa(v_plano, p_indice) THEN
        RAISE EXCEPTION E'FALHOU: % (o plano usou %)\n%', p_nome, p_indice, v_plano;
    END IF;
    RAISE NOTICE 'OK: %', p_nome;
END;
$$ LANGUAGE plpgsql;


-- 1. Estrutura
SELECT pg_temp.confere('idx_ag_prof_inicio = agendamento (id_profissional, inicio)',
    pg_temp.def('idx_ag_prof_inicio') = 'agendamento USING btree (id_profissional, inicio)');
SELECT pg_temp.confere('idx_ag_inicio = agendamento (inicio)',
    pg_temp.def('idx_ag_inicio') = 'agendamento USING btree (inicio)');
SELECT pg_temp.confere('idx_ag_cliente_inicio = agendamento (id_cliente, inicio DESC)',
    pg_temp.def('idx_ag_cliente_inicio') = 'agendamento USING btree (id_cliente, inicio DESC)');
SELECT pg_temp.confere('idx_ag_em_aberto = agendamento (inicio) só com AGENDADO/CONFIRMADO',
    pg_temp.def('idx_ag_em_aberto') LIKE 'agendamento USING btree (inicio) WHERE%'
    AND pg_temp.def('idx_ag_em_aberto') LIKE '%AGENDADO%'
    AND pg_temp.def('idx_ag_em_aberto') LIKE '%CONFIRMADO%'
    AND pg_temp.def('idx_ag_em_aberto') NOT LIKE '%CANCELADO%');
SELECT pg_temp.confere('item_agendamento.id_agendamento é coberto pelo UNIQUE (id_agendamento, id_servico)',
    pg_temp.def('item_agendamento_id_agendamento_id_servico_key')
        = 'item_agendamento USING btree (id_agendamento, id_servico)');
SELECT pg_temp.confere('idx_item_agendamento (redundante) não existe mais',
    to_regclass('idx_item_agendamento') IS NULL);
SELECT pg_temp.confere('idx_item_servico = item_agendamento (id_servico)',
    pg_temp.def('idx_item_servico') = 'item_agendamento USING btree (id_servico)');
SELECT pg_temp.confere('idx_ps_servico = profissional_servico (id_servico)',
    pg_temp.def('idx_ps_servico') = 'profissional_servico USING btree (id_servico)');
SELECT pg_temp.confere('idx_com_competencia = comissao (competencia, paga)',
    pg_temp.def('idx_com_competencia') = 'comissao USING btree (competencia, paga)');
SELECT pg_temp.confere('uq_cliente_email = cliente (lower(email)) e é UNIQUE',
    pg_temp.def('uq_cliente_email') = 'cliente USING btree (lower((email)::text))'
    AND (SELECT indisunique FROM pg_index WHERE indexrelid = 'uq_cliente_email'::regclass));
SELECT pg_temp.confere('nenhum índice inválido (CREATE INDEX que falhou no meio)',
    NOT EXISTS (SELECT 1 FROM pg_index WHERE NOT indisvalid));


-- 2. Uso: cada índice atende à consulta para a qual foi criado
SELECT pg_temp.usa_indice('agenda de um profissional no período usa idx_ag_prof_inicio',
    'idx_ag_prof_inicio',
    $$SELECT * FROM agendamento WHERE id_profissional = 1
      AND inicio >= '2026-11-17' AND inicio < '2026-11-18' ORDER BY inicio$$);
SELECT pg_temp.usa_indice('agenda do salão no período usa idx_ag_inicio',
    'idx_ag_inicio',
    $$SELECT * FROM agendamento WHERE inicio >= '2026-11-17' AND inicio < '2026-11-18' ORDER BY inicio$$);
SELECT pg_temp.usa_indice('histórico do cliente (mais recente primeiro) usa idx_ag_cliente_inicio',
    'idx_ag_cliente_inicio',
    $$SELECT * FROM agendamento WHERE id_cliente = 1 ORDER BY inicio DESC$$);
SELECT pg_temp.usa_indice('próximos atendimentos em aberto usam o índice parcial idx_ag_em_aberto',
    'idx_ag_em_aberto',
    $$SELECT * FROM agendamento WHERE status IN ('AGENDADO', 'CONFIRMADO') AND inicio >= now() ORDER BY inicio$$);
SELECT pg_temp.nao_usa_indice('índice parcial NÃO serve para buscar cancelados',
    'idx_ag_em_aberto',
    $$SELECT * FROM agendamento WHERE status = 'CANCELADO' AND inicio >= now()$$);
SELECT pg_temp.usa_indice('itens de um agendamento usam o índice do UNIQUE (id_agendamento, id_servico)',
    'item_agendamento_id_agendamento_id_servico_key',
    $$SELECT * FROM item_agendamento WHERE id_agendamento = 1$$);
SELECT pg_temp.usa_indice('vendas de um serviço usam idx_item_servico',
    'idx_item_servico',
    $$SELECT * FROM item_agendamento WHERE id_servico = 1$$);
SELECT pg_temp.usa_indice('profissionais que fazem um serviço usam idx_ps_servico',
    'idx_ps_servico',
    $$SELECT * FROM profissional_servico WHERE id_servico = 1$$);
SELECT pg_temp.usa_indice('comissões pendentes do mês usam idx_com_competencia',
    'idx_com_competencia',
    $$SELECT * FROM comissao WHERE competencia = '2026-11-01' AND NOT paga$$);
SELECT pg_temp.usa_indice('busca por e-mail com lower() usa uq_cliente_email',
    'uq_cliente_email',
    $$SELECT * FROM cliente WHERE lower(email) = 'ana.costa@email.com'$$);
SELECT pg_temp.nao_usa_indice('busca por e-mail SEM lower() não usa uq_cliente_email',
    'uq_cliente_email',
    $$SELECT * FROM cliente WHERE email = 'ana.costa@email.com'$$);


-- 3. Comportamento do índice único de e-mail
INSERT INTO cliente (nome, telefone, email) VALUES ('Teste Índice', '00000000091', 'Teste.Indice@Exemplo.com');
SELECT pg_temp.espera_erro('e-mail repetido só mudando maiúsculas é bloqueado',
    $$INSERT INTO cliente (nome, telefone, email) VALUES ('Teste Índice 2', '00000000092', 'teste.indice@exemplo.com')$$);
INSERT INTO cliente (nome, telefone, email) VALUES ('Teste Sem Email 1', '00000000093', NULL),
                                                   ('Teste Sem Email 2', '00000000094', NULL);
SELECT pg_temp.confere('vários clientes sem e-mail (NULL) são permitidos',
    (SELECT count(*) FROM cliente WHERE telefone IN ('00000000093', '00000000094')) = 2);


-- 4. Toda FK tem um índice que começa pela coluna dela (evita Seq Scan
--    em JOINs e no ON DELETE RESTRICT/CASCADE da tabela referenciada)
SELECT pg_temp.confere('toda chave estrangeira tem índice: ' || COALESCE((
        SELECT 'faltando em ' || string_agg(c.conrelid::regclass || '.' || a.attname, ', ')
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f'
          AND c.connamespace = 'public'::regnamespace
          AND NOT EXISTS (SELECT 1 FROM pg_index i
                          WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])
    ), 'ok'),
    NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.contype = 'f'
          AND c.connamespace = 'public'::regnamespace
          AND NOT EXISTS (SELECT 1 FROM pg_index i
                          WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])));


-- Aviso (não falha): índice cujas colunas são o começo de outro índice
-- btree da mesma tabela; o maior já atende às mesmas consultas.
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT a.indexrelid::regclass AS menor, b.indexrelid::regclass AS maior
        FROM pg_index a
        JOIN pg_index b ON b.indrelid = a.indrelid AND b.indexrelid <> a.indexrelid
        JOIN pg_class ca ON ca.oid = a.indexrelid
        JOIN pg_class cb ON cb.oid = b.indexrelid
        WHERE ca.relnamespace = 'public'::regnamespace
          AND ca.relam = cb.relam
          AND a.indpred IS NULL AND b.indpred IS NULL
          AND a.indexprs IS NULL AND b.indexprs IS NULL
          AND NOT a.indisunique
          AND a.indnatts < b.indnatts
          AND (a.indkey::int2[])[0:a.indnatts - 1] = (b.indkey::int2[])[0:a.indnatts - 1]
    LOOP
        RAISE NOTICE 'AVISO: % é redundante (% começa pelas mesmas colunas)', r.menor, r.maior;
    END LOOP;
END $$;

\o
\echo '>>> TODOS OS TESTES DE ÍNDICES PASSARAM <<<'

ROLLBACK;
