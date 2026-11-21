-- Testes automáticos das regras do banco.
-- Tudo roda dentro de uma transação desfeita no final (ROLLBACK),
-- então nenhum dado de teste fica no banco.
--
-- Rodar manualmente:
--   docker compose exec db psql -f /docker-entrypoint-initdb.d/07_testes.sql
\set ON_ERROR_STOP on
SET client_min_messages = notice;

-- Esconde os resultados dos SELECTs; só aparecem as linhas OK/FALHOU e o \echo final
\o /dev/null

BEGIN;

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

-- Espera que a condição seja verdadeira
CREATE FUNCTION pg_temp.confere(p_nome text, p_cond boolean) RETURNS void AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FALHOU: %', p_nome;
    END IF;
    RAISE NOTICE 'OK: %', p_nome;
END;
$$ LANGUAGE plpgsql;

-- Massa de teste (2026-11-17 é uma terça-feira = dia_semana 2)
INSERT INTO cliente (nome, telefone, email) VALUES ('Teste Ana', '00000000001', 'Teste.Ana@exemplo.com');
INSERT INTO profissional (nome, cpf) VALUES ('Teste Carla', '00000000001');
INSERT INTO profissional (nome, cpf, ativo) VALUES ('Teste Inativo', '00000000002', FALSE);
INSERT INTO servico (nome, preco, duracao_min) VALUES
    ('Teste Corte', 50, 30), ('Teste Escova', 40, 45), ('Teste Unha', 30, 60);

INSERT INTO profissional_servico (id_profissional, id_servico, pct_comissao)
SELECT p.id_profissional, s.id_servico, v.pct
FROM (VALUES ('Teste Corte', 40.0), ('Teste Escova', 30.0)) v(serv, pct)
JOIN servico s ON s.nome = v.serv
JOIN profissional p ON p.cpf = '00000000001';

INSERT INTO horario_trabalho (id_profissional, dia_semana, hora_inicio, hora_fim)
SELECT id_profissional, 2, '09:00', '18:00' FROM profissional WHERE cpf IN ('00000000001', '00000000002');

-- Atalhos para não depender de IDs fixos
CREATE TEMP VIEW t AS SELECT
    (SELECT id_cliente      FROM cliente      WHERE telefone = '00000000001') AS cli,
    (SELECT id_profissional FROM profissional WHERE cpf = '00000000001')      AS prof,
    (SELECT id_profissional FROM profissional WHERE cpf = '00000000002')      AS inativo,
    (SELECT id_servico FROM servico WHERE nome = 'Teste Corte')               AS corte,
    (SELECT id_servico FROM servico WHERE nome = 'Teste Escova')              AS escova,
    (SELECT id_servico FROM servico WHERE nome = 'Teste Unha')                AS unha;

INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, observacao)
SELECT cli, prof, '2026-11-17 10:00', '2026-11-17 10:15', 'teste-1' FROM t;

-- CHECKs do schema
SELECT pg_temp.espera_erro('preço negativo',
    $$INSERT INTO servico (nome, preco, duracao_min) VALUES ('X', -1, 10)$$);
SELECT pg_temp.espera_erro('duração zero',
    $$INSERT INTO servico (nome, preco, duracao_min) VALUES ('X', 10, 0)$$);
SELECT pg_temp.espera_erro('CPF inválido',
    $$INSERT INTO profissional (nome, cpf) VALUES ('X', '123')$$);
SELECT pg_temp.espera_erro('comissão acima de 100%',
    $$UPDATE profissional_servico SET pct_comissao = 150$$);
SELECT pg_temp.espera_erro('dia da semana inválido',
    $$UPDATE horario_trabalho SET dia_semana = 9$$);
SELECT pg_temp.espera_erro('status fora da lista',
    $$UPDATE agendamento SET status = 'cancelado' WHERE observacao = 'teste-1'$$);
SELECT pg_temp.espera_erro('e-mail repetido com outra caixa',
    $$INSERT INTO cliente (nome, telefone, email) VALUES ('X', '00000000002', 'teste.ana@EXEMPLO.com')$$);

-- Expediente e profissional ativo
SELECT pg_temp.espera_erro('agendamento antes do expediente',
    $$INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim)
      SELECT cli, prof, '2026-11-17 08:00', '2026-11-17 09:00' FROM t$$);
SELECT pg_temp.espera_erro('agendamento em dia sem expediente (quarta)',
    $$INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim)
      SELECT cli, prof, '2026-11-18 10:00', '2026-11-18 11:00' FROM t$$);
SELECT pg_temp.espera_erro('agendamento com profissional inativo',
    $$INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim)
      SELECT cli, inativo, '2026-11-17 10:00', '2026-11-17 11:00' FROM t$$);

-- Itens: serviço x profissional, valor padrão e cálculo do fim
INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado)
SELECT a.id_agendamento, t.corte, NULL FROM agendamento a, t WHERE a.observacao = 'teste-1';
INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado)
SELECT a.id_agendamento, t.escova, 35 FROM agendamento a, t WHERE a.observacao = 'teste-1';

SELECT pg_temp.espera_erro('serviço que o profissional não faz',
    $$INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado)
      SELECT a.id_agendamento, t.unha, 30 FROM agendamento a, t WHERE a.observacao = 'teste-1'$$);

SELECT pg_temp.confere('valor_cobrado NULL usa o preço do serviço',
    (SELECT i.valor_cobrado FROM item_agendamento i JOIN t ON i.id_servico = t.corte) = 50);
SELECT pg_temp.confere('fim recalculado = 10:00 + 30 + 45 min = 11:15',
    (SELECT fim FROM agendamento WHERE observacao = 'teste-1') = '2026-11-17 11:15');

-- Conflito de horário
SELECT pg_temp.espera_erro('agendamento sobreposto',
    $$INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim)
      SELECT cli, prof, '2026-11-17 11:00', '2026-11-17 11:30' FROM t$$);

INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, observacao)
SELECT cli, prof, '2026-11-17 11:15', '2026-11-17 11:45', 'teste-encostado' FROM t;
SELECT pg_temp.confere('agendamento encostado (11:15) é permitido',
    EXISTS (SELECT 1 FROM agendamento WHERE observacao = 'teste-encostado'));

UPDATE agendamento SET status = 'CANCELADO' WHERE observacao = 'teste-encostado';
INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, observacao)
SELECT cli, prof, '2026-11-17 11:15', '2026-11-17 11:45', 'teste-reuso' FROM t;
SELECT pg_temp.confere('horário de agendamento cancelado pode ser reutilizado',
    EXISTS (SELECT 1 FROM agendamento WHERE observacao = 'teste-reuso'));

-- Cancelado não vai direto para CONCLUIDO (horário livre e com item lançado,
-- para que só a regra de status possa bloquear)
INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, observacao)
SELECT cli, prof, '2026-11-17 16:00', '2026-11-17 16:30', 'teste-cancelado' FROM t;
INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado)
SELECT a.id_agendamento, t.corte, NULL FROM agendamento a, t WHERE a.observacao = 'teste-cancelado';
UPDATE agendamento SET status = 'CANCELADO' WHERE observacao = 'teste-cancelado';
SELECT pg_temp.espera_erro('cancelado não pode ser concluído',
    $$UPDATE agendamento SET status = 'CONCLUIDO' WHERE observacao = 'teste-cancelado'$$);
UPDATE agendamento SET status = 'AGENDADO' WHERE observacao = 'teste-cancelado';
UPDATE agendamento SET status = 'CONCLUIDO' WHERE observacao = 'teste-cancelado';
SELECT pg_temp.confere('cancelado reaberto pode ser concluído',
    (SELECT status FROM agendamento WHERE observacao = 'teste-cancelado') = 'CONCLUIDO');

-- Comissão gerada ao concluir
UPDATE agendamento SET status = 'CONCLUIDO' WHERE observacao = 'teste-1';

SELECT pg_temp.confere('2 comissões geradas (uma por item)',
    (SELECT count(*) FROM comissao c
       JOIN item_agendamento i ON i.id_item = c.id_item
       JOIN agendamento a ON a.id_agendamento = i.id_agendamento
      WHERE a.observacao = 'teste-1') = 2);
SELECT pg_temp.confere('valores: 40% de 50 = 20,00 e 30% de 35 = 10,50',
    (SELECT array_agg(c.valor ORDER BY c.valor) FROM comissao c
       JOIN item_agendamento i ON i.id_item = c.id_item
       JOIN agendamento a ON a.id_agendamento = i.id_agendamento
      WHERE a.observacao = 'teste-1') = ARRAY[10.50, 20.00]::numeric[]);
SELECT pg_temp.confere('competência = 2026-11-01',
    (SELECT bool_and(c.competencia = '2026-11-01') FROM comissao c
       JOIN item_agendamento i ON i.id_item = c.id_item
       JOIN agendamento a ON a.id_agendamento = i.id_agendamento
      WHERE a.observacao = 'teste-1'));

-- Comissão: casos de borda
CREATE TEMP VIEW com_t1 AS
SELECT c.* FROM comissao c
JOIN item_agendamento i ON i.id_item = c.id_item
JOIN agendamento a ON a.id_agendamento = i.id_agendamento
WHERE a.observacao = 'teste-1';

SELECT pg_temp.espera_erro('concluído não aceita alterar valor do item',
    $$UPDATE item_agendamento SET valor_cobrado = 99
      WHERE id_agendamento = (SELECT id_agendamento FROM agendamento WHERE observacao = 'teste-1')$$);
SELECT pg_temp.espera_erro('concluído não aceita excluir item',
    $$DELETE FROM item_agendamento
      WHERE id_agendamento = (SELECT id_agendamento FROM agendamento WHERE observacao = 'teste-1')$$);
SELECT pg_temp.espera_erro('agendamento não pode ser criado já CONCLUIDO',
    $$INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, status)
      SELECT cli, prof, '2026-11-17 14:00', '2026-11-17 14:30', 'CONCLUIDO' FROM t$$);
SELECT pg_temp.espera_erro('não conclui agendamento sem serviços',
    $$UPDATE agendamento SET status = 'CONCLUIDO' WHERE observacao = 'teste-reuso'$$);
SELECT pg_temp.espera_erro('concluído não troca de horário',
    $$UPDATE agendamento SET inicio = '2026-11-17 15:00', fim = '2026-11-17 16:15'
      WHERE observacao = 'teste-1'$$);
SELECT pg_temp.espera_erro('concluído não troca de profissional',
    $$UPDATE agendamento SET id_profissional = (SELECT inativo FROM t)
      WHERE observacao = 'teste-1'$$);
UPDATE agendamento SET observacao = 'teste-1' WHERE observacao = 'teste-1';
SELECT pg_temp.confere('concluído ainda aceita alterar outros campos', TRUE);

-- Reabrir apaga as comissões não pagas
UPDATE agendamento SET status = 'CONFIRMADO' WHERE observacao = 'teste-1';
SELECT pg_temp.confere('reabrir apaga as comissões não pagas',
    (SELECT count(*) FROM com_t1) = 0);

-- Corrigir o valor e concluir de novo gera a comissão com o valor novo
UPDATE item_agendamento SET valor_cobrado = 45
WHERE id_agendamento = (SELECT id_agendamento FROM agendamento WHERE observacao = 'teste-1')
  AND id_servico = (SELECT escova FROM t);
UPDATE agendamento SET status = 'CONCLUIDO' WHERE observacao = 'teste-1';
SELECT pg_temp.confere('reconcluir gera comissão nova: 30% de 45 = 13,50',
    (SELECT array_agg(valor ORDER BY valor) FROM com_t1) = ARRAY[13.50, 20.00]::numeric[]);

-- Comissão paga trava a reabertura
UPDATE comissao SET paga = TRUE WHERE id_comissao IN (SELECT id_comissao FROM com_t1);
SELECT pg_temp.espera_erro('não reabre agendamento com comissão paga',
    $$UPDATE agendamento SET status = 'CANCELADO' WHERE observacao = 'teste-1'$$);

-- Serviço sem percentual cadastrado bloqueia a conclusão
INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, observacao)
SELECT cli, prof, '2026-11-17 13:00', '2026-11-17 13:30', 'teste-sem-pct' FROM t;
INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado)
SELECT a.id_agendamento, t.corte, NULL FROM agendamento a, t WHERE a.observacao = 'teste-sem-pct';
DELETE FROM profissional_servico WHERE id_servico = (SELECT corte FROM t);
SELECT pg_temp.espera_erro('não conclui serviço sem percentual de comissão',
    $$UPDATE agendamento SET status = 'CONCLUIDO' WHERE observacao = 'teste-sem-pct'$$);

\echo '>>> TODOS OS TESTES PASSARAM <<<'

ROLLBACK;
