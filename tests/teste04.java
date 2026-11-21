// T4 - Validar agendamento com cliente inexistente
// Teste COM banco de dados: FK agendamento.id_cliente -> cliente
// (sql/01_schema.sql). Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste04.java
public class teste04 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T4 - Validar agendamento com cliente inexistente");
        conectar();

        long ana = profissional("Ana");
        long corte = servico("Corte", "50.00", 30);
        habilita(ana, corte, "40.00");
        long cli = cliente("C1");
        long inexistente = contar("SELECT COALESCE(MAX(id_cliente), 0) + 1000 FROM cliente");

        verifica("Agendamento com cliente existente é aceito",
                !lanca(() -> agendar(cli, ana, "2026-11-20 10:00", corte)));
        verifica("Agendamento com cliente inexistente é rejeitado",
                lanca(() -> agendar(inexistente, ana, "2026-11-20 14:00", corte)));
        verifica("Nenhum agendamento foi gravado para o cliente inexistente",
                contar("SELECT COUNT(*) FROM agendamento WHERE id_cliente = ?", inexistente) == 0);
        fim();
    }
}
