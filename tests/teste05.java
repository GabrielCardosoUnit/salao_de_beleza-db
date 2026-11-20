// T5 - Dois horários sobrepostos para o mesmo profissional
// Teste SEM banco de dados: valida as regras do schema em memória.
// Execução: java tests/05_teste.java
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.*;
import java.util.*;
import java.util.stream.*;

public class teste05 {

    public static void main(String[] args) {
        System.out.println("T5 - Dois horarios sobrepostos para o mesmo profissional");
        Salao s = Salao.exemplo();
        s.agendar(1, 1, dt("2026-11-20T10:00"), 1, 2);      // Ana 10:00-11:00

        verifica("Mesmo horário exato é rejeitado",
                lanca(() -> s.agendar(2, 1, dt("2026-11-20T10:00"), 1)));
        verifica("Início dentro de um agendamento existente e rejeitado",
                lanca(() -> s.agendar(2, 1, dt("2026-11-20T10:30"), 1)));
        verifica("Término invadindo o inicio de outro e rejeitado (09:45-10:15)",
                lanca(() -> s.agendar(2, 1, dt("2026-11-20T09:45"), 1)));
        verifica("Agendamento que engloba outro é rejeitado",
                lanca(() -> s.agendar(2, 1, dt("2026-11-20T09:30"), 3)));
        verifica("Horários colados (11:00 logo apos 10:00-11:00) sao aceitos",
                !lanca(() -> s.agendar(2, 1, dt("2026-11-20T11:00"), 1)));
        verifica("Outro profissional no mesmo horário é aceito",
                !lanca(() -> s.agendar(3, 2, dt("2026-11-20T10:00"), 1)));
        verifica("Outro dia para o mesmo profissional é aceito",
                !lanca(() -> s.agendar(3, 1, dt("2026-11-21T10:00"), 1)));
        verifica("Total de agendamentos validos = 4", s.agendamentos.size() == 4);
        fim();
    }

    // ======================================================================
    // Modelo em memoria do schema (sql/01_scema.sql). Nao usa banco de dados:
    // reproduz as regras (FKs, UNIQUE, status, comissao) para validar a logica.
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
                    throw new IllegalStateException("Profissional nao executa o servico " + s);
                a.itens.add(new Item(s, sv.preco()));
                dur += sv.duracaoMin();
            }
            a.fim = ini.plusMinutes(dur);
            if (!a.fim.isAfter(a.inicio)) throw new IllegalStateException("fim deve ser maior que inicio");
            // Regra de sobreposicao (a ser garantida pelo trigger em 02_triggers.sql):
            for (Agendamento o : agendamentos)
                if (o.idProfissional == prof && !o.status.equals("CANCELADO")
                        && ini.isBefore(o.fim) && a.fim.isAfter(o.inicio))
                    throw new IllegalStateException("Conflito de horario com o agendamento " + o.id);
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
            if (!a.status.equals("AGENDADO")) throw new IllegalStateException("So e possivel concluir AGENDADO (atual: " + a.status + ")");
            a.status = "CONCLUIDO";
            for (Item it : a.itens) {
                BigDecimal pct = pctComissao.get(a.idProfissional + "-" + it.idServico());
                BigDecimal valor = it.valorCobrado().multiply(pct).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
                comissoes.add(new Comissao(a.id, it.idServico(), pct, valor, a.inicio.toLocalDate().withDayOfMonth(1)));
            }
        }

        void cancelar(int idAg) {
            Agendamento a = buscar(idAg);
            if (a.status.equals("CONCLUIDO")) throw new IllegalStateException("Agendamento concluido nao pode ser cancelado");
            if (a.status.equals("CANCELADO")) throw new IllegalStateException("Agendamento ja cancelado");
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
            s.servicos.put(3, new Servico(3, "Coloracao",  new BigDecimal("120.00"), 90));
            for (int p : new int[]{1, 2}) {
                s.pctComissao.put(p + "-1", new BigDecimal("40.00"));
                s.pctComissao.put(p + "-2", new BigDecimal("30.00"));
                s.pctComissao.put(p + "-3", new BigDecimal("50.00"));
            }
            return s;
        }
    }

    // ---------------- mini framework de verificacao ----------------
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
