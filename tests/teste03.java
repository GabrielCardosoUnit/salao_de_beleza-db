
import java.util.HashSet;
import java.util.Set;

public class teste03 {

    static Set<String> telefones = new HashSet<>();

    static int ok = 0;
    static int falhas = 0;

    public static void main(String[] args) {

        System.out.println("T3 - Validar telefone duplicado");

        // Primeiro telefone deve ser aceito
        verifica("Primeiro telefone e aceito",
                !lanca(() -> cadastrarCliente("79999999999")));

        // Telefone diferente deve ser aceito
        verifica("Telefone diferente e aceito",
                !lanca(() -> cadastrarCliente("79888888888")));

        // Telefone repetido deve ser rejeitado
        verifica("Telefone duplicado e rejeitado",
                lanca(() -> cadastrarCliente("79999999999")));

        fim();
    }

    static void cadastrarCliente(String telefone) {

        if (!telefones.add(telefone)) {
            throw new IllegalStateException(
                    "Telefone ja cadastrado"
            );
        }
    }

    static void verifica(String descricao, boolean condicao) {
        if (condicao) {
            ok++;
            System.out.println("  [OK] " + descricao);
        } else {
            falhas++;
            System.out.println("  [FALHA] " + descricao);
        }
    }

    static boolean lanca(Runnable acao) {
        try {
            acao.run();
            return false;
        } catch (IllegalStateException e) {
            System.out.println(
                    "  (erro esperado: " + e.getMessage() + ")"
            );
            return true;
        }
    }

    static void fim() {
        System.out.println(
                "\nResultado: " + ok + " ok, " + falhas + " falha(s)"
        );

        if (falhas > 0) {
            System.exit(1);
        }
    }
}
