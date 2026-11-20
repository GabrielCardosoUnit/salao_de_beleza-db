// T7 - Concluir agendamento
// Teste SEM banco de dados: valida as regras do schema em memória.
// Execução: java tests/07_teste.java
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.*;
import java.util.*;
import java.util.stream.*;

public class teste07 {

    public static void main(String[] args) {
        System.out.println("T7 - Concluir agendamento");
        Salao s = Salao.exemplo();
        Agendamento a = s.agendar(1, 1, dt("2026-11-20T10:00"), 1, 3);   // Corte 50 (40%) + Coloração 120 (50%)

        verifica("Status inicial é AGENDADO", a.status.equals("AGENDADO"));
        verifica("Sem comissão antes de concluir", s.comissoes.isEmpty());

        s.concluir(a.id);
        verifica("Status passa para CONCLUIDO", a.status.equals("CONCLUIDO"));
        verifica("Gera 1 comissão por item (2)", s.comissoes.size() == 2);

        BigDecimal total = s.comissoes.stream().map(Comissao::valor).reduce(BigDecimal.ZERO, BigDecimal::add);
        verifica("Comissão do Corte = 20,00",
                s.comissoes.stream().anyMatch(c -> c.idServico() == 1 && c.valor().compareTo(new BigDecimal("20.00")) == 0));
        verifica("Comissão da Coloração = 60,00",
                s.comissoes.stream().anyMatch(c -> c.idServico() == 3 && c.valor().compareTo(new BigDecimal("60.00")) == 0));
        verifica("Total de comissões = 80,00", total.compareTo(new BigDecimal("80.00")) == 0);
        verifica("Competência = 1º dia do mês do atendimento (2026-11-01)",
                s.comissoes.stream().allMatch(c -> c.competencia().equals(LocalDate.of(2026, 11, 1))));
        verifica("Concluir de novo é rejeitado (evita comissão duplicada)", lanca(() -> s.concluir(a.id)));
        verifica("Continuam 2 comissões após a tentativa", s.comissoes.size() == 2);
        verifica("Concluir agendamento inexistente é rejeitado", lanca(() -> s.concluir(999)));
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
            s.profissionais.put(1, "Ana"); s.profissionais.put(2, "Bruno");
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
