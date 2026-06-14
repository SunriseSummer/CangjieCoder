package cangjiecoder.httpx

import stdx.net.http.*
import cangjiecoder.common.*

/**
 * `chat/completions` 客户端：封装 stdx HTTP
 * 自动处理 HTTPS、Bearer 鉴权，并支持 SSE 流式回调
 */
public type StreamCallback = (String) -> Unit

// HTTP 超时配置（秒）
let HTTP_READ_TIMEOUT_SECONDS: Int64 = 180
let HTTP_WRITE_TIMEOUT_SECONDS: Int64 = 30

// 错误响应体截断限制（字节）
let ERROR_BODY_TRUNCATE_LIMIT: Int64 = 400

public class ChatClient <: IChatClient {
    let readTimeoutSeconds: Int64

    public init(timeoutSeconds!: Int64 = HTTP_READ_TIMEOUT_SECONDS) {
        this.readTimeoutSeconds = timeoutSeconds
    }

    /** 构建并发送 HTTP 请求，处理错误响应，返回 (httpClient, resp) */
    func executeRequest(req: ChatRequest, accept: String): (Client, HttpResponse) {
        let httpClient = buildHttpClient(endpoint: req.endpoint, readTimeoutSec: this.readTimeoutSeconds)
        let httpReq = HttpRequestBuilder()
            .post()
            .url(req.endpoint)
            .header("Content-Type", "application/json")
            .header("Accept", accept)
            .header("Authorization", "Bearer ${req.apiKey}")
            .body(req.toJsonBody())
            .build()
        let resp = try {
            httpClient.send(httpReq)
        } catch (e: Exception) {
            httpClient.close()
            throw annotateTlsError(e)
        }
        if (resp.status >= 400) {
            try {
                let body = readBodyAsString(resp.body)
                throw HttpException("HTTP ${resp.status}: ${truncateWithEllipsis(body, ERROR_BODY_TRUNCATE_LIMIT)}")
            } finally {
                resp.close()
                httpClient.close()
            }
        }
        return (httpClient, resp)
    }

    public func send(req: ChatRequest, onChunk: ?StreamCallback): String {
        let accept = if (req.stream) {
            "text/event-stream"
        } else {
            "application/json"
        }
        let (httpClient, resp) = executeRequest(req, accept)
        try {
            if (req.stream) {
                return readStream(resp, onChunk)
            }
            return extractAssistantText(readBodyAsString(resp.body))
        } finally {
            resp.close()
            httpClient.close()
        }
    }

    /**
     * 非流式发送，返回完整 assistant 消息
     * 三元组：(content, toolCalls, reasoningContent)
     * reasoningContent 为思考模型的推理内容，需要在后续请求中回传
     */
    public func sendForMessage(req: ChatRequest): (String, Array<ToolCall>, String) {
        req.stream = false
        let (httpClient, resp) = executeRequest(req, "application/json")
        try {
            return extractAssistantMessage(readBodyAsString(resp.body))
        } finally {
            resp.close()
            httpClient.close()
        }
    }
}

func buildHttpClient(endpoint!: String = "", readTimeoutSec!: Int64 = HTTP_READ_TIMEOUT_SECONDS): Client {
    let builder = ClientBuilder()
        .readTimeout(Duration.second * readTimeoutSec)
        .writeTimeout(Duration.second * HTTP_WRITE_TIMEOUT_SECONDS)
    let tls = buildTlsConfig(endpoint)
    return builder.tlsConfig(tls).build()
}
