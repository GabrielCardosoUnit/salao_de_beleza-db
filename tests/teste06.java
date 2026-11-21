// T6 - Apagar profissionais que têm agendamentos
// Teste COM banco de dados: FK agendamento.id_profissional ON DELETE RESTRICT
// (sql/01_schema.sql). Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste06.java
public class teste06 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T6 - Apagar profissionais que têm agendamentos");
        conectar();

        long ana = profissional("Ana"), bruno = profissional("Bruno");
        long corte = servico("Corte", "50.00", 30);
        habilita(ana, corte, "40.00");
        habilita(bruno, corte, "40.00");
        long ag = agendar(cliente("C1"), ana, "2026-11-20 10:00", corte);   // Ana tem agendamento
        // Bruno não tem agendamentos

        verifica("Apagar profissional COM agendamento é bloqueado (ON DELETE RESTRICT)",
                lanca(() -> apagarProfissional(ana)));
        verifica("Profissional com agendamento continua cadastrado",
                contar("SELECT COUNT(*) FROM profissional WHERE id_profissional = ?", ana) == 1);
        verifica("Agendamento continua existindo após a tentativa",
                contar("SELECT COUNT(*) FROM agendamento WHERE id_agendamento = ?", ag) == 1);

        verifica("Apagar profissional SEM agendamento é permitido",
                !lanca(() -> apagarProfissional(bruno)));
        verifica("Profissional sem agendamento foi removido",
                contar("SELECT COUNT(*) FROM profissional WHERE id_profissional = ?", bruno) == 0);
        verifica("Expediente e serviços dele foram removidos junto (ON DELETE CASCADE)",
                contar("SELECT COUNT(*) FROM horario_trabalho WHERE id_profissional = ?", bruno) == 0
                && contar("SELECT COUNT(*) FROM profissional_servico WHERE id_profissional = ?", bruno) == 0);

        // Mesmo cancelado, o agendamento mantém a FK (RESTRICT não olha o status)
        cancelar(ag);
        verifica("Agendamento CANCELADO também impede apagar o profissional",
                lanca(() -> apagarProfissional(ana)));
        fim();
    }
}
