package team.prisma.plugin.http;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import team.prisma.plugin.config.PluginConfig;

import java.io.IOException;
import java.net.InetAddress;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.logging.Logger;

public final class SupabaseClient {

    private static final Logger LOG = Logger.getLogger("PrismaPlugin");

    private final HttpClient http;
    private final String supabaseBaseUrl;
    private final String restBaseUrl;
    private final String serviceRoleKey;
    private final Duration timeout;
    private final ExecutorService executor;
    private final Gson gson = new Gson();


    public SupabaseClient(PluginConfig config) {
        this.supabaseBaseUrl = config.supabaseUrl();
        this.restBaseUrl = config.supabaseUrl() + "/rest/v1";
        this.serviceRoleKey = config.serviceRoleKey();
        this.timeout = Duration.ofSeconds(config.httpTimeoutSeconds());

        AtomicInteger counter = new AtomicInteger();
        ThreadFactory namedThreads = runnable -> {
            Thread thread = new Thread(runnable, "prisma-supabase-" + counter.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        };
        this.executor = Executors.newFixedThreadPool(4, namedThreads);
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    public ExecutorService executor() {
        return executor;
    }

    public void shutdown() {
        executor.shutdown();
    }

    public JsonObject postRpcSync(String functionName, JsonObject body) throws IOException, InterruptedException {
        JsonElement parsed = postRpcJsonSync(functionName, body);
        return parsed != null && parsed.isJsonObject() ? parsed.getAsJsonObject() : new JsonObject();
    }

    /** Performs an RPC while preserving array/scalar responses for typed gateways. */
    public JsonElement postRpcJsonSync(String functionName, JsonObject body) throws IOException, InterruptedException {
        HttpRequest request = baseRequest("/rpc/" + encode(functionName))
            .POST(HttpRequest.BodyPublishers.ofString(gson.toJson(body)))
            .build();
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() >= 300) {
            String details = abbreviate(response.body());
            throw new IOException("RPC " + functionName + " returned HTTP " + response.statusCode()
                + (details.isBlank() ? "" : ": " + details));
        }
        return gson.fromJson(response.body(), JsonElement.class);
    }

    public CompletableFuture<JsonObject> postRpcAsync(String functionName, JsonObject body) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                return postRpcSync(functionName, body);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }, executor);
    }









    public DiagnosticResult diagnose(String nickname) {
        String host = URI.create(supabaseBaseUrl).getHost();

        long dnsStart = System.nanoTime();
        String dnsResult;
        try {
            InetAddress[] addresses = InetAddress.getAllByName(host);
            long ms = elapsedMillis(dnsStart);
            StringBuilder resolved = new StringBuilder();
            for (int i = 0; i < addresses.length; i++) {
                if (i > 0) resolved.append(", ");
                resolved.append(addresses[i].getHostAddress());
            }
            dnsResult = "OK (" + ms + " ms): " + resolved;
        } catch (Exception e) {
            dnsResult = "FAIL (" + elapsedMillis(dnsStart) + " ms): " + errorMessage(e);
        }

        Probe root = probe(
            HttpRequest.newBuilder(URI.create(withTrailingSlash(supabaseBaseUrl)))
                .timeout(timeout)
                .header("apikey", serviceRoleKey)
                .header("Authorization", "Bearer " + serviceRoleKey)
                .GET()
                .build()
        );

        Probe rest = probe(
            HttpRequest.newBuilder(URI.create(withTrailingSlash(restBaseUrl)))
                .timeout(timeout)
                .header("apikey", serviceRoleKey)
                .header("Authorization", "Bearer " + serviceRoleKey)
                .GET()
                .build()
        );

        RpcProbe rpc = probeRpc(nickname);
        return new DiagnosticResult(
            dnsResult,
            formatProbe(root),
            formatProbe(rest),
            formatProbe(rpc.probe()),
            rpc.status(),
            rpc.whitelisted(),
            rpc.banned()
        );
    }

    private RpcProbe probeRpc(String nickname) {
        long start = System.nanoTime();
        try {
            JsonObject body = new JsonObject();
            body.addProperty("p_nickname", nickname);

            HttpRequest request = baseRequest("/rpc/" + RpcNames.GET_MINECRAFT_USER)
                .timeout(timeout)
                .POST(HttpRequest.BodyPublishers.ofString(gson.toJson(body)))
                .build();

            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            long ms = elapsedMillis(start);

            JsonObject payload = null;
            try {
                JsonElement parsed = gson.fromJson(response.body(), JsonElement.class);
                if (parsed != null && parsed.isJsonObject()) {
                    payload = parsed.getAsJsonObject();
                }
            } catch (Exception ignored) {
            }

            String status = payload != null && payload.has("status") && !payload.get("status").isJsonNull()
                ? payload.get("status").getAsString() : null;
            boolean whitelisted = payload != null && payload.has("is_whitelisted")
                && payload.get("is_whitelisted").getAsBoolean();
            boolean banned = payload != null && payload.has("is_banned")
                && payload.get("is_banned").getAsBoolean();

            String detail = response.statusCode() >= 300
                ? response.statusCode() + " (" + ms + " ms): " + abbreviate(response.body())
                : response.statusCode() + " (" + ms + " ms)";

            return new RpcProbe(
                new Probe(response.statusCode(), ms, detail),
                status,
                whitelisted,
                banned
            );
        } catch (Exception e) {
            long ms = elapsedMillis(start);
            return new RpcProbe(
                new Probe(null, ms, "FAIL (" + ms + " ms): " + errorMessage(e)),
                null,
                false,
                false
            );
        }
    }

    private Probe probe(HttpRequest request) {
        long start = System.nanoTime();
        try {
            HttpResponse<Void> response = http.send(request, HttpResponse.BodyHandlers.discarding());
            long ms = elapsedMillis(start);
            return new Probe(
                response.statusCode(),
                ms,
                response.statusCode() + " (" + ms + " ms)"
            );
        } catch (Exception e) {
            long ms = elapsedMillis(start);
            return new Probe(null, ms, "FAIL (" + ms + " ms): " + errorMessage(e));
        }
    }

    private HttpRequest.Builder baseRequest(String pathAndQuery) {
        return HttpRequest.newBuilder()
            .uri(URI.create(restBaseUrl + pathAndQuery))
            .timeout(timeout)
            .header("apikey", serviceRoleKey)
            .header("Authorization", "Bearer " + serviceRoleKey)
            .header("Content-Type", "application/json");
    }


    public static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }


    private static String abbreviate(String value) {
        if (value == null) return "";
        return value.length() <= 180 ? value : value.substring(0, 180) + "...";
    }

    private static String withTrailingSlash(String value) {
        return value.endsWith("/") ? value : value + "/";
    }

    private static long elapsedMillis(long startNanos) {
        return Math.max(0L, (System.nanoTime() - startNanos) / 1_000_000L);
    }

    private static String errorMessage(Exception e) {
        String message = e.getMessage();
        if (message == null || message.isBlank()) return e.getClass().getSimpleName();
        return e.getClass().getSimpleName() + ": " + message;
    }

    private static String formatProbe(Probe probe) {
        return probe.detail();
    }

    private record Probe(Integer statusCode, long millis, String detail) {}

    private record RpcProbe(Probe probe, String status, boolean whitelisted, boolean banned) {}

    public record DiagnosticResult(
        String dns,
        String rootHttp,
        String restHttp,
        String rpcHttp,
        String rpcStatus,
        boolean rpcWhitelisted,
        boolean rpcBanned
    ) {}
}
