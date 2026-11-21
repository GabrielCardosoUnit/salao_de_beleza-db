
import java.math.BigDecimal;

public class teste02 {

    public static void main(String[] args) {

        System.out.println("T2 - Validar preco negativo e comissao");

        // Preco positivo deve ser aceito
        verifica("Preco positivo e aceito",
                !lanca(() -> validarPreco("50.00")));

        // Preco negativo deve ser rejeitado
        verifica("Preco negativo e rejeitado",
                lanca(() -> validarPreco("-50.00")));

        // Comissao de 50% deve ser aceita
        verifica("Comissao de 50% e aceita",
                !lanca(() -> validarComissao("50.00")));

        // Comissao de 150% deve ser rejeitada
        verifica("Comissao de 150% e rejeitada",
                lanca(() -> validarComissao("150.00")));

        fim();
    }

    static void validarPreco(String valor) {
        BigDecimal preco = new BigDecimal(valor);

        if (preco.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalStateException(
                    "O preco nao pode ser negativo"
            );
        }
    }

    static void validarComissao(String valor) {
        BigDecimal comissao = new BigDecimal(valor);

        if (comissao.compareTo(BigDecimal.ZERO) < 0 ||
            comissao.compareTo(new BigDecimal("100")) > 0) {

            throw new IllegalStateException(
                    "A comissao deve estar entre 0 e 100%"
            );
        }
    }

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
