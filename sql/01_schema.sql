-- Necessária para o EXCLUDE com tsrange
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Apaga e recria (permite rodar o arquivo de novo após mudanças)
DROP TABLE IF EXISTS comissao,
item_agendamento,
agendamento,
horario_trabalho,
profissional_servico,
servico,
profissional,
cliente CASCADE;

CREATE TABLE cliente (
    id_cliente     SERIAL       PRIMARY KEY,
    nome           VARCHAR(100) NOT NULL,
    telefone       VARCHAR(15)  NOT NULL UNIQUE,
    email          VARCHAR(120), -- unicidade sem diferenciar maiúsculas: ver 03_indices.sql
    data_cadastro  DATE         NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE profissional (
    id_profissional SERIAL       PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL,
    cpf             CHAR(11)     NOT NULL UNIQUE,
    telefone        VARCHAR(15),
    ativo           BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT ck_prof_cpf CHECK (cpf ~ '^[0-9]{11}$')
);

CREATE TABLE servico (
    id_servico  SERIAL         PRIMARY KEY,
    nome        VARCHAR(80)    NOT NULL UNIQUE,
    preco       DECIMAL(10, 2) NOT NULL,
    duracao_min INT            NOT NULL,

    CONSTRAINT ck_serv_preco   CHECK (preco >= 0),
    CONSTRAINT ck_serv_duracao CHECK (duracao_min > 0)
);

CREATE TABLE profissional_servico (
    id_profissional INT          NOT NULL REFERENCES profissional (id_profissional) ON DELETE CASCADE,
    id_servico      INT          NOT NULL REFERENCES servico (id_servico)           ON DELETE RESTRICT,
    pct_comissao    DECIMAL(5, 2) NOT NULL,
    PRIMARY KEY (id_profissional, id_servico),

    CONSTRAINT ck_ps_pct CHECK (pct_comissao BETWEEN 0 AND 100)
);

CREATE TABLE horario_trabalho (
    id_profissional INT      NOT NULL REFERENCES profissional (id_profissional) ON DELETE CASCADE,
    dia_semana      SMALLINT NOT NULL, -- 0 = domingo ... 6 = sábado (mesmo padrão do EXTRACT(DOW))
    hora_inicio     TIME     NOT NULL,
    hora_fim        TIME     NOT NULL,
    PRIMARY KEY (id_profissional, dia_semana),

    CONSTRAINT ck_ht_dia     CHECK (dia_semana BETWEEN 0 AND 6),
    CONSTRAINT ck_ht_periodo CHECK (hora_fim > hora_inicio)
);

CREATE TABLE agendamento (
    id_agendamento   SERIAL       PRIMARY KEY,
    id_cliente       INT          NOT NULL REFERENCES cliente(id_cliente)           ON DELETE RESTRICT,
    id_profissional  INT          NOT NULL REFERENCES profissional(id_profissional) ON DELETE RESTRICT,
    inicio           TIMESTAMP    NOT NULL,
    fim              TIMESTAMP    NOT NULL,
    status           VARCHAR(10)  NOT NULL DEFAULT 'AGENDADO',
    observacao       VARCHAR(255),

    CONSTRAINT ck_ag_periodo CHECK (fim > inicio),

    -- O EXCLUDE abaixo depende do valor exato 'CANCELADO', por isso o domínio é fechado
    CONSTRAINT ck_ag_status CHECK (status IN ('AGENDADO', 'CONFIRMADO', 'CONCLUIDO', 'CANCELADO')),

    CONSTRAINT ex_sem_sobreposicao EXCLUDE USING gist (
        id_profissional WITH =,
        tsrange(inicio, fim, '[)') WITH &&
    ) WHERE (status <> 'CANCELADO')
);

CREATE TABLE item_agendamento (
    id_item        SERIAL         PRIMARY KEY,
    id_agendamento INT            NOT NULL REFERENCES agendamento (id_agendamento) ON DELETE CASCADE,
    id_servico     INT            NOT NULL REFERENCES servico (id_servico)         ON DELETE RESTRICT,
    valor_cobrado  DECIMAL(10, 2) NOT NULL, -- se vier NULL, o trigger usa servico.preco
    UNIQUE (id_agendamento, id_servico),

    CONSTRAINT ck_item_valor CHECK (valor_cobrado >= 0)
);

CREATE TABLE comissao (
    id_comissao  SERIAL         PRIMARY KEY,
    id_item      INT            NOT NULL UNIQUE REFERENCES item_agendamento (id_item) ON DELETE RESTRICT,
    pct_aplicado DECIMAL(5, 2)  NOT NULL,
    valor        DECIMAL(10, 2) NOT NULL,
    competencia  DATE           NOT NULL, -- mês de referência (ex.: 2026-11-01)
    paga         BOOLEAN        NOT NULL DEFAULT FALSE,

    CONSTRAINT ck_com_pct         CHECK (pct_aplicado BETWEEN 0 AND 100),
    CONSTRAINT ck_com_valor       CHECK (valor >= 0),
    CONSTRAINT ck_com_competencia CHECK (competencia = date_trunc('month', competencia)::date)
);
