-- =====================================================================
-- Regras de negócio que CHECK/FK não conseguem garantir sozinhos
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Agendamento: profissional ativo, dentro do expediente e,
--    se trocar de profissional, ele precisa fazer todos os serviços já lançados.
--    Só valida quando muda horário/profissional, para não travar a
--    conclusão de agendamentos antigos se o expediente mudar depois.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 2) Item: o profissional do agendamento precisa realizar o serviço.
--    Se valor_cobrado vier NULL, usa o preço atual do serviço.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 3) Recalcula agendamento.fim = inicio + soma das durações dos itens.
--    O UPDATE dispara o trg_ag_valida, então expediente e o EXCLUDE
--    anti-conflito continuam sendo checados com o novo fim.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 4) Ao concluir o agendamento, gera a comissão de cada item com o
--    percentual vigente (snapshot em pct_aplicado).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ag_gera_comissao() RETURNS trigger AS $$
BEGIN
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

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ag_gera_comissao
AFTER UPDATE OF status ON agendamento
FOR EACH ROW
WHEN (NEW.status = 'CONCLUIDO' AND OLD.status IS DISTINCT FROM 'CONCLUIDO')
EXECUTE FUNCTION fn_ag_gera_comissao();
