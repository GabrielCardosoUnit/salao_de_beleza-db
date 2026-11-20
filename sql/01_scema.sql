-- Apaga e recria (permite rodar o arquivo de novo após mudanças)
DROP TABLE IF EXISTS comissao, item_agendamento, agendamento, horario_trabalho,
                     profissional_servico, servico, profissional, cliente CASCADE;


CREATE TABLE cliente (
    id_cliente     SERIAL       PRIMARY KEY,
    nome           VARCHAR(100) NOT NULL,
    telefone       VARCHAR(15)  NOT NULL UNIQUE,
    email          VARCHAR(120) UNIQUE,
    data_cadastro  DATE         NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE profissional (
    id_profissional  SERIAL       PRIMARY KEY,
    nome             VARCHAR(100) NOT NULL,
    cpf              CHAR(11)     NOT NULL UNIQUE,
    telefone         VARCHAR(15),
    ativo            BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE servico (
    id_servico   SERIAL        PRIMARY KEY,
    nome         VARCHAR(80)   NOT NULL UNIQUE,
    preco        DECIMAL(10,2) NOT NULL,
    duracao_min  INT           NOT NULL
);

CREATE TABLE profissional_servico (
    id_profissional  INT          NOT NULL REFERENCES profissional(id_profissional) ON DELETE CASCADE,
    id_servico       INT          NOT NULL REFERENCES servico(id_servico)           ON DELETE RESTRICT,
    pct_comissao     DECIMAL(5,2) NOT NULL,
    PRIMARY KEY (id_profissional, id_servico)
);

CREATE TABLE horario_trabalho (
    id_profissional  INT      NOT NULL REFERENCES profissional(id_profissional) ON DELETE CASCADE,
    dia_semana       SMALLINT NOT NULL,
    hora_inicio      TIME     NOT NULL,
    hora_fim         TIME     NOT NULL,
    PRIMARY KEY (id_profissional, dia_semana)
);

CREATE TABLE agendamento (
    id_agendamento   SERIAL       PRIMARY KEY,
    id_cliente       INT          NOT NULL REFERENCES cliente(id_cliente)           ON DELETE RESTRICT,
    id_profissional  INT          NOT NULL REFERENCES profissional(id_profissional) ON DELETE RESTRICT,
    inicio           TIMESTAMP    NOT NULL,
    fim              TIMESTAMP    NOT NULL,
    status           VARCHAR(10)  NOT NULL DEFAULT 'AGENDADO',
    observacao       VARCHAR(255)
);

CREATE TABLE item_agendamento (
    id_item         SERIAL        PRIMARY KEY,
    id_agendamento  INT           NOT NULL REFERENCES agendamento(id_agendamento) ON DELETE CASCADE,
    id_servico      INT           NOT NULL REFERENCES servico(id_servico)         ON DELETE RESTRICT,
    valor_cobrado   DECIMAL(10,2) NOT NULL,
    UNIQUE (id_agendamento, id_servico)
);

CREATE TABLE comissao (
    id_comissao   SERIAL        PRIMARY KEY,
    id_item       INT           NOT NULL UNIQUE REFERENCES item_agendamento(id_item) ON DELETE RESTRICT,
    pct_aplicado  DECIMAL(5,2)  NOT NULL,
    valor         DECIMAL(10,2) NOT NULL,
    competencia   DATE          NOT NULL,          -- mês de referência (ex.: 2026-11-01)
    paga          BOOLEAN       NOT NULL DEFAULT FALSE
);