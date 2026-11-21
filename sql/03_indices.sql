-- Índices da agenda (tabela agendamento)

-- Agenda de um profissional em um dia/período
--   WHERE id_profissional = 1 AND inicio >= '2026-11-17' AND inicio < '2026-11-18'
--   ORDER BY inicio
CREATE INDEX idx_ag_prof_inicio ON agendamento (id_profissional, inicio);

-- Agenda do salão inteiro em um dia/período
--   WHERE inicio >= '2026-11-17' AND inicio < '2026-11-18' ORDER BY inicio
CREATE INDEX idx_ag_inicio ON agendamento (inicio);

-- Histórico do cliente, do mais recente para o mais antigo
--   WHERE id_cliente = 1 ORDER BY inicio DESC
-- (também serve de índice para a FK id_cliente)
CREATE INDEX idx_ag_cliente_inicio ON agendamento (id_cliente, inicio DESC);

-- Próximos atendimentos ainda em aberto (índice parcial: só guarda
-- AGENDADO/CONFIRMADO, então fica pequeno mesmo com muito histórico)
--   WHERE status IN ('AGENDADO', 'CONFIRMADO') AND inicio >= now()
CREATE INDEX idx_ag_em_aberto ON agendamento (inicio)
WHERE
    status IN ('AGENDADO', 'CONFIRMADO');

-- Chaves estrangeiras
-- (item_agendamento.id_agendamento não precisa de índice próprio: o
--  UNIQUE (id_agendamento, id_servico) do schema já cria um índice que
--  começa por essa coluna e atende às mesmas consultas)
CREATE INDEX idx_item_servico ON item_agendamento (id_servico);

CREATE INDEX idx_ps_servico ON profissional_servico (id_servico);

-- Outros

-- Relatórios de comissão por mês / pendentes de pagamento
CREATE INDEX idx_com_competencia ON comissao (competencia, paga);

-- E-mail único sem diferenciar maiúsculas/minúsculas (NULL continua permitido)
CREATE UNIQUE INDEX uq_cliente_email ON cliente (lower(email));