-- Views para as consultas do dia a dia (agenda, comissões, faturamento)

-- Apaga e recria (permite rodar o arquivo de novo após mudanças)
DROP VIEW IF EXISTS vw_agenda,
vw_comissao_profissional,
vw_faturamento_mensal,
vw_horarios_profissional;


-- Agenda: um agendamento por linha, com nomes, serviços e valor total.
--   SELECT * FROM vw_agenda WHERE inicio::date = '2026-11-17' ORDER BY inicio;
--   SELECT * FROM vw_agenda WHERE profissional = 'Juliana Souza' AND status <> 'CANCELADO';
CREATE VIEW vw_agenda AS
SELECT a.id_agendamento,
       a.inicio,
       a.fim,
       (EXTRACT(EPOCH FROM a.fim - a.inicio) / 60)::int AS duracao_min,
       a.status,
       c.id_cliente,
       c.nome                                            AS cliente,
       c.telefone                                        AS telefone_cliente,
       p.id_profissional,
       p.nome                                            AS profissional,
       string_agg(s.nome, ', ' ORDER BY i.id_item)       AS servicos,
       COALESCE(SUM(i.valor_cobrado), 0)                 AS valor_total,
       a.observacao
FROM agendamento a
JOIN cliente      c ON c.id_cliente      = a.id_cliente
JOIN profissional p ON p.id_profissional = a.id_profissional
LEFT JOIN item_agendamento i ON i.id_agendamento = a.id_agendamento
LEFT JOIN servico          s ON s.id_servico     = i.id_servico
GROUP BY a.id_agendamento, c.id_cliente, p.id_profissional;


-- Comissões por profissional e mês, separando pago e pendente.
--   SELECT * FROM vw_comissao_profissional WHERE competencia = '2026-11-01';
--   SELECT * FROM vw_comissao_profissional WHERE total_pendente > 0;
CREATE VIEW vw_comissao_profissional AS
SELECT p.id_profissional,
       p.nome                                                AS profissional,
       c.competencia,
       COUNT(*)                                              AS qtd_servicos,
       SUM(i.valor_cobrado)                                  AS valor_atendido,
       SUM(c.valor)                                          AS total_comissao,
       COALESCE(SUM(c.valor) FILTER (WHERE c.paga), 0)       AS total_pago,
       COALESCE(SUM(c.valor) FILTER (WHERE NOT c.paga), 0)   AS total_pendente
FROM comissao c
JOIN item_agendamento i ON i.id_item         = c.id_item
JOIN agendamento      a ON a.id_agendamento  = i.id_agendamento
JOIN profissional     p ON p.id_profissional = a.id_profissional
GROUP BY p.id_profissional, c.competencia;


-- Faturamento por mês e serviço (só atendimentos CONCLUIDO).
--   SELECT * FROM vw_faturamento_mensal WHERE mes = '2026-10-01' ORDER BY faturamento DESC;
--   SELECT mes, SUM(faturamento) FROM vw_faturamento_mensal GROUP BY mes ORDER BY mes;
CREATE VIEW vw_faturamento_mensal AS
SELECT date_trunc('month', a.inicio)::date AS mes,
       s.id_servico,
       s.nome                              AS servico,
       COUNT(*)                            AS qtd_atendimentos,
       SUM(i.valor_cobrado)                AS faturamento,
       ROUND(AVG(i.valor_cobrado), 2)      AS ticket_medio
FROM item_agendamento i
JOIN agendamento a ON a.id_agendamento = i.id_agendamento
JOIN servico     s ON s.id_servico     = i.id_servico
WHERE a.status = 'CONCLUIDO'
GROUP BY 1, s.id_servico;


-- Expediente dos profissionais ativos, com o nome do dia da semana.
--   SELECT * FROM vw_horarios_profissional WHERE dia_semana = 6;  -- quem trabalha sábado
CREATE VIEW vw_horarios_profissional AS
SELECT p.id_profissional,
       p.nome AS profissional,
       h.dia_semana,
       (ARRAY['Domingo', 'Segunda', 'Terça', 'Quarta',
              'Quinta', 'Sexta', 'Sábado'])[h.dia_semana + 1] AS dia,
       h.hora_inicio,
       h.hora_fim
FROM horario_trabalho h
JOIN profissional p ON p.id_profissional = h.id_profissional
WHERE p.ativo;
