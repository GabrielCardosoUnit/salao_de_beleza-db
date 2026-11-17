```mermaid
erDiagram
    cliente ||--o{ agendamento : "faz"
    profissional ||--o{ agendamento : "atende"
    profissional ||--o{ profissional_servico : "realiza"
    servico ||--o{ profissional_servico : "é realizado por"
    profissional ||--o{ horario_trabalho : "trabalha em"
    agendamento ||--|{ item_agendamento : "contém"
    servico ||--o{ item_agendamento : "é lançado em"
    item_agendamento ||--o| comissao : "gera"

    cliente {
        serial id_cliente PK
        varchar nome "100"
        varchar telefone UK "15"
        varchar email UK "120, nulo, único sem diferenciar maiúsculas"
        date data_cadastro "default CURRENT_DATE"
    }

    profissional {
        serial id_profissional PK
        varchar nome "100"
        char cpf UK "11 dígitos"
        varchar telefone "15, nulo"
        boolean ativo "default TRUE"
    }

    servico {
        serial id_servico PK
        varchar nome UK "80"
        decimal preco "10,2 - maior ou igual a 0"
        int duracao_min "maior que 0"
    }

    profissional_servico {
        int id_profissional PK, FK
        int id_servico PK, FK
        decimal pct_comissao "5,2 - entre 0 e 100"
    }

    horario_trabalho {
        int id_profissional PK, FK
        smallint dia_semana PK "0 = domingo ... 6 = sábado"
        time hora_inicio
        time hora_fim "maior que hora_inicio"
    }

    agendamento {
        serial id_agendamento PK
        int id_cliente FK
        int id_profissional FK
        timestamp inicio
        timestamp fim "maior que inicio"
        varchar status "AGENDADO, CONFIRMADO, CONCLUIDO, CANCELADO"
        varchar observacao "255, nulo"
    }

    item_agendamento {
        serial id_item PK
        int id_agendamento FK
        int id_servico FK
        decimal valor_cobrado "10,2 - maior ou igual a 0"
    }

    comissao {
        serial id_comissao PK
        int id_item FK, UK
        decimal pct_aplicado "5,2 - entre 0 e 100"
        decimal valor "10,2 - maior ou igual a 0"
        date competencia "primeiro dia do mês"
        boolean paga "default FALSE"
    }
```

## Restrições que o diagrama não mostra

- `agendamento`: um profissional não pode ter dois agendamentos sobrepostos (`EXCLUDE USING gist`), exceto os `CANCELADO`.
- `item_agendamento`: o par (`id_agendamento`, `id_servico`) é único.
- As demais regras de negócio (expediente, serviço x profissional, cálculo do fim e da comissão) ficam em [`sql/02_triggers.sql`](../sql/02_triggers.sql).
