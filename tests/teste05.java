// T5 - Dois horários sobrepostos para o mesmo profissional
// Teste COM banco de dados: quem bloqueia é o EXCLUDE ex_sem_sobreposicao
// (sql/01_schema.sql). Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste05.java
public class teste05 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T5 - Dois horários sobrepostos para o mesmo profissional");
        conectar();

        long ana = profissional("Ana"), bruno = profissional("Bruno");
        long corte = servico("Corte", "50.00", 30);
        long escova = servico("Escova", "40.00", 30);
        long coloracao = servico("Coloração", "120.00", 90);
        for (long p : new long[]{ana, bruno}) {
            habilita(p, corte, "40.00");
            habilita(p, escova, "30.00");
            habilita(p, coloracao, "50.00");
        }
        long c1 = cliente("C1"), c2 = cliente("C2"), c3 = cliente("C3");

        agendar(c1, ana, "2026-11-20 10:00", corte, escova);
        verifica("Fim calculado pelos itens = 11:00",
                "2026-11-20 11:00:00".equals(texto(
                        "SELECT fim::text FROM agendamento WHERE id_profissional = ?", ana)));

        verifica("Mesmo horário exato é rejeitado",
                lanca(() -> agendar(c2, ana, "2026-11-20 10:00", corte)));
        verifica("Início dentro de um agendamento existente é rejeitado",
                lanca(() -> agendar(c2, ana, "2026-11-20 10:30", corte)));
        verifica("Término invadindo o início de outro é rejeitado (09:45-10:15)",
                lanca(() -> agendar(c2, ana, "2026-11-20 09:45", corte)));
        verifica("Agendamento que engloba outro é rejeitado (09:30-11:00)",
                lanca(() -> agendar(c2, ana, "2026-11-20 09:30", coloracao)));
        verifica("Horários colados (11:00 logo após 10:00-11:00) são aceitos",
                !lanca(() -> agendar(c2, ana, "2026-11-20 11:00", corte)));
        verifica("Outro profissional no mesmo horário é aceito",
                !lanca(() -> agendar(c3, bruno, "2026-11-20 10:00", corte)));
        verifica("Outro dia para o mesmo profissional é aceito",
                !lanca(() -> agendar(c3, ana, "2026-11-21 10:00", corte)));
        verifica("Total de agendamentos válidos = 4",
                contar("SELECT COUNT(*) FROM agendamento WHERE id_profissional IN (?, ?)", ana, bruno) == 4);
        fim();
    }
}
