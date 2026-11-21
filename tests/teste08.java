// T8 - Cancelar agendamento
// Teste COM banco de dados: EXCLUDE ignora cancelados e o trigger
// trg_ag_comissao desfaz comissões ao sair de CONCLUIDO (sql/02_triggers.sql).
// Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste08.java
public class teste08 extends Db {

    static final String COMISSOES = """
            SELECT COUNT(*) FROM comissao c JOIN item_agendamento i ON i.id_item = c.id_item
            WHERE i.id_agendamento = ?""";

    public static void main(String[] args) throws Exception {
        System.out.println("T8 - Cancelar agendamento");
        conectar();

        long ana = profissional("Ana");
        long corte = servico("Corte", "50.00", 30);
        habilita(ana, corte, "40.00");
        long cli = cliente("C1");
        long a = agendar(cli, ana, "2026-11-20 10:00", corte);
        long b = agendar(cli, ana, "2026-11-20 14:00", corte);
        long c = agendar(cli, ana, "2026-11-20 16:00", corte);

        cancelar(a);
        verifica("Status passa para CANCELADO", "CANCELADO".equals(status(a)));
        verifica("Cancelar não gera comissão", contar(COMISSOES, a) == 0);
        verifica("Horário cancelado fica livre para novo agendamento",
                !lanca(() -> agendar(cliente("C2"), ana, "2026-11-20 10:00", corte)));
        verifica("Cancelar duas vezes não gera erro e mantém CANCELADO",
                !lanca(() -> cancelar(a)) && "CANCELADO".equals(status(a)));

        // Comissão já paga trava o agendamento em CONCLUIDO
        concluir(b);
        executar("UPDATE comissao SET paga = TRUE WHERE id_item IN "
                + "(SELECT id_item FROM item_agendamento WHERE id_agendamento = ?)", b);
        verifica("CONCLUIDO com comissão paga não pode ser cancelado", lanca(() -> cancelar(b)));
        verifica("Comissão do concluído permanece intacta", contar(COMISSOES, b) == 1);

        // Comissão ainda não paga: cancelar é permitido e desfaz a comissão
        concluir(c);
        verifica("CONCLUIDO com comissão não paga pode ser cancelado", !lanca(() -> cancelar(c)));
        verifica("Cancelar um CONCLUIDO apaga a comissão não paga", contar(COMISSOES, c) == 0);

        verifica("Cancelar agendamento inexistente não altera nenhuma linha", cancelar(-1) == 0);

        // CANCELADO -> CONCLUIDO é bloqueado (trg_ag_cancelado_nao_conclui).
        // Usa um horário livre para o EXCLUDE não interferir no resultado.
        long d = agendar(cli, ana, "2026-11-20 18:00", corte);
        cancelar(d);
        verifica("Agendamento cancelado não pode ser concluído", lanca(() -> concluir(d)));
        verifica("Cancelado continua sem comissão", contar(COMISSOES, d) == 0);
        executar("UPDATE agendamento SET status = 'AGENDADO' WHERE id_agendamento = ?", d);
        verifica("Cancelado reaberto (AGENDADO) pode ser concluído", !lanca(() -> concluir(d)));
        fim();
    }
}
