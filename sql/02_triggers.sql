-- Regras de negócio que CHECK/FK não conseguem garantir sozinhos

-- Agendamento: profissional ativo, dentro do expediente e,
--    se trocar de profissional, ele precisa fazer todos os serviços já lançados.
--    Só valida quando muda horário/profissional, para não travar a
--    conclusão de agendamentos antigos se o expediente mudar depois.
CREATE OR REPLACE FUNCTION fn_ag_valida() RETURNS trigger AS $$
BEGIN
    IF NEW.status = 'CANCELADO' THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM profissional
                   WHERE id_profissional = NEW.id_profissional AND ativo) THEN
        RAISE EXCEPTION 'Profissional % está inativo ou não existe', NEW.id_profissional;
    END IF;

    IF NEW.inicio::date <> NEW.fim::date THEN
        RAISE EXCEPTION 'O agendamento deve começar e terminar no mesmo dia';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM horario_trabalho h
        WHERE h.id_profissional = NEW.id_profissional
          AND h.dia_semana      = EXTRACT(DOW FROM NEW.inicio)
          AND NEW.inicio::time >= h.hora_inicio
          AND NEW.fim::time    <= h.hora_fim
    ) THEN
        RAISE EXCEPTION 'Horário % - % fora do expediente do profissional %',
            NEW.inicio, NEW.fim, NEW.id_profissional;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.id_profissional <> OLD.id_profissional AND EXISTS (
        SELECT 1 FROM item_agendamento i
        WHERE i.id_agendamento = NEW.id_agendamento
          AND NOT EXISTS (SELECT 1 FROM profissional_servico ps
                          WHERE ps.id_profissional = NEW.id_profissional
                            AND ps.id_servico      = i.id_servico)
    ) THEN
        RAISE EXCEPTION 'O novo profissional não realiza todos os serviços deste agendamento';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ag_valida
BEFORE INSERT OR UPDATE OF inicio, fim, id_profissional ON agendamento
FOR EACH ROW EXECUTE FUNCTION fn_ag_valida();


-- Item: o profissional do agendamento precisa realizar o serviço.
--    Se valor_cobrado vier NULL, usa o preço atual do serviço.
CREATE OR REPLACE FUNCTION fn_item_valida() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM agendamento a
        JOIN profissional_servico ps ON ps.id_profissional = a.id_profissional
        WHERE a.id_agendamento = NEW.id_agendamento
          AND ps.id_servico    = NEW.id_servico
    ) THEN
        RAISE EXCEPTION 'O profissional do agendamento % não realiza o serviço %',
            NEW.id_agendamento, NEW.id_servico;
    END IF;

    IF NEW.valor_cobrado IS NULL THEN
        SELECT preco INTO NEW.valor_cobrado FROM servico WHERE id_servico = NEW.id_servico;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_item_valida
BEFORE INSERT OR UPDATE OF id_servico, id_agendamento ON item_agendamento
FOR EACH ROW EXECUTE FUNCTION fn_item_valida();


-- Recalcula agendamento.fim = inicio + soma das durações dos itens.
--    O UPDATE dispara o trg_ag_valida, então expediente e o EXCLUDE
--    anti-conflito continuam sendo checados com o novo fim.
CREATE OR REPLACE FUNCTION fn_item_recalcula_fim() RETURNS trigger AS $$
DECLARE
    v_ag    INT;
    v_total INT;
BEGIN
    v_ag := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_agendamento ELSE NEW.id_agendamento END;

    SELECT COALESCE(SUM(s.duracao_min), 0) INTO v_total
    FROM item_agendamento i
    JOIN servico s ON s.id_servico = i.id_servico
    WHERE i.id_agendamento = v_ag;

    -- Sem itens, mantém o fim informado manualmente
    IF v_total > 0 THEN
        UPDATE agendamento
           SET fim = inicio + make_interval(mins => v_total)
         WHERE id_agendamento = v_ag
           AND fim IS DISTINCT FROM inicio + make_interval(mins => v_total);
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_item_recalcula_fim
AFTER INSERT OR DELETE OR UPDATE OF id_servico ON item_agendamento
FOR EACH ROW EXECUTE FUNCTION fn_item_recalcula_fim();


-- Comissão
--
--    Fluxo: AGENDADO/CONFIRMADO -> CONCLUIDO gera uma comissão por item,
--    com o percentual vigente em profissional_servico (snapshot em
--    pct_aplicado) e competência = mês do atendimento.
--
--    Reabrir (CONCLUIDO -> outro status) apaga as comissões ainda não
--    pagas; se alguma já foi paga, a reabertura é bloqueada.
--
--    Para corrigir um atendimento concluído: reabrir, ajustar os itens e
--    concluir de novo (a comissão é gerada outra vez com os valores novos).
CREATE OR REPLACE FUNCTION fn_ag_comissao() RETURNS trigger AS $$
BEGIN
    -- Concluiu: gera as comissões
    IF NEW.status = 'CONCLUIDO' AND OLD.status <> 'CONCLUIDO' THEN

        IF NOT EXISTS (SELECT 1 FROM item_agendamento
                       WHERE id_agendamento = NEW.id_agendamento) THEN
            RAISE EXCEPTION 'Agendamento % não tem serviços lançados; não é possível concluir',
                NEW.id_agendamento;
        END IF;

        -- Todo item precisa ter percentual cadastrado (senão a comissão sairia incompleta)
        IF EXISTS (
            SELECT 1 FROM item_agendamento i
            WHERE i.id_agendamento = NEW.id_agendamento
              AND NOT EXISTS (SELECT 1 FROM profissional_servico ps
                              WHERE ps.id_profissional = NEW.id_profissional
                                AND ps.id_servico      = i.id_servico)
        ) THEN
            RAISE EXCEPTION 'Há serviço no agendamento % sem percentual de comissão para o profissional %',
                NEW.id_agendamento, NEW.id_profissional;
        END IF;

        INSERT INTO comissao (id_item, pct_aplicado, valor, competencia)
        SELECT i.id_item,
               ps.pct_comissao,
               ROUND(i.valor_cobrado * ps.pct_comissao / 100, 2),
               date_trunc('month', NEW.inicio)::date
        FROM item_agendamento i
        JOIN profissional_servico ps
          ON ps.id_profissional = NEW.id_profissional
         AND ps.id_servico      = i.id_servico
        WHERE i.id_agendamento = NEW.id_agendamento
        ON CONFLICT (id_item) DO NOTHING;

    -- Reabriu/cancelou um concluído: desfaz as comissões não pagas
    ELSIF OLD.status = 'CONCLUIDO' AND NEW.status <> 'CONCLUIDO' THEN

        IF EXISTS (
            SELECT 1 FROM comissao c
            JOIN item_agendamento i ON i.id_item = c.id_item
            WHERE i.id_agendamento = NEW.id_agendamento AND c.paga
        ) THEN
            RAISE EXCEPTION 'Agendamento % tem comissão já paga; não pode sair de CONCLUIDO',
                NEW.id_agendamento;
        END IF;

        DELETE FROM comissao c
        USING item_agendamento i
        WHERE i.id_item = c.id_item
          AND i.id_agendamento = NEW.id_agendamento;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ag_comissao
AFTER UPDATE OF status ON agendamento
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION fn_ag_comissao();


-- Agendamento concluído fica "fechado": não aceita inclusão,
--    alteração ou exclusão de itens (a comissão ficaria desatualizada).
--    Também não é permitido criar um agendamento já CONCLUIDO, porque
--    ele ainda não teria itens e nunca geraria comissão.
CREATE OR REPLACE FUNCTION fn_item_bloqueia_concluido() RETURNS trigger AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') AND EXISTS (
        SELECT 1 FROM agendamento
        WHERE id_agendamento = OLD.id_agendamento AND status = 'CONCLUIDO'
    ) THEN
        RAISE EXCEPTION 'Agendamento % está CONCLUIDO; reabra-o para alterar os serviços',
            OLD.id_agendamento;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') AND EXISTS (
        SELECT 1 FROM agendamento
        WHERE id_agendamento = NEW.id_agendamento AND status = 'CONCLUIDO'
    ) THEN
        RAISE EXCEPTION 'Agendamento % está CONCLUIDO; reabra-o para alterar os serviços',
            NEW.id_agendamento;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_item_bloqueia_concluido
BEFORE INSERT OR UPDATE OR DELETE ON item_agendamento
FOR EACH ROW EXECUTE FUNCTION fn_item_bloqueia_concluido();


CREATE OR REPLACE FUNCTION fn_ag_nao_nasce_concluido() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Crie o agendamento como AGENDADO, lance os serviços e depois mude para CONCLUIDO';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ag_nao_nasce_concluido
BEFORE INSERT ON agendamento
FOR EACH ROW
WHEN (NEW.status = 'CONCLUIDO')
EXECUTE FUNCTION fn_ag_nao_nasce_concluido();


-- Agendamento concluído também não pode trocar de profissional nem de
--    horário: a comissão já gerada ficaria com o profissional ou a
--    competência errados. Reabrir no mesmo UPDATE é permitido, porque
--    aí as comissões são apagadas e geradas de novo ao concluir.
--    (O nome "trg_ag_bloqueia..." faz este trigger rodar antes do
--    trg_ag_valida, já que o PostgreSQL dispara em ordem alfabética.)
CREATE OR REPLACE FUNCTION fn_ag_bloqueia_concluido() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Agendamento % está CONCLUIDO; reabra-o para mudar profissional ou horário',
        OLD.id_agendamento;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ag_bloqueia_concluido
BEFORE UPDATE OF inicio, fim, id_profissional ON agendamento
FOR EACH ROW
WHEN (OLD.status = 'CONCLUIDO' AND NEW.status = 'CONCLUIDO'
      AND (NEW.id_profissional IS DISTINCT FROM OLD.id_profissional
           OR NEW.inicio IS DISTINCT FROM OLD.inicio
           OR NEW.fim    IS DISTINCT FROM OLD.fim))
EXECUTE FUNCTION fn_ag_bloqueia_concluido();


-- Agendamento cancelado não pode ir direto para CONCLUIDO: geraria
--    comissão de um atendimento que não aconteceu. Se o cliente veio
--    mesmo assim, reabra (AGENDADO/CONFIRMADO) e depois conclua; a
--    reabertura passa de novo pela checagem de expediente e conflito.
CREATE OR REPLACE FUNCTION fn_ag_cancelado_nao_conclui() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Agendamento % está CANCELADO; reabra-o antes de concluir',
        OLD.id_agendamento;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ag_cancelado_nao_conclui
BEFORE UPDATE OF status ON agendamento
FOR EACH ROW
WHEN (OLD.status = 'CANCELADO' AND NEW.status = 'CONCLUIDO')
EXECUTE FUNCTION fn_ag_cancelado_nao_conclui();
