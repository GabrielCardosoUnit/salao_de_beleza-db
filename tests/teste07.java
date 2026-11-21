// T7 - Concluir agendamento
// Teste COM banco de dados: a comissão é gerada pelo trigger trg_ag_comissao
// (sql/02_triggers.sql). Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste07.java
import java.math.BigDecimal;

public class teste07 extends Db {

    static final String COMISSOES = """
            FROM comissao c JOIN item_agendamento i ON i.id_item = c.id_item
            WHERE i.id_agendamento = ?""";

    public static void main(String[] args) throws Exception {
        System.out.println("T7 - Concluir agendamento");
        conectar();

        long ana = profissional("Ana");
        long corte = servico("Corte", "50.00", 30);
        long coloracao = servico("Coloração", "120.00", 90);
        habilita(ana, corte, "40.00");
        habilita(ana, coloracao, "50.00");
        long a = agendar(cliente("C1"), ana, "2026-11-20 10:00", corte, coloracao);  // 50 (40%) + 120 (50%)

        verifica("Status inicial é AGENDADO", "AGENDADO".equals(status(a)));
        verifica("Sem comissão antes de concluir", contar("SELECT COUNT(*) " + COMISSOES, a) == 0);

        concluir(a);
        verifica("Status passa para CONCLUIDO", "CONCLUIDO".equals(status(a)));
        verifica("Gera 1 comissão por item (2)", contar("SELECT COUNT(*) " + COMISSOES, a) == 2);

        verifica("Comissão do Corte = 20,00",
                dec("20.00").compareTo(decimal("SELECT c.valor " + COMISSOES + " AND i.id_servico = ?", a, corte)) == 0);
        verifica("Comissão da Coloração = 60,00",
                dec("60.00").compareTo(decimal("SELECT c.valor " + COMISSOES + " AND i.id_servico = ?", a, coloracao)) == 0);
        BigDecimal total = decimal("SELECT SUM(c.valor) " + COMISSOES, a);
        verifica("Total de comissões = 80,00", dec("80.00").compareTo(total) == 0);
        verifica("Competência = 1º dia do mês do atendimento (2026-11-01)",
                contar("SELECT COUNT(*) " + COMISSOES + " AND c.competencia <> DATE '2026-11-01'", a) == 0);

        // No banco, concluir de novo não dá erro (o UPDATE não muda o status,
        // então o trigger não dispara) - o importante é não duplicar comissão.
        verifica("Concluir de novo não gera erro", !lanca(() -> concluir(a)));
        verifica("Continuam 2 comissões após concluir de novo (sem duplicar)",
                contar("SELECT COUNT(*) " + COMISSOES, a) == 2);

        verifica("Concluir agendamento inexistente não altera nenhuma linha", concluir(-1) == 0);

        long vazio = id("""
                INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim)
                VALUES (?, ?, '2026-11-20 15:00', '2026-11-20 15:30') RETURNING id_agendamento""",
                cliente("C2"), ana);
        verifica("Concluir agendamento sem serviços lançados é rejeitado", lanca(() -> concluir(vazio)));
        fim();
    }
}
