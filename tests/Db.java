// Helper compartilhado pelos testes T5-T9: conexão com o PostgreSQL do
// docker-compose, criação de massa de teste e mini framework de verificação.
//
// Tudo roda numa única transação desfeita no final (ROLLBACK), então os
// testes não deixam dados no banco e não mexem nos dados de 05_dados.sql.
//
// Execução (a partir da raiz do projeto, com o banco no ar):
//   java -cp lib/postgresql-42.7.4.jar tests/teste05.java
import java.math.BigDecimal;
import java.nio.file.*;
import java.sql.*;
import java.util.*;

public class Db {

    static Connection con;
    static int ok = 0, falhas = 0, avisos = 0, seq = 0;

    // ------------------------------------------------------------------
    // Conexão
    // ------------------------------------------------------------------

    /** Conecta usando as variáveis do .env (as mesmas do docker-compose). */
    static void conectar() {
        Map<String, String> env = lerEnv();
        String host = env.getOrDefault("DB_HOST", "localhost");
        String port = env.getOrDefault("DB_PORT", "5432");
        String url = "jdbc:postgresql://" + host + ":" + port + "/" + exigir(env, "POSTGRES_DB");
        try {
            con = DriverManager.getConnection(url, exigir(env, "POSTGRES_USER"), exigir(env, "POSTGRES_PASSWORD"));
            con.setAutoCommit(false);
        } catch (SQLException e) {
            System.err.println("Não foi possível conectar em " + url + ": " + e.getMessage());
            System.err.println("O banco está no ar? Rode: docker compose up -d");
            System.exit(2);
        }
    }

    /** Lê o .env da raiz do projeto; variáveis de ambiente do sistema têm prioridade. */
    static Map<String, String> lerEnv() {
        Map<String, String> env = new HashMap<>();
        for (Path p : List.of(Path.of(".env"), Path.of("..", ".env"))) {
            if (!Files.exists(p)) continue;
            try {
                for (String linha : Files.readAllLines(p)) {
                    linha = linha.strip();
                    if (linha.isEmpty() || linha.startsWith("#") || !linha.contains("=")) continue;
                    int i = linha.indexOf('=');
                    env.put(linha.substring(0, i).strip(), linha.substring(i + 1).strip());
                }
            } catch (Exception e) {
                throw new RuntimeException("Erro lendo " + p, e);
            }
            break;
        }
        env.putAll(System.getenv());
        return env;
    }

    static String exigir(Map<String, String> env, String chave) {
        String v = env.get(chave);
        if (v == null || v.isBlank()) {
            System.err.println("Variável " + chave + " não encontrada. Crie o .env a partir do .env.example.");
            System.exit(2);
        }
        return v;
    }

    // ------------------------------------------------------------------
    // Massa de teste (dados únicos para não colidir com 05_dados.sql)
    // ------------------------------------------------------------------

    static long cliente(String nome) throws SQLException {
        return id("INSERT INTO cliente (nome, telefone) VALUES (?, ?) RETURNING id_cliente",
                "Teste " + nome, String.format("0990000%04d", ++seq));
    }

    /** Cria um profissional que trabalha todos os dias, das 08:00 às 20:00. */
    static long profissional(String nome) throws SQLException {
        long id = id("INSERT INTO profissional (nome, cpf) VALUES (?, ?) RETURNING id_profissional",
                "Teste " + nome, String.format("0990000%04d", ++seq));
        executar("""
                INSERT INTO horario_trabalho (id_profissional, dia_semana, hora_inicio, hora_fim)
                SELECT ?, d, '08:00', '20:00' FROM generate_series(0, 6) d""", id);
        return id;
    }

    static long servico(String nome, String preco, int duracaoMin) throws SQLException {
        return id("INSERT INTO servico (nome, preco, duracao_min) VALUES (?, ?, ?) RETURNING id_servico",
                "Teste " + nome, new BigDecimal(preco), duracaoMin);
    }

    /** Liga profissional ao serviço com o percentual de comissão. */
    static void habilita(long prof, long serv, String pct) throws SQLException {
        executar("INSERT INTO profissional_servico (id_profissional, id_servico, pct_comissao) VALUES (?, ?, ?)",
                prof, serv, new BigDecimal(pct));
    }

    // ------------------------------------------------------------------
    // Operações do salão (SQL real; as regras são do schema e dos triggers)
    // ------------------------------------------------------------------

    /**
     * Cria o agendamento e lança os serviços. O fim já é enviado como
     * inicio + soma das durações, para o EXCLUDE checar o intervalo real.
     * Se qualquer passo falhar, nada do agendamento fica gravado.
     */
    static long agendar(long cli, long prof, String inicio, long... servs) throws SQLException {
        Savepoint sp = con.setSavepoint();
        try {
            Long[] ids = Arrays.stream(servs).boxed().toArray(Long[]::new);
            long ag;
            try (PreparedStatement ps = con.prepareStatement("""
                    INSERT INTO agendamento (id_cliente, id_profissional, inicio, fim)
                    SELECT ?, ?, ?::timestamp,
                           ?::timestamp + make_interval(mins => SUM(duracao_min)::int)
                    FROM servico WHERE id_servico = ANY (?)
                    RETURNING id_agendamento""")) {
                ps.setLong(1, cli);
                ps.setLong(2, prof);
                ps.setString(3, inicio);
                ps.setString(4, inicio);
                ps.setArray(5, con.createArrayOf("bigint", ids));
                try (ResultSet rs = ps.executeQuery()) { rs.next(); ag = rs.getLong(1); }
            }
            for (long s : servs)
                executar("INSERT INTO item_agendamento (id_agendamento, id_servico, valor_cobrado) VALUES (?, ?, NULL)", ag, s);
            con.releaseSavepoint(sp);
            return ag;
        } catch (SQLException e) {
            con.rollback(sp);
            throw e;
        }
    }

    /** Retorna o número de linhas alteradas (0 = agendamento inexistente). */
    static int concluir(long ag) throws SQLException {
        return executar("UPDATE agendamento SET status = 'CONCLUIDO' WHERE id_agendamento = ?", ag);
    }

    static int cancelar(long ag) throws SQLException {
        return executar("UPDATE agendamento SET status = 'CANCELADO' WHERE id_agendamento = ?", ag);
    }

    static int apagarProfissional(long prof) throws SQLException {
        return executar("DELETE FROM profissional WHERE id_profissional = ?", prof);
    }

    static String status(long ag) throws SQLException {
        return texto("SELECT status FROM agendamento WHERE id_agendamento = ?", ag);
    }

    // ------------------------------------------------------------------
    // JDBC utilitário
    // ------------------------------------------------------------------

    static int executar(String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = preparar(sql, params)) { return ps.executeUpdate(); }
    }

    static long id(String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = preparar(sql, params); ResultSet rs = ps.executeQuery()) {
            rs.next();
            return rs.getLong(1);
        }
    }

    static long contar(String sql, Object... params) throws SQLException {
        return id(sql, params);
    }

    static String texto(String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = preparar(sql, params); ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getString(1) : null;
        }
    }

    static BigDecimal decimal(String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = preparar(sql, params); ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getBigDecimal(1) : null;
        }
    }

    /** Executa a consulta e devolve cada linha como lista de colunas (texto). */
    static List<List<String>> linhas(String sql, Object... params) throws SQLException {
        List<List<String>> out = new ArrayList<>();
        try (PreparedStatement ps = preparar(sql, params); ResultSet rs = ps.executeQuery()) {
            int n = rs.getMetaData().getColumnCount();
            while (rs.next()) {
                List<String> l = new ArrayList<>();
                for (int i = 1; i <= n; i++) l.add(rs.getString(i));
                out.add(l);
            }
        }
        return out;
    }

    static PreparedStatement preparar(String sql, Object... params) throws SQLException {
        PreparedStatement ps = con.prepareStatement(sql);
        for (int i = 0; i < params.length; i++) ps.setObject(i + 1, params[i]);
        return ps;
    }

    static BigDecimal dec(String v) { return new BigDecimal(v); }

    // ------------------------------------------------------------------
    // Mini framework de verificação
    // ------------------------------------------------------------------

    @FunctionalInterface
    interface Acao { void run() throws SQLException; }

    static void verifica(String desc, boolean cond) {
        if (cond) { ok++; System.out.println("  [OK]    " + desc); }
        else { falhas++; System.out.println("  [FALHA] " + desc); }
    }

    /** Alerta sobre comportamento do banco que talvez não seja o desejado (não conta como falha). */
    static void aviso(String desc) {
        avisos++;
        System.out.println("  [AVISO] " + desc);
    }

    /**
     * Executa a ação e diz se o banco a rejeitou. Usa savepoint porque, no
     * PostgreSQL, um erro invalida o resto da transação.
     */
    static boolean lanca(Acao acao) {
        Savepoint sp;
        try { sp = con.setSavepoint(); } catch (SQLException e) { throw new RuntimeException(e); }
        try {
            acao.run();
            con.releaseSavepoint(sp);
            return false;
        } catch (SQLException e) {
            try { con.rollback(sp); } catch (SQLException ex) { throw new RuntimeException(ex); }
            String msg = e.getMessage() == null ? "" : e.getMessage().lines().findFirst().orElse("");
            System.out.println("          (erro esperado [" + e.getSQLState() + "]: " + msg + ")");
            return true;
        }
    }

    /** Desfaz tudo, mostra o resultado e sai com código 1 se houve falha. */
    static void fim() {
        try { con.rollback(); con.close(); } catch (SQLException ignored) {}
        System.out.println("\nResultado: " + ok + " ok, " + falhas + " falha(s)"
                + (avisos > 0 ? ", " + avisos + " aviso(s)" : ""));
        if (falhas > 0) System.exit(1);
    }
}
