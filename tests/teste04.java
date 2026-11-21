
import java.util.HashSet;
import java.util.Set;

public class teste04 {

    static Set<Integer> clientesExistentes = new HashSet<>();

    static int ok = 0;
    static int falhas = 0;

    public static void main(String[] args) {

        System.out.println("T4 - Validar agendamento com cliente inexistente");

        // Simula clientes cadastrados
        clientesExistentes.add(1);
        clientesExistentes.add(2);

        // Cliente existente deve permitir agendamento
        verifica("Agendamento com cliente existente e aceito",
                !lanca(() -> agendar(1)));

        // Cliente inexistente deve impedir agendamento
        verifica("Agendamento com cliente inexistente e rejeitado",
                lanca(() -> agendar(999999)));

        fim();
    }

    static void agendar(int idCliente) {

        if (!clientesExistentes.contains(idCliente)) {
            throw new IllegalStateException(
                    "Cliente nao encontrado"
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
