-- O PostgreSQL não cria índice automático para chave estrangeira.
-- agendamento.id_profissional já é coberto pelo índice gist do EXCLUDE.
CREATE INDEX idx_ag_cliente        ON agendamento (id_cliente);
CREATE INDEX idx_item_agendamento  ON item_agendamento (id_agendamento);
CREATE INDEX idx_item_servico      ON item_agendamento (id_servico);
CREATE INDEX idx_ps_servico        ON profissional_servico (id_servico);

-- Relatórios de comissão por mês / pendentes de pagamento
CREATE INDEX idx_com_competencia   ON comissao (competencia, paga);

-- E-mail único sem diferenciar maiúsculas/minúsculas (NULL continua permitido)
CREATE UNIQUE INDEX uq_cliente_email ON cliente (lower(email));
