// T9 - Consultas: agenda do dia, comissão do mês por profissional, serviços mais vendidos
// Teste SEM banco de dados: valida as regras do schema em memória.
// Execução: java tests/09_teste.java
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.*;
import java.util.*;
import java.util.stream.*;

public class teste09 {

    public static void main(String[] args) {
        System.out.println("T9 - Consultas: agenda do dia, comissão do mês por profissional, serviços mais vendidos");
        Salao s = Salao.exemplo();
        Agendamento a1 = s.agendar(1, 1, dt("2026-11-20T09:00"), 1);        // Talita  Corte 50
        Agendamento a2 = s.agendar(2, 1, dt("2026-11-20T11:00"), 1, 2);     // Talita  Corte+Escova
        Agendamento a3 = s.agendar(3, 2, dt("2026-11-20T10:00"), 3);        // Carlos Coloração 120
        Agendamento a4 = s.agendar(4, 2, dt("2026-11-21T10:00"), 1);        // Carlos, outro dia
        Agendamento a5 = s.agendar(5, 2, dt("2026-10-15T10:00"), 1);        // Carlos, mês anterior
        Agendamento a6 = s.agendar(6, 1, dt("2026-11-20T15:00"), 2);        // Talita, será cancelado
        s.concluir(a1.id); s.concluir(a2.id); s.concluir(a3.id); s.concluir(a5.id);
        s.cancelar(a6.id);

        // ---- Consulta 1: agenda do dia (2026-11-20), sem cancelados, ordenada por horário
        LocalDate dia = LocalDate.of(2026, 11, 20);
        List<Agendamento> agenda = s.agendamentos.stream()
                .filter(a -> a.inicio.toLocalDate().equals(dia) && !a.status.equals("CANCELADO"))
                .sorted(Comparator.comparing(a -> a.inicio)).collect(Collectors.toList());
        System.out.println("\n  Agenda de " + dia + ":");
        agenda.forEach(a -> System.out.println("    " + a.inicio.toLocalTime() + " - " + s.profissionais.get(a.idProfissional) + " [" + a.status + "]"));
        verifica("Agenda do dia traz 3 agendamentos (cancelado e outros dias excluídos)", agenda.size() == 3);
        verifica("Agenda está em ordem de horário",
                agenda.get(0).id == a1.id && agenda.get(1).id == a3.id && agenda.get(2).id == a2.id);

        // ---- Consulta 2: comissão do mês (2026-11) por profissional
        LocalDate mes = LocalDate.of(2026, 11, 1);
        Map<String, BigDecimal> porProf = new TreeMap<>();
        for (Comissao c : s.comissoes) {
            if (!c.competencia().equals(mes)) continue;
            Agendamento ag = s.buscar(c.idAgendamento());
            porProf.merge(s.profissionais.get(ag.idProfissional), c.valor(), BigDecimal::add);
        }
        System.out.println("\n  Comissão de 2026-11 por profissional: " + porProf);
        verifica("Talita: 20,00 + 20,00 + 12,00 = 52,00", porProf.get("Talita").compareTo(new BigDecimal("52.00")) == 0);
        verifica("Carlos (só novembro): Coloração = 60,00", porProf.get("Carlos").compareTo(new BigDecimal("60.00")) == 0);
        verifica("Comissão de outubro não entra no mês de novembro", porProf.size() == 2);

        // ---- Consulta 3: serviços mais vendidos (apenas itens de agendamentos CONCLUIDOS)
        Map<String, Long> vendas = new HashMap<>();
        for (Agendamento ag : s.agendamentos)
            if (ag.status.equals("CONCLUIDO"))
                for (Item it : ag.itens) vendas.merge(s.servicos.get(it.idServico()).nome(), 1L, Long::sum);
        List<Map.Entry<String, Long>> ranking = vendas.entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey()))
                .collect(Collectors.toList());
        System.out.println("\n  Ranking de serviços: " + ranking);
        verifica("Mais vendido: Corte (3 vendas concluídas)",
                ranking.get(0).getKey().equals("Corte") && ranking.get(0).getValue() == 3);
        verifica("Escova do cancelado não é contada (1 venda)", vendas.get("Escova") == 1);
        verifica("Coloração = 1 venda", vendas.get("Coloração") == 1);
        fim();
    }

    // ======================================================================
    // Modelo em memória do schema (sql/01_scema.sql). Não usa banco de dados:
    // reproduz as regras (FKs, UNIQUE, status, comissão) para validar a lógica.
    // ======================================================================
    record Servico(int id, String nome, BigDecimal preco, int duracaoMin) {}
    record Item(int idServico, BigDecimal valorCobrado) {}
    record Comissao(int idAgendamento, int idServico, BigDecimal pct, BigDecimal valor, LocalDate competencia) {}

    static class Agendamento {
        int id, idCliente, idProfissional;
        LocalDateTime inicio, fim;
        String status = "AGENDADO";           // AGENDADO | CONCLUIDO | CANCELADO
        List<Item> itens = new ArrayList<>();
    }

    static class Salao {
        Map<Integer, String> profissionais = new LinkedHashMap<>();
        Map<Integer, Servico> servicos = new LinkedHashMap<>();
        Map<String, BigDecimal> pctComissao = new HashMap<>();   // "idProf-idServ" -> %
        List<Agendamento> agendamentos = new ArrayList<>();
        List<Comissao> comissoes = new ArrayList<>();
        int seq = 1;

        Agendamento agendar(int cli, int prof, LocalDateTime ini, int... servs) {
            if (!profissionais.containsKey(prof)) throw new IllegalStateException("FK: profissional inexistente");
            Agendamento a = new Agendamento();
            a.idCliente = cli; a.idProfissional = prof; a.inicio = ini;
            int dur = 0;
            for (int s : servs) {
                Servico sv = servicos.get(s);
                if (!pctComissao.containsKey(prof + "-" + s))
                    throw new IllegalStateException("Profissional não executa o serviço " + s);
                a.itens.add(new Item(s, sv.preco()));
                dur += sv.duracaoMin();
            }
            a.fim = ini.plusMinutes(dur);
            if (!a.fim.isAfter(a.inicio)) throw new IllegalStateException("fim deve ser maior que início");
            // Regra de sobreposição (a ser garantida pelo trigger em 02_triggers.sql):
            for (Agendamento o : agendamentos)
                if (o.idProfissional == prof && !o.status.equals("CANCELADO")
                        && ini.isBefore(o.fim) && a.fim.isAfter(o.inicio))
                    throw new IllegalStateException("Conflito de horário com o agendamento " + o.id);
            a.id = seq++;
            agendamentos.add(a);
            return a;
        }

        // DELETE FROM profissional: FK agendamento.id_profissional é ON DELETE RESTRICT
        void apagarProfissional(int prof) {
            for (Agendamento a : agendamentos)
                if (a.idProfissional == prof)
                    throw new IllegalStateException("RESTRICT: profissional possui agendamentos");
            profissionais.remove(prof);
        }

        void concluir(int idAg) {
            Agendamento a = buscar(idAg);
            if (!a.status.equals("AGENDADO")) throw new IllegalStateException("Só é possível concluir AGENDADO (atual: " + a.status + ")");
            a.status = "CONCLUIDO";
            for (Item it : a.itens) {
                BigDecimal pct = pctComissao.get(a.idProfissional + "-" + it.idServico());
                BigDecimal valor = it.valorCobrado().multiply(pct).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
                comissoes.add(new Comissao(a.id, it.idServico(), pct, valor, a.inicio.toLocalDate().withDayOfMonth(1)));
            }
        }

        void cancelar(int idAg) {
            Agendamento a = buscar(idAg);
            if (a.status.equals("CONCLUIDO")) throw new IllegalStateException("Agendamento concluído não pode ser cancelado");
            if (a.status.equals("CANCELADO")) throw new IllegalStateException("Agendamento já cancelado");
            a.status = "CANCELADO";
        }

        Agendamento buscar(int id) {
            return agendamentos.stream().filter(x -> x.id == id).findFirst()
                    .orElseThrow(() -> new IllegalStateException("Agendamento inexistente"));
        }

        // Dados de exemplo
        static Salao exemplo() {
            Salao s = new Salao();
            s.profissionais.put(1, "Talita"); s.profissionais.put(2, "Carlos");
            s.servicos.put(1, new Servico(1, "Corte",      new BigDecimal("50.00"),  30));
            s.servicos.put(2, new Servico(2, "Escova",     new BigDecimal("40.00"),  30));
            s.servicos.put(3, new Servico(3, "Coloração",  new BigDecimal("120.00"), 90));
            for (int p : new int[]{1, 2}) {
                s.pctComissao.put(p + "-1", new BigDecimal("40.00"));
                s.pctComissao.put(p + "-2", new BigDecimal("30.00"));
                s.pctComissao.put(p + "-3", new BigDecimal("50.00"));
            }
            return s;
        }
    }

    // ---------------- mini framework de verificação ----------------
    static int ok = 0, falhas = 0;
    static void verifica(String desc, boolean cond) {
        if (cond) { ok++; System.out.println("  [OK]    " + desc); }
        else { falhas++; System.out.println("  [FALHA] " + desc); }
    }
    static boolean lanca(Runnable r) {
        try { r.run(); return false; } catch (IllegalStateException e) { System.out.println("          (erro esperado: " + e.getMessage() + ")"); return true; }
    }
    static void fim() {
        System.out.println("\nResultado: " + ok + " ok, " + falhas + " falha(s)");
        if (falhas > 0) System.exit(1);
    }
    static LocalDateTime dt(String s) { return LocalDateTime.parse(s); }
}
