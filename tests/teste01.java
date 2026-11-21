
import java.math.BigDecimal;

public class teste01 {

    public static void main(String[] args) {

        System.out.println("T1 - Validar tipo de dado do preco");

        // Um preco numerico deve ser aceito
        verifica("Preco numerico e aceito",
                !lanca(() -> inserirPreco("50.00")));

        // Um texto nao pode ser utilizado como preco
        verifica("Texto no campo preco e rejeitado",
                lanca(() -> inserirPreco("abc")));

        // Texto com letras e numeros tambem deve ser rejeitado
        verifica("Texto '50 reais' no preco e rejeitado",
                lanca(() -> inserirPreco("50 reais")));

        fim();
    }

    // Simula a conversao para o tipo numerico DECIMAL(10,2)
    static BigDecimal inserirPreco(String valor) {
        try {
            return new BigDecimal(valor);
        } catch (NumberFormatException e) {
            throw new IllegalStateException(
                    "Preco deve ser um valor numerico"
            );
        }
    }

    // Framework de verificacao no padrao do grupo
    static int ok = 0;
    static int falhas = 0;

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
