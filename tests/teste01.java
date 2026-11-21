// T1 - Validar tipo de dado do preço
// Teste COM banco de dados: servico.preco é DECIMAL(10, 2) (sql/01_schema.sql).
// O valor é enviado como texto para o PostgreSQL converter, como num
// INSERT escrito à mão. Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste01.java
import java.sql.*;

public class teste01 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T1 - Validar tipo de dado do preço");
        conectar();

        verifica("Preço numérico é aceito",
                !lanca(() -> inserirPreco("P1", "50.00")));
        verifica("Preço gravado com 2 casas decimais (50 -> 50.00)",
                !lanca(() -> inserirPreco("P2", "50"))
                && "50.00".equals(texto("SELECT preco::text FROM servico WHERE nome = 'Teste P2'")));
        verifica("Texto no campo preço é rejeitado",
                lanca(() -> inserirPreco("P3", "abc")));
        verifica("Texto '50 reais' no preço é rejeitado",
                lanca(() -> inserirPreco("P4", "50 reais")));
        verifica("Preço acima do limite de DECIMAL(10, 2) é rejeitado",
                lanca(() -> inserirPreco("P5", "123456789.00")));
        fim();
    }

    /** Envia o preço como texto sem tipo: quem converte (e valida) é o banco. */
    static void inserirPreco(String nome, String preco) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(
                "INSERT INTO servico (nome, preco, duracao_min) VALUES (?, ?, 30)")) {
            ps.setString(1, "Teste " + nome);
            ps.setObject(2, preco, Types.OTHER);
            ps.executeUpdate();
        }
    }
}
