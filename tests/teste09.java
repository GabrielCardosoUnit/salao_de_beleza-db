// T9 - Consultas: agenda do dia, comissão do mês por profissional, serviços mais vendidos
// Teste COM banco de dados: as consultas rodam em SQL sobre as tabelas reais,
// filtradas pela massa criada aqui. Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste09.java
import java.util.*;

public class teste09 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T9 - Consultas: agenda do dia, comissão do mês por profissional, serviços mais vendidos");
        conectar();

        long talita = profissional("Talita"), carlos = profissional("Carlos");
        long corte = servico("Corte", "50.00", 30);
        long escova = servico("Escova", "40.00", 30);
        long coloracao = servico("Coloração", "120.00", 90);
        for (long p : new long[]{talita, carlos}) {
            habilita(p, corte, "40.00");
            habilita(p, escova, "30.00");
            habilita(p, coloracao, "50.00");
        }
        long a1 = agendar(cliente("C1"), talita, "2026-11-20 09:00", corte);          // Corte 50
        long a2 = agendar(cliente("C2"), talita, "2026-11-20 11:00", corte, escova);  // Corte+Escova
        long a3 = agendar(cliente("C3"), carlos, "2026-11-20 10:00", coloracao);      // Coloração 120
        long a4 = agendar(cliente("C4"), carlos, "2026-11-21 10:00", corte);          // outro dia
        long a5 = agendar(cliente("C5"), carlos, "2026-10-15 10:00", corte);          // mês anterior
        long a6 = agendar(cliente("C6"), talita, "2026-11-20 15:00", escova);         // será cancelado
        concluir(a1); concluir(a2); concluir(a3); concluir(a5);
        cancelar(a6);

        // ---- Consulta 1: agenda do dia, sem cancelados, ordenada por horário
        List<List<String>> agenda = linhas("""
                SELECT a.id_agendamento, to_char(a.inicio, 'HH24:MI'), p.nome, a.status
                FROM agendamento a JOIN profissional p ON p.id_profissional = a.id_profissional
                WHERE a.inicio::date = DATE '2026-11-20'
                  AND a.status <> 'CANCELADO'
                  AND a.id_profissional IN (?, ?)
                ORDER BY a.inicio""", talita, carlos);
        System.out.println("\n  Agenda de 2026-11-20:");
        agenda.forEach(l -> System.out.println("    " + l.get(1) + " - " + l.get(2) + " [" + l.get(3) + "]"));
        verifica("Agenda do dia traz 3 agendamentos (cancelado e outros dias excluídos)", agenda.size() == 3);
        verifica("Agenda está em ordem de horário",
                agenda.stream().map(l -> Long.parseLong(l.get(0))).toList().equals(List.of(a1, a3, a2)));

        // ---- Consulta 2: comissão do mês (2026-11) por profissional
        Map<Long, String> porProf = new HashMap<>();
        for (List<String> l : linhas("""
                SELECT a.id_profissional, SUM(c.valor)
                FROM comissao c
                JOIN item_agendamento i ON i.id_item = c.id_item
                JOIN agendamento a      ON a.id_agendamento = i.id_agendamento
                WHERE c.competencia = DATE '2026-11-01'
                  AND a.id_profissional IN (?, ?)
                GROUP BY a.id_profissional""", talita, carlos))
            porProf.put(Long.parseLong(l.get(0)), l.get(1));
        System.out.println("\n  Comissão de 2026-11: Talita=" + porProf.get(talita) + ", Carlos=" + porProf.get(carlos));
        verifica("Talita: 20,00 + 20,00 + 12,00 = 52,00", dec("52.00").compareTo(dec(porProf.get(talita))) == 0);
        verifica("Carlos (só novembro): Coloração = 60,00", dec("60.00").compareTo(dec(porProf.get(carlos))) == 0);
        verifica("Comissão de outubro não entra no mês de novembro", porProf.size() == 2);

        // ---- Consulta 3: serviços mais vendidos (só itens de agendamentos CONCLUIDOS)
        List<List<String>> ranking = linhas("""
                SELECT s.nome, COUNT(*) AS vendas
                FROM item_agendamento i
                JOIN agendamento a ON a.id_agendamento = i.id_agendamento
                JOIN servico s     ON s.id_servico     = i.id_servico
                WHERE a.status = 'CONCLUIDO' AND s.id_servico IN (?, ?, ?)
                GROUP BY s.nome
                ORDER BY vendas DESC, s.nome""", corte, escova, coloracao);
        Map<String, Long> vendas = new HashMap<>();
        ranking.forEach(l -> vendas.put(l.get(0), Long.parseLong(l.get(1))));
        System.out.println("\n  Ranking de serviços: " + ranking);
        verifica("Mais vendido: Corte (3 vendas concluídas)",
                ranking.get(0).get(0).equals("Teste Corte") && ranking.get(0).get(1).equals("3"));
        verifica("Escova do cancelado não é contada (1 venda)", vendas.get("Teste Escova") == 1);
        verifica("Coloração = 1 venda", vendas.get("Teste Coloração") == 1);
        verifica("Agendamento de outro dia (não concluído) não entra no ranking",
                "AGENDADO".equals(status(a4)));
        fim();
    }
}
