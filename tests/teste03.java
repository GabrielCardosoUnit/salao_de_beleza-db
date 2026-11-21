// T3 - Validar telefone duplicado
// Teste COM banco de dados: cliente.telefone é UNIQUE (sql/01_schema.sql).
// Tudo é desfeito no final (ROLLBACK).
// Execução: java -cp lib/postgresql-42.7.4.jar tests/teste03.java
import java.sql.SQLException;

public class teste03 extends Db {

    public static void main(String[] args) throws Exception {
        System.out.println("T3 - Validar telefone duplicado");
        conectar();

        verifica("Primeiro telefone é aceito",
                !lanca(() -> cadastrarCliente("Ana", "79999999999")));
        verifica("Telefone diferente é aceito",
                !lanca(() -> cadastrarCliente("Bruno", "79888888888")));
        verifica("Telefone duplicado é rejeitado",
                lanca(() -> cadastrarCliente("Carla", "79999999999")));
        verifica("Telefone de um cliente já existente nos dados de exemplo é rejeitado",
                lanca(() -> cadastrarCliente("Daniel",
                        texto("SELECT telefone FROM cliente WHERE nome NOT LIKE 'Teste %' LIMIT 1"))));
        verifica("Só os 2 clientes válidos foram gravados",
                contar("SELECT COUNT(*) FROM cliente WHERE telefone IN ('79999999999', '79888888888')") == 2);
        fim();
    }

    static void cadastrarCliente(String nome, String telefone) throws SQLException {
        executar("INSERT INTO cliente (nome, telefone) VALUES (?, ?)", "Teste " + nome, telefone);
    }
}
