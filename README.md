# salao_de_beleza-banco_de_dados

Banco de dados PostgreSQL 17 para um salão de beleza: clientes, profissionais, serviços, agendamentos e comissões.

## Como rodar

```bash
cp .env.example .env   # preencha POSTGRES_DB, POSTGRES_USER e POSTGRES_PASSWORD
docker compose up -d
```

Os scripts de `sql/` são executados em ordem alfabética **apenas na primeira criação do volume**. Depois de alterar algum script, recrie o banco (apaga os dados):

```bash
docker compose down -v
docker compose up -d
```

## Testes

O `sql/07_testes.sql` confere todas as regras abaixo e imprime `OK: ...` para cada uma. Ele roda dentro de uma transação desfeita no final, então não deixa dados no banco.

Os testes rodam sozinhos na criação do banco. Para ver o resultado:

```bash
docker compose logs db | findstr "OK: FALHOU PASSARAM"
```

Para rodar de novo a qualquer momento:

```bash
docker compose exec db psql -f /docker-entrypoint-initdb.d/07_testes.sql
```

Se tudo estiver certo, a saída termina com `>>> TODOS OS TESTES PASSARAM <<<`. Se alguma regra falhar, a execução para com `FALHOU: <nome do teste>`.

Para abrir o terminal do banco:

```bash
docker compose exec db psql
```

## Estrutura

| Arquivo                  | Conteúdo                                                                            |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `sql/01_schema.sql`    | Tabelas, PK, FK, CHECKs e a regra anti-conflito de horário                          |
| `sql/02_triggers.sql`  | Regras de negócio (expediente, serviço x profissional, cálculo do fim, comissão) |
| `sql/03_indices.sql`   | Índices das FKs e e-mail único sem diferenciar maiúsculas                         |
| `sql/05_dados.sql`     | Dados de exemplo                                                                     |
| `sql/06_consultas.sql` | Consultas                                                                            |
| `sql/07_testes.sql`    | Testes das regras                                                                    |
| `docs/der.md`          | Diagrama entidade-relacionamento (Mermaid, renderizado pelo GitHub)                  |

## Regras de negócio

- **Sem conflito de horário:** um profissional não pode ter dois agendamentos sobrepostos (`EXCLUDE USING gist`). Agendamentos cancelados não contam, e horários encostados (10h–11h e 11h–12h) são permitidos.
- **Status:** `AGENDADO`, `CONFIRMADO`, `CONCLUIDO` ou `CANCELADO`.
- **Expediente:** o agendamento precisa estar dentro do `horario_trabalho` do profissional naquele dia da semana (0 = domingo … 6 = sábado), no mesmo dia, e o profissional precisa estar ativo.
- **Serviço x profissional:** só é possível lançar um serviço que o profissional realiza (`profissional_servico`).
- **Fim do agendamento:** recalculado automaticamente como `inicio + soma das durações` dos serviços lançados.
- **Valor cobrado:** se não for informado, usa o preço atual do serviço.
- **Comissão:** gerada automaticamente quando o agendamento passa para `CONCLUIDO`, guardando o percentual aplicado e o mês de competência.
