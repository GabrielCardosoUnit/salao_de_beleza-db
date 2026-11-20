-- Dados de exemplo do salão.
\set ON_ERROR_STOP on

BEGIN;

-- Clientes (a Larissa não tem agendamentos, útil para testar LEFT JOIN)
INSERT INTO cliente (nome, telefone, email, data_cadastro) VALUES
    ('Ana Beatriz Costa',  '11987650001', 'ana.costa@email.com',     '2026-09-02'),
    ('Bruno Henrique Silva','11987650002', 'bruno.silva@email.com',  '2026-09-05'),
    ('Camila Ferreira',    '11987650003', 'camila.ferreira@email.com','2026-09-10'),
    ('Daniela Martins',    '11987650004', NULL,                      '2026-09-15'),
    ('Eduardo Gomes',      '11987650005', 'eduardo.gomes@email.com', '2026-09-20'),
    ('Fabiana Ribeiro',    '11987650006', 'fabiana.r@email.com',     '2026-10-01'),
    ('Gabriela Nunes',     '11987650007', NULL,                      '2026-10-03'),
    ('Helena Carvalho',    '11987650008', 'helena.carvalho@email.com','2026-10-20'),
    ('Igor Almeida',       '11987650009', 'igor.almeida@email.com',  '2026-10-28'),
    ('Jéssica Moura',      '11987650010', 'jessica.moura@email.com', '2026-11-02'),
    ('Larissa Pinto',      '11987650011', 'larissa.pinto@email.com', '2026-11-15');

-- Profissionais (o Marcos é desativado no final, depois de ter histórico)
INSERT INTO profissional (nome, cpf, telefone) VALUES
    ('Juliana Souza',  '12345678901', '11912340001'),
    ('Ricardo Lima',   '23456789012', '11912340002'),
    ('Patrícia Alves', '34567890123', '11912340003'),
    ('Fernanda Rocha', '45678901234', '11912340004'),
    ('Marcos Dias',    '56789012345', '11912340005');

INSERT INTO servico (nome, preco, duracao_min) VALUES
    ('Corte feminino',        80.00,  60),
    ('Corte masculino',       45.00,  30),
    ('Escova',                50.00,  45),
    ('Coloração',            180.00, 120),
    ('Hidratação',            70.00,  45),
    ('Manicure',              35.00,  45),
    ('Pedicure',              40.00,  50),
    ('Design de sobrancelha', 30.00,  30);

-- Quem faz o quê e com qual percentual de comissão
INSERT INTO profissional_servico (id_profissional, id_servico, pct_comissao)
SELECT p.id_profissional, s.id_servico, v.pct
FROM (VALUES
    ('12345678901', 'Corte feminino',        40.0),
    ('12345678901', 'Escova',                35.0),
    ('12345678901', 'Coloração',             30.0),
    ('12345678901', 'Hidratação',            35.0),
    ('23456789012', 'Corte masculino',       45.0),
    ('23456789012', 'Corte feminino',        40.0),
    ('23456789012', 'Escova',                35.0),
    ('34567890123', 'Manicure',              50.0),
    ('34567890123', 'Pedicure',              50.0),
    ('34567890123', 'Design de sobrancelha', 45.0),
    ('45678901234', 'Escova',                35.0),
    ('45678901234', 'Hidratação',            35.0),
    ('45678901234', 'Design de sobrancelha', 40.0),
    ('56789012345', 'Corte masculino',       40.0)
) v(cpf, servico, pct)
JOIN profissional p ON p.cpf  = v.cpf
JOIN servico      s ON s.nome = v.servico;

-- Expediente (0 = domingo ... 6 = sábado)
INSERT INTO horario_trabalho (id_profissional, dia_semana, hora_inicio, hora_fim)
SELECT p.id_profissional, d.dia, v.ini::time, v.fim::time
FROM (VALUES
    -- Juliana: terça a sábado, 9h-18h
    ('12345678901', 2, 6, '09:00', '18:00'),
    -- Ricardo: terça a sexta 10h-19h, sábado 8h-14h
    ('23456789012', 2, 5, '10:00', '19:00'),
    ('23456789012', 6, 6, '08:00', '14:00'),
    -- Patrícia: segunda a sexta 9h-17h, sábado 9h-13h
    ('34567890123', 1, 5, '09:00', '17:00'),
    ('34567890123', 6, 6, '09:00', '13:00'),
    -- Fernanda: quarta a sábado, 12h-20h
    ('45678901234', 3, 6, '12:00', '20:00'),
    -- Marcos: terça a sábado, 9h-18h
    ('56789012345', 2, 6, '09:00', '18:00')
) v(cpf, dia_de, dia_ate, ini, fim)
CROSS JOIN LATERAL generate_series(v.dia_de, v.dia_ate) d(dia)
JOIN profissional p ON p.cpf = v.cpf;

-- Agendamentos
-- valores: preço cobrado de cada serviço, na mesma ordem; NULL = preço atual
CREATE TEMP TABLE carga_agendamento (
    telefone     VARCHAR(15),
    cpf          CHAR(11),
    inicio       TIMESTAMP,
    servicos     TEXT[],
    valores      NUMERIC[],
    status_final VARCHAR(10),
    observacao   VARCHAR(255)
) ON COMMIT DROP;

INSERT INTO carga_agendamento VALUES
    -- Outubro (concluídos, comissão paga)
    ('11987650001', '12345678901', '2026-10-06 09:00', '{Corte feminino,Escova}',      NULL, 'CONCLUIDO', NULL),
    ('11987650002', '23456789012', '2026-10-06 10:00', '{Corte masculino}',            NULL, 'CONCLUIDO', NULL),
    ('11987650003', '34567890123', '2026-10-07 14:00', '{Manicure,Pedicure}',          NULL, 'CONCLUIDO', NULL),
    ('11987650004', '12345678901', '2026-10-09 13:00', '{Coloração,Hidratação}',       NULL, 'CONCLUIDO', 'Cliente com alergia a amônia'),
    ('11987650005', '56789012345', '2026-10-10 09:00', '{Corte masculino}',            NULL, 'CONCLUIDO', NULL),
    ('11987650006', '45678901234', '2026-10-14 15:00', '{Escova,Design de sobrancelha}',NULL, 'CONCLUIDO', NULL),
    ('11987650007', '34567890123', '2026-10-16 10:00', '{Manicure}',                   NULL, 'CANCELADO', 'Cliente desmarcou por telefone'),
    ('11987650002', '56789012345', '2026-10-24 11:00', '{Corte masculino}',            NULL, 'CONCLUIDO', NULL),
    -- Novembro até ontem (concluídos, comissão pendente)
    ('11987650001', '34567890123', '2026-11-04 09:00', '{Manicure,Design de sobrancelha}', NULL, 'CONCLUIDO', NULL),
    ('11987650008', '12345678901', '2026-11-05 10:00', '{Corte feminino,Hidratação}',  '{NULL,60.00}', 'CONCLUIDO', 'Desconto de R$ 10 na hidratação'),
    ('11987650009', '23456789012', '2026-11-07 08:00', '{Corte masculino}',            NULL, 'CONCLUIDO', NULL),
    ('11987650003', '45678901234', '2026-11-11 12:00', '{Hidratação,Escova}',          NULL, 'CONCLUIDO', NULL),
    ('11987650004', '23456789012', '2026-11-12 16:00', '{Corte feminino}',             NULL, 'CANCELADO', 'Não compareceu'),
    ('11987650010', '12345678901', '2026-11-13 09:00', '{Coloração}',                  NULL, 'CONCLUIDO', NULL),
    ('11987650008', '34567890123', '2026-11-14 09:00', '{Pedicure}',                   NULL, 'CONCLUIDO', NULL),
    -- Hoje (2026-11-17)
    ('11987650006', '12345678901', '2026-11-17 09:00', '{Escova}',                     NULL, 'CONFIRMADO', NULL),
    ('11987650005', '23456789012', '2026-11-17 10:00', '{Corte masculino}',            NULL, 'CONFIRMADO', NULL),
    ('11987650007', '34567890123', '2026-11-17 14:00', '{Manicure,Pedicure}',          NULL, 'AGENDADO',   NULL),
    -- Próximos dias
    ('11987650001', '12345678901', '2026-11-20 10:00', '{Corte feminino}',             NULL, 'AGENDADO',   NULL),
    ('11987650009', '23456789012', '2026-11-21 09:00', '{Corte masculino}',            NULL, 'AGENDADO',   NULL),
    ('11987650010', '45678901234', '2026-11-25 18:00', '{Design de sobrancelha}',      NULL, 'AGENDADO',   NULL),
    ('11987650003', '12345678901', '2026-12-01 14:00', '{Coloração,Escova}',           NULL, 'AGENDADO',   'Retoque da raiz');

DO $$
DECLARE
    r    carga_agendamento%ROWTYPE;
    v_id INT;
BEGIN
    FOR r IN SELECT * FROM carga_agendamento ORDER BY inicio LOOP
        -- fim provisório: o trigger recalcula ao lançar os serviços
        INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim, observacao)
        SELECT c.id_cliente, p.id_profissional, r.inicio, r.inicio + INTERVAL '1 minute', r.observacao
        FROM cliente c, profissional p
        WHERE c.telefone = r.telefone AND p.cpf = r.cpf
        RETURNING id_agendamento INTO v_id;

        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Cliente % ou profissional % não encontrado', r.telefone, r.cpf;
        END IF;

        INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado)
        SELECT v_id, s.id_servico, x.valor
        FROM unnest(r.servicos, COALESCE(r.valores, '{}')) x(servico, valor)
        JOIN servico s ON s.nome = x.servico;

        IF r.status_final <> 'AGENDADO' THEN
            UPDATE agendamento SET status = r.status_final WHERE id_agendamento = v_id;
        END IF;
    END LOOP;
END;
$$;

-- Comissões de outubro já foram pagas
UPDATE comissao SET paga = TRUE WHERE competencia = '2026-10-01';

-- Marcos saiu do salão: fica o histórico, mas não aceita novos agendamentos
UPDATE profissional SET ativo = FALSE WHERE cpf = '56789012345';

COMMIT;
