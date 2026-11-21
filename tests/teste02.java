// T2 - Validar preço negativo e percentual de comissão
// Teste COM banco de dados: CHECKs ck_serv_preco (servico) e ck_ps_pct
// (profissional_servico) em sql/01_schema.sql. Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste02.java
public class teste02 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T2 - Validar preço negativo e percentual de comissão");
        conectar();

        // Preço do serviço (ck_serv_preco: preco >= 0)
        verifica("Preço positivo é aceito", !lanca(() -> servico("Corte", "50.00", 30)));
        verifica("Preço zero é aceito (serviço gratuito)", !lanca(() -> servico("Cortesia", "0.00", 30)));
        verifica("Preço negativo é rejeitado", lanca(() -> servico("Negativo", "-50.00", 30)));

        // Percentual de comissão (ck_ps_pct: entre 0 e 100)
        long prof = profissional("Ana");
        long s1 = servico("S1", "50.00", 30), s2 = servico("S2", "50.00", 30),
             s3 = servico("S3", "50.00", 30), s4 = servico("S4", "50.00", 30);
        verifica("Comissão de 50% é aceita", !lanca(() -> habilita(prof, s1, "50.00")));
        verifica("Comissão de 100% é aceita (limite)", !lanca(() -> habilita(prof, s2, "100.00")));
        verifica("Comissão de 150% é rejeitada", lanca(() -> habilita(prof, s3, "150.00")));
        verifica("Comissão negativa é rejeitada", lanca(() -> habilita(prof, s4, "-1.00")));
        fim();
    }
}
