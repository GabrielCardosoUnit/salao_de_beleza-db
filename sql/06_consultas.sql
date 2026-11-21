-- Consultas do salão.
-- As datas são fixas para bater com os dados de exemplo (o "hoje" dos dados é 2026-11-17).

-- Em uso real, troque as datas por CURRENT_DATE / date_trunc('month', CURRENT_DATE).

-- C1. Agenda do dia: atendimentos não cancelados, em ordem de horário.
SELECT inicio::time AS hora,
       fim::time    AS termino,
       profissional,
       cliente,
       telefone_cliente,
       servicos,
       valor_total,
       status
FROM vw_agenda
WHERE inicio::date = DATE '2026-11-17'
  AND status <> 'CANCELADO'
ORDER BY inicio, profissional;

-- C2. Histórico de atendimentos de um cliente (busca pelo telefone).
SELECT a.inicio::date AS data,
       p.nome         AS profissional,
       s.nome         AS servico,
       i.valor_cobrado,
       a.status
FROM cliente c
JOIN agendamento      a ON a.id_cliente      = c.id_cliente
JOIN profissional     p ON p.id_profissional = a.id_profissional
JOIN item_agendamento i ON i.id_agendamento  = a.id_agendamento
JOIN servico          s ON s.id_servico      = i.id_servico
WHERE c.telefone = '11987650001'
ORDER BY a.inicio DESC, s.nome;

-- C3. Faturamento total por mês (só concluídos).
SELECT
    mes,
    SUM(qtd_atendimentos) AS qtd_servicos,
    SUM(faturamento) AS faturamento
FROM vw_faturamento_mensal
GROUP BY
    mes
ORDER BY mes;

-- C4. Ranking de serviços mais vendidos (concluídos), com participação no faturamento.
SELECT
    s.nome AS servico,
    COUNT(*) AS qtd,
    SUM(i.valor_cobrado) AS faturamento,
    ROUND(
        100 * SUM(i.valor_cobrado) / SUM(SUM(i.valor_cobrado)) OVER (),
        1
    ) AS pct_faturamento,
    RANK() OVER (
        ORDER BY SUM(i.valor_cobrado) DESC
    ) AS posicao
FROM
    item_agendamento i
    JOIN agendamento a ON a.id_agendamento = i.id_agendamento
    JOIN servico s ON s.id_servico = i.id_servico
WHERE
    a.status = 'CONCLUIDO'
GROUP BY
    s.id_servico
ORDER BY posicao, servico;

-- C5. Comissões pendentes de pagamento por profissional.
SELECT
    profissional,
    competencia,
    qtd_servicos,
    total_comissao,
    total_pendente
FROM vw_comissao_profissional
WHERE
    total_pendente > 0
ORDER BY competencia, total_pendente DESC;

-- C6. Desempenho de cada profissional no mês (todos aparecem, mesmo sem atendimento).
SELECT
    p.nome AS profissional,
    COUNT(DISTINCT a.id_agendamento) AS atendimentos,
    COALESCE(SUM(i.valor_cobrado), 0) AS faturamento,
    COALESCE(SUM(cm.valor), 0) AS comissao
FROM
    profissional p
    LEFT JOIN agendamento a ON a.id_profissional = p.id_profissional
    AND a.status = 'CONCLUIDO'
    AND a.inicio >= DATE '2026-11-01'
    AND a.inicio < DATE '2026-12-01'
    LEFT JOIN item_agendamento i ON i.id_agendamento = a.id_agendamento
    LEFT JOIN comissao cm ON cm.id_item = i.id_item
GROUP BY
    p.id_profissional
ORDER BY faturamento DESC, profissional;

-- C7. Clientes que mais gastaram (top 5), com ticket médio por visita.
SELECT
    c.nome AS cliente,
    COUNT(DISTINCT a.id_agendamento) AS visitas,
    SUM(i.valor_cobrado) AS total_gasto,
    ROUND(
        SUM(i.valor_cobrado) / COUNT(DISTINCT a.id_agendamento),
        2
    ) AS ticket_medio
FROM
    cliente c
    JOIN agendamento a ON a.id_cliente = c.id_cliente
    JOIN item_agendamento i ON i.id_agendamento = a.id_agendamento
WHERE
    a.status = 'CONCLUIDO'
GROUP BY
    c.id_cliente
ORDER BY total_gasto DESC
LIMIT 5;

-- C8. Clientes que nunca foram atendidos (sem nenhum agendamento concluído).
SELECT c.nome, c.telefone, c.data_cadastro
FROM cliente c
WHERE
    NOT EXISTS (
        SELECT 1
        FROM agendamento a
        WHERE
            a.id_cliente = c.id_cliente
            AND a.status = 'CONCLUIDO'
    )
ORDER BY c.data_cadastro;

-- C9. Clientes sumidos: última visita concluída há mais de 30 dias e nada marcado depois.
SELECT c.nome,
       c.telefone,
       MAX(a.inicio)::date                        AS ultima_visita,
       DATE '2026-11-17' - MAX(a.inicio)::date    AS dias_sem_vir
FROM cliente c
JOIN agendamento a ON a.id_cliente = c.id_cliente AND a.status = 'CONCLUIDO'
WHERE NOT EXISTS (
    SELECT 1
    FROM agendamento f
    WHERE f.id_cliente = c.id_cliente
      AND f.status IN ('AGENDADO', 'CONFIRMADO')
      AND f.inicio >= DATE '2026-11-17'
)
GROUP BY c.id_cliente
HAVING MAX(a.inicio) < DATE '2026-11-17' - INTERVAL '30 days'
ORDER BY ultima_visita;

-- C10. Taxa de cancelamento por profissional.
SELECT
    p.nome AS profissional,
    COUNT(*) AS agendamentos,
    COUNT(*) FILTER (
        WHERE
            a.status = 'CANCELADO'
    ) AS cancelados,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE
                a.status = 'CANCELADO'
        ) / COUNT(*),
        1
    ) AS pct_cancelado
FROM agendamento a
    JOIN profissional p ON p.id_profissional = a.id_profissional
GROUP BY
    p.id_profissional
ORDER BY pct_cancelado DESC, profissional;

-- C11. Horários livres de um profissional num dia (lacunas entre os agendamentos dentro do expediente).
WITH params AS (
    SELECT p.id_profissional, DATE '2026-11-17' AS dia
    FROM profissional p
    WHERE p.cpf = '12345678901'  -- Juliana Souza
),
expediente AS (
    SELECT pr.id_profissional,
           pr.dia + h.hora_inicio AS abre,
           pr.dia + h.hora_fim    AS fecha
    FROM params pr
    JOIN horario_trabalho h
      ON h.id_profissional = pr.id_profissional
     AND h.dia_semana      = EXTRACT(DOW FROM pr.dia)
),
ocupado AS (
    SELECT a.inicio, a.fim
    FROM agendamento a
    JOIN expediente e ON e.id_profissional = a.id_profissional
    WHERE a.status <> 'CANCELADO'
      AND a.inicio < e.fecha
      AND a.fim    > e.abre
),
marcos AS (
    -- cada lacuna começa no fim de um bloco ocupado (ou na abertura) e vai até o próximo início
    SELECT e.abre AS livre_de,
           COALESCE((SELECT MIN(o.inicio) FROM ocupado o WHERE o.inicio >= e.abre), e.fecha) AS livre_ate
    FROM expediente e
    UNION ALL
    SELECT o.fim,
           COALESCE((SELECT MIN(o2.inicio) FROM ocupado o2 WHERE o2.inicio >= o.fim), e.fecha)
    FROM ocupado o
    CROSS JOIN expediente e
)
SELECT livre_de::time  AS livre_de,
       livre_ate::time AS livre_ate,
       (EXTRACT(EPOCH FROM livre_ate - livre_de) / 60)::int AS minutos
FROM marcos
WHERE livre_ate > livre_de
ORDER BY livre_de;

-- C12. Quem pode atender um serviço num dia da semana (realiza o serviço e trabalha nesse dia).
SELECT h.profissional, h.dia, h.hora_inicio, h.hora_fim, ps.pct_comissao
FROM
    vw_horarios_profissional h
    JOIN profissional_servico ps ON ps.id_profissional = h.id_profissional
    JOIN servico s ON s.id_servico = ps.id_servico
WHERE
    s.nome = 'Escova'
    AND h.dia_semana = 6 -- sábado
ORDER BY h.hora_inicio, h.profissional;

-- C13. Serviços com preço cobrado diferente da tabela atual (descontos/reajustes).
SELECT a.inicio::date            AS data,
       c.nome                    AS cliente,
       s.nome                    AS servico,
       s.preco                   AS preco_tabela,
       i.valor_cobrado,
       i.valor_cobrado - s.preco AS diferenca,
       a.observacao
FROM item_agendamento i
JOIN servico     s ON s.id_servico     = i.id_servico
JOIN agendamento a ON a.id_agendamento = i.id_agendamento
JOIN cliente     c ON c.id_cliente     = a.id_cliente
WHERE i.valor_cobrado <> s.preco
ORDER BY a.inicio;